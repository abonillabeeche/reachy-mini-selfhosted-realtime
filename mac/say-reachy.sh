#!/usr/bin/env bash
# Speak text through Reachy Mini's speaker from this Mac.
# Usage: ./say-reachy.sh "hello, I am Reachy"
#        VOICE=Alex ./say-reachy.sh "hi there"
set -euo pipefail

ROBOT="${ROBOT:-10.0.0.154:8000}"
VOICE="${VOICE:-Samantha}"
TEXT="${*:-hello from your Mac}"

TMP="$(mktemp -d)"
AIFF="$TMP/msg.aiff"
WAV="$TMP/msg.wav"
NAME="mac_say_$(date +%s%N).wav"

say -v "$VOICE" -o "$AIFF" "$TEXT"
afconvert -f WAVE -d LEI16@22050 "$AIFF" "$WAV" >/dev/null

curl -sS --max-time 15 -F "file=@${WAV};filename=${NAME}" \
  "http://${ROBOT}/api/media/sounds/upload" >/dev/null

curl -sS --max-time 5 -X POST \
  -H "Content-Type: application/json" \
  -d "{\"file\":\"${NAME}\"}" \
  "http://${ROBOT}/api/media/play_sound"
echo
