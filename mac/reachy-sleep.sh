#!/usr/bin/env bash
# Put Reachy fully to sleep: stops the conversation app, which triggers its
# shutdown sequence (goto_sleep → motor disable). Head folds down, no more
# wobbles / idle animations / head tracking.
#
# Usage: ./reachy-sleep.sh
#        ROBOT_IP=192.168.1.20 ./reachy-sleep.sh
set -euo pipefail

: "${ROBOT_IP:=10.0.0.154}"
BASE="http://${ROBOT_IP}:8000"

echo "==> Checking Reachy at ${ROBOT_IP} …"
if ! curl -sS --max-time 5 -o /dev/null "${BASE}/api/daemon/status"; then
  echo "!! Daemon not reachable. Nothing to do."; exit 1
fi

APP=$(curl -sS --max-time 5 "${BASE}/api/apps/current-app-status" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print((d or {}).get('info',{}).get('name') or '')")

if [ -n "$APP" ]; then
  echo "==> Stopping app '${APP}' (this folds Reachy down + disables motors) …"
  curl -sS --max-time 15 -X POST "${BASE}/api/apps/stop-current-app" >/dev/null
  echo "    App stop requested; waiting for goto_sleep sequence …"
  sleep 6
else
  echo "==> No app running. Making sure she's folded and motors off …"
  # If motors are on, gently goto sleep pose then disable.
  MODE=$(curl -sS --max-time 5 "${BASE}/api/motors/status" | python3 -c "import sys,json; print(json.load(sys.stdin).get('mode',''))")
  if [ "$MODE" = "enabled" ]; then
    curl -sS --max-time 15 -X POST "${BASE}/api/move/play/goto_sleep" >/dev/null || true
    sleep 3
    curl -sS --max-time 5 -X POST "${BASE}/api/motors/set_mode/disabled" >/dev/null || true
  fi
fi

# Final report
sleep 1
PITCH=$(curl -sS --max-time 5 "${BASE}/api/state/present_head_pose" | \
  python3 -c "import sys,json,math; d=json.load(sys.stdin); print(round(math.degrees(d['pitch']),1))")
MODE=$(curl -sS --max-time 5 "${BASE}/api/motors/status" | python3 -c "import sys,json; print(json.load(sys.stdin).get('mode',''))")
echo "==> Reachy: pitch=${PITCH}° motors=${MODE}"
echo "    Sleeping. Run reachy-wake.sh to bring her back."
