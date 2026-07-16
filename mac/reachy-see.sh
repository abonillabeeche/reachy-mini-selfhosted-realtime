#!/usr/bin/env bash
# Live-view Reachy's camera on a remote Mac.
# gst-launch on Reachy captures /dev/video0 → jpeg stream → SSH → ffplay on Mac.
# Ctrl-C to stop; the daemon's media is re-acquired automatically.
#
# Reachy is woken (motors + slow head lift) on entry so she's actually looking
# somewhere useful. She stays awake on exit.
#
# Usage:
#   reachy see
#   ROBOT_IP=192.168.1.20 reachy see
#   NOWAKE=1 reachy see                # don't wake first (skip motor+head goto)
#   WIDTH=1280 HEIGHT=720 FPS=15 reachy see
set -euo pipefail

: "${ROBOT_IP:=10.0.0.154}"
: "${ROBOT_USER:=pollen}"
: "${ROBOT_PASS:=root}"
: "${V4L_DEV:=/dev/video0}"
: "${WIDTH:=640}"
: "${HEIGHT:=480}"
: "${FPS:=15}"
: "${QUALITY:=70}"
: "${NOWAKE:=0}"

BASE="http://${ROBOT_IP}:8000"

command -v ffplay >/dev/null  || { echo "!! ffplay not found. Install: brew install ffmpeg"; exit 1; }
command -v sshpass >/dev/null || { echo "!! sshpass not found. Install: brew install esolitos/ipa/sshpass"; exit 1; }

media_released=0
if [ "$NOWAKE" != "1" ]; then
  echo "==> Waking Reachy so she's actually looking at something …"
  curl -sS --max-time 5 -X POST "${BASE}/api/motors/set_mode/enabled" >/dev/null || true
  curl -sS --max-time 12 -X POST "${BASE}/api/move/goto" \
    -H "Content-Type: application/json" \
    -d '{"head":{"x":0,"y":0,"z":0,"roll":0,"pitch":0,"yaw":0,"degrees":true,"mm":true},"antennas":[-0.1745, 0.1745],"body_yaw":0,"duration":3.0}' >/dev/null || true
  sleep 4
fi

echo "==> Releasing Reachy's media (frees ${V4L_DEV}) …"
curl -sS --max-time 10 -X POST "${BASE}/api/media/release" >/dev/null
media_released=1
sleep 2

restore() {
  if [ "$media_released" = "1" ]; then
    echo; echo "==> Re-acquiring Reachy's media …"
    curl -sS --max-time 10 -X POST "${BASE}/api/media/acquire" >/dev/null || true
  fi
}
trap restore EXIT INT TERM

echo "==> Streaming ${V4L_DEV} @ ${WIDTH}x${HEIGHT}@${FPS}fps — close the window or Ctrl-C to stop."
echo

# gst on Reachy: v4l2 → convert → resize → jpeg → multipart mjpeg over stdout.
# ffplay reads the MJPEG stream from stdin.
sshpass -p "$ROBOT_PASS" \
  ssh -o StrictHostKeyChecking=accept-new -C \
  "${ROBOT_USER}@${ROBOT_IP}" \
  "gst-launch-1.0 -q v4l2src device=${V4L_DEV} ! \
   video/x-raw,width=${WIDTH},height=${HEIGHT},framerate=${FPS}/1 ! \
   videoconvert ! jpegenc quality=${QUALITY} ! \
   multipartmux boundary=frame ! fdsink" \
  | ffplay -hide_banner -loglevel warning -window_title "Reachy camera" \
           -f mjpeg -framerate "${FPS}" -i pipe:0
