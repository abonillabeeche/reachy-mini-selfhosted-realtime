#!/usr/bin/env bash
# Launcher for the Reachy face-greeter service.
# Waits for the daemon, (re)uploads greeting sounds (the daemon's sound dir is
# ephemeral /tmp), then runs the hardened recognition watcher.
set -uo pipefail
DIR=/home/pollen/reachy-face
BASE=http://localhost:8000
PY=/venvs/mini_daemon/bin/python

# wait for the daemon HTTP to be up (up to ~2 min after boot)
for _ in $(seq 1 60); do
  curl -sS --max-time 3 -o /dev/null "$BASE/api/daemon/status" && break
  sleep 2
done

# (re)upload persistent greeting WAVs so play_sound can find them by name
for w in "$DIR"/greetings/*.wav; do
  [ -e "$w" ] || continue
  curl -sS --max-time 15 -F "file=@${w};filename=$(basename "$w")" \
    "$BASE/api/media/sounds/upload" >/dev/null 2>&1 || true
done

# recognition thresholds / gating (tuned to avoid photo/incidental false hits)
export FACE_MATCH_THRESHOLD="${FACE_MATCH_THRESHOLD:-0.6}"   # higher = fewer false matches
export GREET_MIN_FRAMES="${GREET_MIN_FRAMES:-3}"           # consecutive confirmations
export GREET_MIN_FACE_W="${GREET_MIN_FACE_W:-26}"          # on the downscaled (DET_WIDTH) frame
export DET_WIDTH="${DET_WIDTH:-960}"                       # downscale before detection (CPU)
export GREET_CADENCE="${GREET_CADENCE:-0.8}"              # secs between recognitions
export GREET_COOLDOWN="${GREET_COOLDOWN:-60}"

exec "$PY" -u "$DIR/livecam.py" watch
