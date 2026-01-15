#!/usr/bin/env bash
set -euo pipefail

API_BASE=${API_BASE:-https://api.localhost}
TOKEN=${TOKEN:-${1:-}}

if [[ -z "$TOKEN" ]]; then
  echo "Usage: TOKEN=<token> $0"
  exit 1
fi

payload=$(cat <<'EOF'
{
  "hostname": "__HOSTNAME__",
  "os_type": "__OS__",
  "arch": "__ARCH__",
  "facts": {
    "ip": "__IP__"
  },
  "token": "__TOKEN__"
}
EOF
)

payload=${payload/__HOSTNAME__/$(hostname)}
payload=${payload/__OS__/$(uname -s)}
payload=${payload/__ARCH__/$(uname -m)}
payload=${payload/__IP__/$(hostname -I | awk '{print $1}')}
payload=${payload/__TOKEN__/$TOKEN}

curl -s -X POST "$API_BASE/enrollment/register" \
  -H "Content-Type: application/json" \
  -d "$payload"
