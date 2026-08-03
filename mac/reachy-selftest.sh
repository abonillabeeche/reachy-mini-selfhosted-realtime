#!/usr/bin/env bash
[ -f "$HOME/.config/reachy/env" ] && . "$HOME/.config/reachy/env"
# reachy-selftest — exercise every Reachy helper and report PASS/FAIL.
#
# Verifies:
#   • daemon reachable + backend running + motors enable
#   • motion actions actually enqueue a move (via /api/move/running)
#   • audio actions actually play (via the daemon's audio-sink log count)
#   • Happy Mode toggle starts/stops cleanly
#
# Usage: reachy test        (or: ./reachy-selftest.sh)
#        FULL=1 reachy test  (also runs the long sing / dance-long medleys)
set -uo pipefail    # NOT -e: keep going so one failure doesn't abort the suite

: "${ROBOT_IP:=10.0.0.154}"
: "${ROBOT_USER:=pollen}"
: "${ROBOT_PASS:=}"
: "${FULL:=0}"
BASE="http://${ROBOT_IP}:8000"
CLI="$(cd "$(dirname "$(readlink "$0" || echo "$0")")" && pwd)/reachy"

G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; Z=$'\033[0m'
PASS=0; FAIL=0
ok()   { printf "  ${G}PASS${Z}  %s\n" "$1"; PASS=$((PASS+1)); }
no()   { printf "  ${R}FAIL${Z}  %s\n" "$1"; FAIL=$((FAIL+1)); }
info() { printf "  ${Y}··${Z}    %s\n" "$1"; }

rssh() { sshpass -p "$ROBOT_PASS" ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 "${ROBOT_USER}@${ROBOT_IP}" "$@" 2>/dev/null; }

# number of moves currently running
running_n() {
  curl -sS --max-time 4 "${BASE}/api/move/running" 2>/dev/null | \
    python3 -c "import sys,json; print(len(json.load(sys.stdin) or []))" 2>/dev/null || echo 0
}
# cumulative count of audio-sink playbacks since boot (a proxy for "sound played")
sink_total() {
  rssh "sudo journalctl -u reachy-mini-daemon.service -b --no-pager 2>/dev/null | grep -c 'reachymini_audio_sink'" || echo 0
}
# stop whatever move is running so the next test starts clean
stop_move() {
  local u
  u=$(curl -sS --max-time 4 "${BASE}/api/move/running" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin) or []; print(d[0]['uuid'] if d else '')" 2>/dev/null)
  [ -n "$u" ] && curl -sS --max-time 5 -X POST "${BASE}/api/move/stop" \
    -H "Content-Type: application/json" -d "{\"uuid\":\"$u\"}" >/dev/null 2>&1
}
wait_idle() { for _ in $(seq 1 20); do [ "$(running_n)" = "0" ] && return 0; sleep 1; done; }

# Assert a CLI action makes a move appear within ~4s. Args: <label> <subcmd...>
test_move() {
  local label="$1"; shift
  wait_idle
  "$CLI" "$@" >/dev/null 2>&1
  local seen=0
  for _ in 1 2 3 4 5 6 7 8; do [ "$(running_n)" != "0" ] && { seen=1; break; }; sleep 0.5; done
  [ "$seen" = "1" ] && ok "$label (move enqueued)" || no "$label (no move appeared)"
  stop_move; wait_idle
}

# Assert a CLI action produces audio (sink count increases). Args: <label> <subcmd...>
test_audio() {
  local label="$1"; shift
  local before after
  before=$(sink_total)
  "$CLI" "$@" >/dev/null 2>&1
  sleep 3
  after=$(sink_total)
  [ "${after:-0}" -gt "${before:-0}" ] && ok "$label (audio played: ${before}->${after})" || no "$label (no audio-sink playback)"
  stop_move; wait_idle
}

echo "── Reachy self-test @ ${ROBOT_IP} ─────────────────────────────"

# 1) Reachability + backend
if curl -sS --max-time 5 -o /dev/null "${BASE}/api/daemon/status"; then ok "daemon reachable"; else no "daemon reachable"; echo "aborting."; exit 1; fi
STATE=$(curl -sS --max-time 5 "${BASE}/api/daemon/status" | python3 -c "import sys,json; print(json.load(sys.stdin).get('state',''))" 2>/dev/null)
[ "$STATE" = "running" ] && ok "backend running" || no "backend running (state=$STATE — try 'reachy wake')"
if [ -n "$ROBOT_PASS" ] && rssh "true"; then ok "SSH to robot"; else no "SSH to robot (check ROBOT_PASS)"; fi

# 2) Motors
curl -sS --max-time 5 -X POST "${BASE}/api/motors/set_mode/enabled" >/dev/null 2>&1
MODE=$(curl -sS --max-time 5 "${BASE}/api/motors/status" | python3 -c "import sys,json; print(json.load(sys.stdin).get('mode',''))" 2>/dev/null)
[ "$MODE" = "enabled" ] && ok "motors enable" || no "motors enable (mode=$MODE)"

echo "── Motion actions ─────────────────────────────────────────────"
test_move "waddle"       waddle
test_move "dance"        dance
test_move "emotion"      emotion cheerful1
test_move "stayin-alive" stayin-alive
test_move "kill-bill"    kill-bill

echo "── Audio actions ──────────────────────────────────────────────"
test_audio "say"     say "self test speaking"
test_audio "whisper" whisper "self test whisper"
test_audio "emotion audio (sing pool)" emotion laughing1

echo "── Happy Mode ─────────────────────────────────────────────────"
"$CLI" happy start >/dev/null 2>&1
sleep 1
[ "$("$CLI" happy status 2>/dev/null)" = "on" ] && ok "happy start" || no "happy start"
# observe at least one move within ~25s
hm=0; for _ in $(seq 1 13); do [ "$(running_n)" != "0" ] && { hm=1; break; }; sleep 2; done
[ "$hm" = "1" ] && ok "happy produced a move" || no "happy produced no move in 25s"
"$CLI" happy stop >/dev/null 2>&1
sleep 1
[ "$("$CLI" happy status 2>/dev/null)" = "off" ] && ok "happy stop" || no "happy stop"

if [ "$FULL" = "1" ]; then
  echo "── Full medleys (FULL=1) ──────────────────────────────────────"
  test_audio "sing (3 clips)" sing
fi

echo "───────────────────────────────────────────────────────────────"
TOTAL=$((PASS+FAIL))
if [ "$FAIL" = "0" ]; then
  printf "${G}ALL PASS${Z}  (%d/%d)\n" "$PASS" "$TOTAL"; exit 0
else
  printf "${R}%d FAILED${Z}  (%d/%d passed)\n" "$FAIL" "$PASS" "$TOTAL"; exit 1
fi
