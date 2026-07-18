#!/usr/bin/env bash
# Run the Flutter app with Supabase config pulled from backend/.env, so credentials
# are never pasted onto a command line (or into shell history). The backend base URL
# defaults to this machine's LAN IP (so a physical device on the same Wi-Fi reaches the
# local docker-compose backend); override with API_BASE_URL=...
#
#   ./scripts/run.sh                  # first available device
#   ./scripts/run.sh -d chrome        # browser (use API_BASE_URL=http://localhost:8000/v1)
#   ./scripts/run.sh -d <device-id>   # a connected phone (see: flutter devices)
#
# Any extra arguments are forwarded to `flutter run` verbatim.
set -euo pipefail

MOBILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${MOBILE_DIR}/../backend/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "error: ${ENV_FILE} not found — copy backend/.env.example and fill it in." >&2
  exit 1
fi

# Read only the two keys we need. Values may contain '=', so split on the first one
# only; strip surrounding quotes if present.
read_env() {
  local key="$1" line value
  line="$(grep -m1 -E "^${key}=" "${ENV_FILE}" || true)"
  [[ -z "${line}" ]] && return 1
  value="${line#*=}"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "${value}"
}

SUPABASE_URL="$(read_env SUPABASE_URL)" || {
  echo "error: SUPABASE_URL missing from ${ENV_FILE}" >&2
  exit 1
}
SUPABASE_ANON_KEY="$(read_env SUPABASE_ANON_KEY)" || {
  echo "error: SUPABASE_ANON_KEY missing from ${ENV_FILE}" >&2
  exit 1
}

# Backend base URL. Override with `API_BASE_URL=... ./scripts/run.sh`; otherwise target the
# local backend (docker compose) on this machine's LAN IP, so a physical device on the same
# Wi-Fi can reach it. `localhost` would resolve to the *device*, not this machine.
if [[ -z "${API_BASE_URL:-}" ]]; then
  LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  API_BASE_URL="http://${LAN_IP:-localhost}:8000/v1"
fi
echo "Using API_BASE_URL=${API_BASE_URL}" >&2

cd "${MOBILE_DIR}"
exec flutter run \
  --dart-define=API_BASE_URL="${API_BASE_URL}" \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  "$@"
