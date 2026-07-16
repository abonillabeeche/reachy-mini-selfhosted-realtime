#!/usr/bin/env bash
# Launch the Reachy Mini Control desktop app cleanly:
#   - Stop any active `reachy listen` session (frees our SSH grab of the mic)
#   - Release the daemon's media (so the app's WebRTC can grab mic+cam)
#   - Open the app
#
# Usage: reachy-open-control [--no-release]
set -euo pipefail

: "${ROBOT_IP:=10.0.0.154}"
BASE="http://${ROBOT_IP}:8000"

# 1. If our listen toggle is running, stop it — it holds Reachy's mic over SSH.
if [ -x "${HOME}/bin/reachy-listen-toggle" ] && "${HOME}/bin/reachy-listen-toggle" status | grep -q on; then
  echo "==> Stopping listen session so the app can take the mic…"
  "${HOME}/bin/reachy-listen-toggle" stop
  sleep 1
fi

# 2. Ask the daemon to release its media pipeline (audio in particular).
if [ "${1:-}" != "--no-release" ]; then
  echo "==> Releasing daemon media…"
  curl -sS --max-time 6 -X POST "${BASE}/api/media/release" >/dev/null || true
  sleep 1
fi

# 3. Launch the desktop app.
echo "==> Opening Reachy Mini Control…"
open -a "Reachy Mini Control"
