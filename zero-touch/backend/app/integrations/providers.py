from typing import Dict, List


class ProvisionResult:
    def __init__(self, ok: bool, actions: List[str], error: str | None = None):
        self.ok = ok
        self.actions = actions
        self.error = error


def for_windows(blueprint: dict, facts: dict) -> ProvisionResult:
    actions = []
    packages = blueprint.get("packages", {}).get("choco", [])
    if packages:
        actions.append(f"choco install {' '.join(packages)} -y")
    users = blueprint.get("users", {}).get("local", [])
    for user in users:
        actions.append(f"powershell.exe New-LocalUser {user.get('name')}")
    return ProvisionResult(ok=True, actions=actions)


def for_macos_linux(blueprint: dict, facts: dict) -> ProvisionResult:
    actions = []
    pkgs = blueprint.get("packages", {}).get("brew", []) or blueprint.get(
        "packages", {}
    ).get("apt", [])
    if pkgs:
        actions.append(f"install packages: {' '.join(pkgs)}")
    files = blueprint.get("files", {})
    for path, content in files.items():
        actions.append(f"write file {path} ({len(str(content))} chars)")
    return ProvisionResult(ok=True, actions=actions)


def for_mobile_or_iot(blueprint: dict, facts: dict) -> ProvisionResult:
    webhook = blueprint.get("security", {}).get("mdm_webhook")
    actions = []
    if webhook:
        actions.append(f"invoke webhook {webhook}")
    return ProvisionResult(ok=True, actions=actions)


def dispatch(os_type: str, blueprint: dict, facts: dict) -> ProvisionResult:
    lowered = os_type.lower()
    if "windows" in lowered:
        return for_windows(blueprint, facts)
    if lowered in {"macos", "darwin", "linux"}:
        return for_macos_linux(blueprint, facts)
    return for_mobile_or_iot(blueprint, facts)
