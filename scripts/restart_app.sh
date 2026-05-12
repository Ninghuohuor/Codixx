#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/Codixx.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/Codixx"
BUNDLE_ID="local.codixx.app"

"$ROOT_DIR/scripts/package_app.sh"

matching_pids() {
  pgrep -f "$EXECUTABLE" || true
}

wait_for_stop() {
  local remaining="${1:-80}"
  while [[ "$remaining" -gt 0 ]]; do
    if [[ -z "$(matching_pids)" ]]; then
      return 0
    fi
    sleep 0.1
    remaining=$((remaining - 1))
  done
  return 1
}

wait_for_start() {
  local remaining="${1:-80}"
  while [[ "$remaining" -gt 0 ]]; do
    local pids
    pids="$(matching_pids)"
    if [[ -n "$pids" ]]; then
      echo "$pids"
      return 0
    fi
    sleep 0.1
    remaining=$((remaining - 1))
  done
  return 1
}

existing_pids="$(matching_pids)"
if [[ -n "$existing_pids" ]]; then
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  kill $existing_pids >/dev/null 2>&1 || true
  if ! wait_for_stop 80; then
    kill -9 $(matching_pids) >/dev/null 2>&1 || true
    wait_for_stop 30 || {
      echo "Codixx did not stop cleanly" >&2
      exit 1
    }
  fi
fi

if ! open -n "$APP_DIR" >/dev/null 2>&1; then
  nohup "$EXECUTABLE" >/tmp/codixx-app.log 2>&1 &
fi

started_pids="$(wait_for_start 80)" || {
  echo "Codixx did not start" >&2
  exit 1
}

sleep 2
stable_pids="$(matching_pids)"
if [[ -z "$stable_pids" ]]; then
  echo "Codixx started but exited immediately" >&2
  if [[ -f /tmp/codixx-app.log ]]; then
    sed -n '1,120p' /tmp/codixx-app.log >&2
  fi
  exit 1
fi

echo "Restarted Codixx: $stable_pids"
