#!/usr/bin/env bash
# Wake Reachy: enables motors, smoothly lifts head to neutral over 5s, then
# starts the conversation app (which sees she's already awake and skips its
# own wake-up sequence — so no double-motion).
#
# Usage: ./reachy-wake.sh
#        ROBOT_IP=192.168.1.20 ./reachy-wake.sh
#        VOLUME=80 ./reachy-wake.sh    # override speaker level after wake
set -euo pipefail

: "${ROBOT_IP:=10.0.0.154}"
: "${VOLUME:=100}"
: "${APP:=reachy_mini_conversation_app}"
BASE="http://${ROBOT_IP}:8000"

echo "==> Checking Reachy at ${ROBOT_IP} …"
if ! curl -sS --max-time 5 -o /dev/null "${BASE}/api/daemon/status"; then
  echo "!! Daemon not reachable. Is Reachy powered on?"; exit 1
fi

echo "==> Enabling motors …"
curl -sS --max-time 5 -X POST "${BASE}/api/motors/set_mode/enabled" >/dev/null

echo "==> Slow 5-second goto to upright + antennas raised …"
curl -sS --max-time 15 -X POST "${BASE}/api/move/goto" \
  -H "Content-Type: application/json" \
  -d '{"head":{"x":0,"y":0,"z":0,"roll":0,"pitch":0,"yaw":0,"degrees":true,"mm":true},"antennas":[-0.1745, 0.1745],"body_yaw":0,"duration":5.0}' >/dev/null
sleep 6

echo "==> Restoring volume to ${VOLUME} …"
curl -sS --max-time 5 -X POST "${BASE}/api/volume/set" \
  -H "Content-Type: application/json" \
  -d "{\"volume\":${VOLUME}}" >/dev/null

RUNNING=$(curl -sS --max-time 5 "${BASE}/api/apps/current-app-status" | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print((d or {}).get('state') or '')")
if [ "$RUNNING" = "running" ]; then
  echo "==> Conversation app already running; leaving it alone."
else
  echo "==> Starting conversation app '${APP}' …"
  curl -sS --max-time 15 -X POST "${BASE}/api/apps/start-app/${APP}" >/dev/null
  echo "    (Reachy's already upright, so the app's wake_up_if_sleeping is a no-op.)"
fi

sleep 2
PITCH=$(curl -sS --max-time 5 "${BASE}/api/state/present_head_pose" | \
  python3 -c "import sys,json,math; d=json.load(sys.stdin); print(round(math.degrees(d['pitch']),1))")
MODE=$(curl -sS --max-time 5 "${BASE}/api/motors/status" | python3 -c "import sys,json; print(json.load(sys.stdin).get('mode',''))")
VOL=$(curl -sS --max-time 5 "${BASE}/api/volume/current" | python3 -c "import sys,json; print(json.load(sys.stdin).get('volume',''))")
echo "==> Reachy: pitch=${PITCH}° motors=${MODE} volume=${VOL}%  — ready."
