#!/usr/bin/env bash
[ -f "$HOME/.config/reachy/env" ] && . "$HOME/.config/reachy/env"
# Happy Mode worker — Reachy quietly does gentle moves "for fun" in the
# background. Picks a random SILENT dance every ~10-20s. Dances carry no
# audio (unlike emotions), so this stays quiet. Ctrl-C / SIGTERM to stop.
#
# This is the long-running worker; use reachy-happy-toggle.sh to start/stop it
# in the background from SwiftBar.
#
# Usage: ./reachy-happy.sh
#        ROBOT_IP=192.168.1.20 ./reachy-happy.sh
set -euo pipefail

: "${ROBOT_IP:=10.0.0.154}"
: "${MIN_GAP:=10}"     # min seconds between moves
: "${MAX_GAP:=20}"     # max seconds between moves
BASE="http://${ROBOT_IP}:8000"
DANCES="pollen-robotics/reachy-mini-dances-library"

# Gentle, silent dances only (a calm subset of the dances library) so Happy
# Mode reads as playful ambience, not a rave.
GENTLE=(
  side_to_side_sway simple_nod yeah_nod uh_huh_tilt head_tilt_roll
  pendulum_swing side_glance_flick chin_lead groovy_sway_and_roll side_peekaboo
)

running=1
stop() { running=0; }
trap stop INT TERM

# Auto-enable motors so moves actually happen even if she was limp/asleep.
curl -sS --max-time 5 -X POST "${BASE}/api/motors/set_mode/enabled" >/dev/null 2>&1 || true

while [ "$running" = "1" ]; do
  # Don't fight the conversation app (or a prior move) — if something is
  # already moving, skip this beat and try again later.
  BUSY=$(curl -sS --max-time 4 "${BASE}/api/move/running" 2>/dev/null | \
    python3 -c "import sys,json; print(len(json.load(sys.stdin) or []))" 2>/dev/null || echo 0)
  if [ "$BUSY" = "0" ]; then
    MOVE=${GENTLE[$((RANDOM % ${#GENTLE[@]}))]}
    curl -sS --max-time 8 -X POST \
      "${BASE}/api/move/play/recorded-move-dataset/${DANCES}/${MOVE}" >/dev/null 2>&1 || true
  fi
  # Randomized gap so it feels organic. Sleep in 1s steps so stop is responsive.
  GAP=$((RANDOM % (MAX_GAP - MIN_GAP + 1) + MIN_GAP))
  for _ in $(seq 1 "$GAP"); do
    [ "$running" = "1" ] || break
    sleep 1
  done
done
