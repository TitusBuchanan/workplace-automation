"""
Audit rules engine for Microsoft 365 access and license hygiene.

Rules are intentionally simple, readable, and easy to extend.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional


Finding = Dict[str, Any]


@dataclass(frozen=True)
class AuditConfig:
    inactivity_days: int = 90


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _parse_iso_datetime(value: Any) -> Optional[datetime]:
    """
    Parse Graph ISO date strings like '2024-10-01T12:34:56Z'.
    Returns None if missing/unparseable.
    """

    if not value or not isinstance(value, str):
        return None

    s = value.strip()
    if not s:
        return None

    # Handle the common trailing 'Z' format for UTC.
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"

    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return None


def _user_license_sku_ids(user: Dict[str, Any]) -> List[str]:
    assigned = user.get("assignedLicenses") or []
    if not isinstance(assigned, list):
        return []
    sku_ids: List[str] = []
    for lic in assigned:
        # Support either:
        # - Graph-like shape: [{"skuId": "..."}]
        # - Offline export shape: ["SKU_ID_OR_NAME", ...]
        if isinstance(lic, dict) and lic.get("skuId"):
            sku_ids.append(str(lic["skuId"]))
        elif isinstance(lic, str) and lic.strip():
            sku_ids.append(lic.strip())
    return sku_ids


def _user_license_names(user: Dict[str, Any], sku_map: Dict[str, str]) -> List[str]:
    return [sku_map.get(sku_id, sku_id) for sku_id in _user_license_sku_ids(user)]


def _base_finding(
    *,
    risk_type: str,
    severity: str,
    user: Dict[str, Any],
    details: str,
    evidence: Dict[str, Any],
    recommended_action: str,
) -> Finding:
    return {
        "risk_type": risk_type,
        "severity": severity,
        "user_id": user.get("id"),
        "upn": user.get("userPrincipalName"),
        "display_name": user.get("displayName"),
        "details": details,
        "evidence": evidence,
        "recommended_action": recommended_action,
    }


def rule_disabled_user_with_licenses(
    users: List[Dict[str, Any]],
    sku_map: Dict[str, str],
    config: AuditConfig,
) -> List[Finding]:
    findings: List[Finding] = []
    for user in users:
        account_enabled = user.get("accountEnabled")
        license_names = _user_license_names(user, sku_map)
        if account_enabled is False and license_names:
            findings.append(
                _base_finding(
                    risk_type="disabled_user_with_licenses",
                    severity="high",
                    user=user,
                    details="User account is disabled but still has active license assignments.",
                    evidence={
                        "accountEnabled": account_enabled,
                        "licenses": license_names,
                    },
                    recommended_action="Remove unnecessary licenses or confirm the account should remain disabled and licensed.",
                )
            )
    return findings


def rule_inactive_user_over_threshold(
    users: List[Dict[str, Any]],
    sku_map: Dict[str, str],
    config: AuditConfig,
) -> List[Finding]:
    """
    Inactive users (> N days). Runs only if a sign-in timestamp exists on the user object.

    Notes:
    - Basic Graph reads typically do NOT include sign-in activity.
    - If your environment fetches sign-in activity (beta or report endpoints), populate:
      user["signInActivity"]["lastSignInDateTime"] or user["lastSignInDateTime"].
    """

    threshold = _now_utc() - timedelta(days=int(config.inactivity_days))
    findings: List[Finding] = []

    for user in users:
        # Support a couple of common shapes:
        # - beta users endpoint: user["signInActivity"]["lastSignInDateTime"]
        # - custom enrichment: user["lastSignInDateTime"]
        sign_in_activity = user.get("signInActivity") if isinstance(user.get("signInActivity"), dict) else {}
        last_sign_in_raw = sign_in_activity.get("lastSignInDateTime") or user.get("lastSignInDateTime")
        last_sign_in = _parse_iso_datetime(last_sign_in_raw)

        if last_sign_in is None:
            continue  # data not available; skip rule

        if last_sign_in < threshold:
            findings.append(
                _base_finding(
                    risk_type="inactive_user_over_threshold",
                    severity="medium",
                    user=user,
                    details=f"No sign-in recorded in the last {config.inactivity_days} days.",
                    evidence={
                        "lastSignInDateTime": last_sign_in_raw,
                        "thresholdDateTime": threshold.isoformat(),
                        "licenses": _user_license_names(user, sku_map),
                    },
                    recommended_action="Review account necessity; disable or remove licenses if the user is no longer active.",
                )
            )

    return findings


def rule_licensed_user_without_signin_activity(
    users: List[Dict[str, Any]],
    sku_map: Dict[str, str],
    config: AuditConfig,
) -> List[Finding]:
    """
    Licensed users with no sign-in activity information at all.

    This is a weaker signal than an inactivity threshold and should only run when
    sign-in data is expected to exist (i.e., you've enabled enrichment).
    """

    findings: List[Finding] = []

    for user in users:
        license_names = _user_license_names(user, sku_map)
        if not license_names:
            continue

        sign_in_activity = user.get("signInActivity") if isinstance(user.get("signInActivity"), dict) else {}
        last_sign_in_raw = sign_in_activity.get("lastSignInDateTime") or user.get("lastSignInDateTime")

        # If the property doesn't exist at all, we can't assume it's "no sign-in" unless
        # the dataset is known to include it. We treat this rule as optional and skip
        # unless at least one user has a sign-in field present.
        #
        # The runner will decide whether to enable this rule based on dataset shape.
        if last_sign_in_raw in (None, ""):
            findings.append(
                _base_finding(
                    risk_type="licensed_user_without_signin_activity",
                    severity="low",
                    user=user,
                    details="User is licensed but has no sign-in activity field populated.",
                    evidence={
                        "licenses": license_names,
                    },
                    recommended_action="If sign-in activity is expected, investigate why it's missing and review license necessity.",
                )
            )

    return findings


def rule_user_without_mfa(
    users: List[Dict[str, Any]],
    sku_map: Dict[str, str],
    config: AuditConfig,
) -> List[Finding]:
    """
    Users without MFA (if available).

    This project keeps MFA checks optional because MFA posture is not reliably available
    from basic user/license reads. If you enrich users with a boolean like user["mfaEnabled"],
    this rule will use it.
    """

    findings: List[Finding] = []
    for user in users:
        if "mfaEnabled" not in user:
            continue  # data not available; skip rule

        mfa_enabled = user.get("mfaEnabled")
        if mfa_enabled is False:
            findings.append(
                _base_finding(
                    risk_type="user_without_mfa",
                    severity="high",
                    user=user,
                    details="User appears to be missing MFA registration/enforcement.",
                    evidence={"mfaEnabled": mfa_enabled},
                    recommended_action="Require MFA for the user (policy-based enforcement preferred) and validate registration.",
                )
            )
    return findings


def run_audit(
    users: List[Dict[str, Any]],
    sku_map: Dict[str, str],
    config: AuditConfig,
) -> List[Finding]:
    """
    Run all applicable audit rules and return a normalized list of findings.
    """

    findings: List[Finding] = []

    # Always-on rules (basic data)
    findings.extend(rule_disabled_user_with_licenses(users, sku_map, config))

    # Optional rules: only run when the dataset contains the required keys.
    has_any_signin_field = any(
        ("lastSignInDateTime" in u)
        or (isinstance(u.get("signInActivity"), dict) and "lastSignInDateTime" in u.get("signInActivity", {}))
        for u in users
        if isinstance(u, dict)
    )
    if has_any_signin_field:
        findings.extend(rule_inactive_user_over_threshold(users, sku_map, config))
        findings.extend(rule_licensed_user_without_signin_activity(users, sku_map, config))

    has_any_mfa_field = any(isinstance(u, dict) and ("mfaEnabled" in u) for u in users)
    if has_any_mfa_field:
        findings.extend(rule_user_without_mfa(users, sku_map, config))

    return findings

