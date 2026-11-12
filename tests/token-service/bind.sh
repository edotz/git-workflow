#!/usr/bin/env bash
# Purpose: Check the address the token service listens on: loopback by default, the address of TOKEN_SERVICE_HOST when set.
# Usage: bash tests/token-service/bind.sh
# Arguments: none; needs node and the packages of the plugin root (npm ci); no GitHub App, no network, no Docker
# Output: one line per case, ok or FAIL
# Exit codes: 0 all cases hold, 1 a case failed
set -euo pipefail

root="$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)"
service="${root}/bin/modules/git/token-service.mjs"
failed=0

case_result() {
  if [[ "$2" == "yes" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    failed=1
  fi
}

work="$(mktemp -d)"
pid=""
finish() {
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap finish EXIT

# The service reads the key file at start and checks only the marker; the key is used when a token is requested.
printf '%s\n' '-----BEGIN PRIVATE KEY-----' 'not-a-real-key' '-----END PRIVATE KEY-----' > "${work}/key.pem"

# The first address of this machine that is not loopback; empty when there is none.
other_ip=""
if command -v hostname >/dev/null 2>&1; then
  for candidate in $(hostname -I 2>/dev/null || true); do
    if [[ "$candidate" != 127.* && "$candidate" != *:* && -z "$other_ip" ]]; then other_ip="$candidate"; fi
  done
fi

# Start the service on a port; sets pid and log. Args: $1 - port, then env assignments
start_service() {
  local port="$1"
  shift
  : > "${work}/log"
  env TOKEN_SERVICE_APP_ID=1 TOKEN_SERVICE_KEY_PATH="${work}/key.pem" TOKEN_SERVICE_PORT="$port" "$@" \
    node "$service" > "${work}/log" 2>&1 &
  pid=$!
  local waited=0
  while ! grep -q 'listening on' "${work}/log" && [[ "$waited" -lt 50 ]]; do
    sleep 0.1
    waited=$((waited + 1))
  done
}

stop_service() {
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  pid=""
}

reachable() {
  curl -s -o /dev/null --max-time 2 "http://$1:$2/token"
}

port=$((20000 + RANDOM % 20000))
start_service "$port"
ok=no
if grep -q "listening on 127.0.0.1:${port}" "${work}/log"; then ok=yes; fi
case_result "the service listens on 127.0.0.1 by default" "$ok"

ok=no
if reachable 127.0.0.1 "$port"; then ok=yes; fi
case_result "the service answers on the loopback address" "$ok"

if [[ -n "$other_ip" ]]; then
  ok=no
  if ! reachable "$other_ip" "$port"; then ok=yes; fi
  case_result "the service does not answer on ${other_ip}, an address of this machine that is not loopback" "$ok"
else
  case_result "no non-loopback address on this machine: only the log line proves the bind" "yes"
fi
stop_service

port=$((20000 + RANDOM % 20000))
start_service "$port" TOKEN_SERVICE_HOST=0.0.0.0
ok=no
if grep -q "listening on 0.0.0.0:${port}" "${work}/log"; then ok=yes; fi
case_result "TOKEN_SERVICE_HOST=0.0.0.0 makes the service listen on all interfaces, as in the container" "$ok"
stop_service

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
exit 0
