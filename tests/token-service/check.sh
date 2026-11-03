#!/usr/bin/env bash
# Purpose: Check the token service against the sandbox App: a narrowed token, the refusals and a log without tokens.
# Usage: APP_KEY_PATH=<private key file of the sandbox App> bash tests/token-service/check.sh
# Arguments: none; APP_KEY_PATH required, TOKEN_SERVICE_APP_ID optional (default 5593711, the sandbox App)
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed or the setup is missing
set -euo pipefail

root="${BASH_SOURCE[0]%/*}/../.."
export TOKEN_SERVICE_KEY_FILE="${APP_KEY_PATH:?APP_KEY_PATH is required}"
export TOKEN_SERVICE_APP_ID="${TOKEN_SERVICE_APP_ID:-5593711}"
export TOKEN_SERVICE_PORT="${TOKEN_SERVICE_PORT:-8790}"
export TOKEN_SERVICE_UID="$(id -u)" TOKEN_SERVICE_GID="$(id -g)"
repo="edotz/git-workflow-sandbox"
url="http://127.0.0.1:${TOKEN_SERVICE_PORT}/token"
compose=(docker compose -f "${root}/.docker/compose.token-service.yaml" -p git-workflow-token-check)
failed=0

cleanup() { "${compose[@]}" down -t 2 >/dev/null 2>&1 || true; }
trap cleanup EXIT

case_result() {
  if [[ "$2" == "yes" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    failed=1
  fi
}

# Post one request and keep status and body in files; the developer token goes in through a header file, never an argument.
post() {
  local bearer="$1" body="$2"
  printf 'Authorization: Bearer %s\n' "$bearer" > "${work}/header"
  status=$(curl -s -o "${work}/body" -w '%{http_code}' -H "@${work}/header" -H 'Content-Type: application/json' -d "$body" "$url")
  rm -f "${work}/header"
}

work=$(mktemp -d)
trap 'rm -rf "$work"; cleanup' EXIT
developer_token=$(gh auth token)

"${compose[@]}" up -d --build >/dev/null 2>&1
for _ in $(seq 1 30); do
  if curl -s -o /dev/null "$url"; then break; fi
  sleep 1
done

post "$developer_token" "{\"repo\":\"${repo}\",\"set\":\"contents\"}"
ok=no
if [[ "$status" == 200 ]] && jq -e '(.token|length>0) and (.expires_at|length>0) and .permissions.contents=="write" and .permissions.metadata=="read" and (.permissions|keys|length==2) and .repository==["git-workflow-sandbox"]' "${work}/body" >/dev/null; then ok=yes; fi
case_result "member gets a token for one repository with contents write and metadata read" "$ok"

post "not-a-token" "{\"repo\":\"${repo}\",\"set\":\"contents\"}"
ok=no; if [[ "$status" == 401 ]] && jq -e '.error=="login not accepted"' "${work}/body" >/dev/null; then ok=yes; fi
case_result "an invalid login token is refused: login not accepted" "$ok"

post "$developer_token" "{\"repo\":\"edotz/no-such-repository-for-the-check\",\"set\":\"contents\"}"
ok=no; if [[ "$status" == 404 ]] && jq -e '.error=="repository not installed"' "${work}/body" >/dev/null; then ok=yes; fi
case_result "a repository without the installation is refused: repository not installed" "$ok"

post "$developer_token" "{\"repo\":\"${repo}\",\"set\":\"nothing\"}"
ok=no; if [[ "$status" == 400 ]] && jq -e '.error=="permission set unknown"' "${work}/body" >/dev/null; then ok=yes; fi
case_result "an unknown permission set is refused" "$ok"

post "$developer_token" "{\"repo\":\"someone-else/repository\",\"set\":\"contents\"}"
ok=no; if [[ "$status" == 403 ]]; then ok=yes; fi
case_result "a repository outside the organisation is refused" "$ok"

logs=$("${compose[@]}" logs --no-color 2>&1)
ok=yes
if grep -qE 'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_' <<<"$logs"; then ok=no; fi
if grep -qF -- "$developer_token" <<<"$logs"; then ok=no; fi
case_result "the container log holds no token" "$ok"

exit "$failed"
