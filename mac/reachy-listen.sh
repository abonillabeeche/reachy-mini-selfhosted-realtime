#!/usr/bin/env bash
[ -f "$HOME/.config/reachy/env" ] && . "$HOME/.config/reachy/env"
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

: "${ROBOT_IP:=10.0.0.20}"
: "${ROBOT_USER:=pollen}"
: "${ROBOT_PASS:=}"
: "${NOSLEEP:=0}"
: "${ALSA_DEV:=plughw:0,0}"   # Reachy Mini Audio (card 0)
: "${RATE:=48000}"
: "${CHANS:=1}"               # 1 channel is enough for room ambience, less bandwidth
: "${BUF_MS:=200}"            # network buffer — smaller = lower latency but more glitchy

BASE="http://${ROBOT_IP}:8000"

command -v play >/dev/null || { echo "!! 'play' not found. Install sox: brew install sox"; exit 1; }
command -v sshpass >/dev/null || { echo "!! sshpass not found. Install: brew install esolitos/ipa/sshpass"; exit 1; }

rssh() { sshpass -p "$ROBOT_PASS" ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 "${ROBOT_USER}@${ROBOT_IP}" "$@"; }

# Push-to-talk leaves the XMOS mic capture switch muted (nocap). Monitoring
# needs it ON, so record the current state, unmute for the session, and
# restore it on exit (so we don't accidentally leave the mic hot for PTT).
MIC_WAS=$(rssh "amixer -c 0 sget Headset,0 2>/dev/null | grep -oE '\[on\]|\[off\]' | head -1" 2>/dev/null)
echo "==> Un-muting mic for monitoring …"
rssh "amixer -c 0 sset Headset,0 cap >/dev/null 2>&1; amixer -c 0 sset Headset,1 cap >/dev/null 2>&1" 2>/dev/null

media_released=0
app_stopped=0
if [ "$NOSLEEP" != "1" ]; then
  # The conversation app holds the single mic; a direct arecord fights it and
  # gets no audio. Stop the app so the mic is free, then release daemon media.
  APP=$(curl -sS --max-time 5 "${BASE}/api/apps/current-app-status" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print((d or {}).get('state') or '')" 2>/dev/null || echo "")
  if [ "$APP" = "running" ]; then
    echo "==> Pausing conversation app so the mic is free …"
    curl -sS --max-time 15 -X POST "${BASE}/api/apps/stop-current-app" >/dev/null
    app_stopped=1
    sleep 4
  fi
  echo "==> Releasing Reachy's mic …"
  curl -sS --max-time 10 -X POST "${BASE}/api/media/release" >/dev/null
  media_released=1
  sleep 2
fi

restore() {
  if [ "$media_released" = "1" ]; then
    echo; echo "==> Re-acquiring Reachy's mic …"
    curl -sS --max-time 10 -X POST "${BASE}/api/media/acquire" >/dev/null || true
  fi
  # restore the mic capture switch to whatever it was (muted, for PTT)
  if [ "$MIC_WAS" = "[off]" ]; then
    rssh "amixer -c 0 sset Headset,0 nocap >/dev/null 2>&1; amixer -c 0 sset Headset,1 nocap >/dev/null 2>&1" 2>/dev/null
    echo "==> Mic restored to muted (push-to-talk default)."
  fi
  if [ "$app_stopped" = "1" ]; then
    echo "==> Restarting conversation app …"
    curl -sS --max-time 15 -X POST "${BASE}/api/apps/start-app/reachy_mini_conversation_app" >/dev/null 2>&1 || true
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
