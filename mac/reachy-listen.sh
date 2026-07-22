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

media_released=0
if [ "$NOSLEEP" != "1" ]; then
  # The reachy-mini daemon itself opens the mic capture pipeline
  # (for wobble / VAD) even without an app running. /api/media/release
  # frees the ALSA device without stopping the daemon or the app.
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
}
trap restore EXIT INT TERM

echo "==> Streaming from ${ROBOT_USER}@${ROBOT_IP} device=${ALSA_DEV} ${RATE}Hz ${CHANS}ch — Ctrl-C to stop."
echo

sshpass -p "$ROBOT_PASS" \
  ssh -o StrictHostKeyChecking=accept-new -C \
  "${ROBOT_USER}@${ROBOT_IP}" \
  "arecord -q -f S16_LE -r ${RATE} -c ${CHANS} -t raw -D ${ALSA_DEV} --buffer-time=$((BUF_MS*1000))" \
  | play -q -t raw -r "${RATE}" -e signed -b 16 -c "${CHANS}" -
