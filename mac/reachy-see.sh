#!/usr/bin/env bash
[ -f "$HOME/.config/reachy/env" ] && . "$HOME/.config/reachy/env"
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

: "${ROBOT_IP:=10.0.0.20}"
: "${ROBOT_USER:=pollen}"
: "${ROBOT_PASS:=}"
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

echo "==> Streaming Reachy camera @ ${WIDTH}x${HEIGHT}@${FPS}fps — close the window or Ctrl-C to stop."
echo

# On Reachy: PipeWire owns the camera (multi-consumer). Use `pipewiresrc` so
# we join the shared stream instead of fighting for exclusive /dev/videoX.
# Kill any leftover gst-launch from a prior failed run first.
#
# One-liner over SSH: kill stale, then start gst pipeline that emits MJPEG.
sshpass -p "$ROBOT_PASS" \
  ssh -o StrictHostKeyChecking=accept-new -C \
  "${ROBOT_USER}@${ROBOT_IP}" \
  "pkill -f 'gst-launch-1.0.*jpegenc' 2>/dev/null; \
   sleep 1; \
   gst-launch-1.0 -q pipewiresrc ! \
     videoconvert ! videoscale ! \
     video/x-raw,width=${WIDTH},height=${HEIGHT} ! \
     videorate ! video/x-raw,framerate=${FPS}/1 ! \
     jpegenc quality=${QUALITY} ! \
     fdsink sync=false" \
  | ffplay -hide_banner -loglevel warning -window_title "Reachy camera" \
           -f image2pipe -vcodec mjpeg -framerate "${FPS}" \
           -video_size "${WIDTH}x${HEIGHT}" \
           -analyzeduration 10M -probesize 10M \
           -fflags nobuffer -flags low_delay \
           -i pipe:0
