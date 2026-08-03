#!/usr/bin/env bash
[ -f "$HOME/.config/reachy/env" ] && . "$HOME/.config/reachy/env"
# Toggle helper for Happy Mode (see reachy-happy.sh).
#   reachy-happy-toggle start   → launch the Happy Mode loop in the background
#   reachy-happy-toggle stop    → stop it
#   reachy-happy-toggle toggle  → start if off, stop if on (SwiftBar one-click)
#   reachy-happy-toggle status  → prints "on" or "off"
set -euo pipefail

STATE_DIR="${TMPDIR:-/tmp}"
PID_FILE="${STATE_DIR}/reachy-happy.pid"
LOG_FILE="${STATE_DIR}/reachy-happy.log"
HAPPY="$(cd "$(dirname "$(readlink "$0" || echo "$0")")" && pwd)/reachy-happy.sh"

is_running() {
  [ -f "$PID_FILE" ] || return 1
  local pid
  pid=$(<"$PID_FILE") || return 1
  kill -0 "$pid" 2>/dev/null
}

start() {
  if is_running; then
    echo "already running (pid $(<"$PID_FILE"))"
    return 0
  fi
  # Detach: macOS lacks setsid, so use nohup + disown.
  nohup "$HAPPY" </dev/null >>"$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  disown 2>/dev/null || true
  sleep 1
  is_running && echo "happy (pid $(<"$PID_FILE"))" || { echo "failed to start; see $LOG_FILE"; exit 1; }
}

stop() {
  if ! is_running; then
    echo "not running"
    rm -f "$PID_FILE"
    return 0
  fi
  local pid
  pid=$(<"$PID_FILE")
  # SIGTERM triggers the trap in reachy-happy.sh for a clean exit.
  kill -TERM "$pid" 2>/dev/null || true
  pkill -TERM -P "$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5; do
    is_running || break
    sleep 1
  done
  is_running && kill -KILL "$pid" 2>/dev/null || true
  rm -f "$PID_FILE"
  echo "stopped"
}

case "${1:-status}" in
  start)  start ;;
  stop)   stop ;;
  toggle) if is_running; then stop; else start; fi ;;
  status) if is_running; then echo "on"; else echo "off"; fi ;;
  *) echo "usage: reachy-happy-toggle {start|stop|toggle|status}"; exit 2 ;;
esac
