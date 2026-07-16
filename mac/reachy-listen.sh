#!/usr/bin/env bash
# Live-listen to Reachy's microphone from a remote Mac.
# Streams raw PCM over SSH → local `play` (from sox). Ctrl-C to stop.
#
# Usage:
#   ./reachy-listen.sh           # stops Reachy's conversation app so the mic is free,
#                                # streams, and restarts the app on exit
#   NOSLEEP=1 ./reachy-listen.sh # skip the sleep/wake — try to share mic (may fail
#                                # if the conversation app has exclusive access)
#   ROBOT_IP=192.168.1.20 ./reachy-listen.sh
set -euo pipefail

: "${ROBOT_IP:=10.0.0.154}"
: "${ROBOT_USER:=pollen}"
: "${ROBOT_PASS:=root}"
: "${NOSLEEP:=0}"
: "${ALSA_DEV:=plughw:0,0}"   # Reachy Mini Audio (card 0)
: "${RATE:=48000}"
: "${CHANS:=1}"               # 1 channel is enough for room ambience, less bandwidth
: "${BUF_MS:=200}"            # network buffer — smaller = lower latency but more glitchy

BASE="http://${ROBOT_IP}:8000"

command -v play >/dev/null || { echo "!! 'play' not found. Install sox: brew install sox"; exit 1; }
command -v sshpass >/dev/null || { echo "!! sshpass not found. Install: brew install esolitos/ipa/sshpass"; exit 1; }

app_was_running=0
if [ "$NOSLEEP" != "1" ]; then
  # Check + stop the conversation app so it releases the mic
  app_state=$(curl -sS --max-time 5 "${BASE}/api/apps/current-app-status" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print((d or {}).get('state') or '')" 2>/dev/null || echo "")
  if [ "$app_state" = "running" ]; then
    app_was_running=1
    echo "==> Stopping Reachy's conversation app to free the mic …"
    curl -sS --max-time 15 -X POST "${BASE}/api/apps/stop-current-app" >/dev/null
    sleep 4
  fi
fi

restore() {
  if [ "$app_was_running" = "1" ]; then
    echo; echo "==> Restarting Reachy's conversation app …"
    curl -sS --max-time 15 -X POST "${BASE}/api/apps/start-app/reachy_mini_conversation_app" >/dev/null || true
  fi
}
trap restore EXIT INT TERM

echo "==> Streaming from ${ROBOT_USER}@${ROBOT_IP} device=${ALSA_DEV} ${RATE}Hz ${CHANS}ch — Ctrl-C to stop."
echo

sshpass -p "$ROBOT_PASS" \
  ssh -o StrictHostKeyChecking=accept-new -C \
  "${ROBOT_USER}@${ROBOT_IP}" \
  "arecord -q -f S16_LE -r ${RATE} -c ${CHANS} -t raw -D ${ALSA_DEV} --buffer-time=$((BUF_MS*1000))" \
  | play -q -t raw -r "${RATE}" -e signed -b 16 -c "${CHANS}" -
