#!/usr/bin/env bash
# Toggle helper for the SwiftBar plugin.
#   reachy-listen-toggle start   → launch reachy-listen in the background
#   reachy-listen-toggle stop    → kill any running listen session (cleans up + restarts app)
#   reachy-listen-toggle status  → prints "on" or "off"
set -euo pipefail

STATE_DIR="${TMPDIR:-/tmp}"
PID_FILE="${STATE_DIR}/reachy-listen.pid"
LOG_FILE="${STATE_DIR}/reachy-listen.log"
LISTEN="$(cd "$(dirname "$(readlink "$0" || echo "$0")")" && pwd)/reachy-listen.sh"

is_running() {
  [ -f "$PID_FILE" ] || return 1
  local pid
  pid=$(<"$PID_FILE") || return 1
  kill -0 "$pid" 2>/dev/null
}

case "${1:-status}" in
  start)
    if is_running; then
      echo "already running (pid $(<"$PID_FILE"))"
      exit 0
    fi
    # Detach with setsid so we can kill the whole session on stop.
    # The launched reachy-listen.sh has a trap that restarts the conv app.
    setsid bash -c "\"$LISTEN\" </dev/null >>\"$LOG_FILE\" 2>&1 & echo \$! > \"$PID_FILE\""
    sleep 1
    is_running && echo "listening (pid $(<"$PID_FILE"))" || { echo "failed to start; see $LOG_FILE"; exit 1; }
    ;;
  stop)
    if ! is_running; then
      echo "not running"
      rm -f "$PID_FILE"
      exit 0
    fi
    pid=$(<"$PID_FILE")
    # SIGINT triggers the trap in reachy-listen.sh (like Ctrl-C).
    kill -INT -"$pid" 2>/dev/null || kill -INT "$pid" 2>/dev/null || true
    # Give it up to 8s to clean up (restart conv app takes ~3-5s).
    for _ in 1 2 3 4 5 6 7 8; do
      is_running || break
      sleep 1
    done
    if is_running; then
      # Escalate
      kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
      sleep 2
    fi
    rm -f "$PID_FILE"
    echo "stopped"
    ;;
  status)
    if is_running; then echo "on"; else echo "off"; fi
    ;;
  *)
    echo "usage: reachy-listen-toggle {start|stop|status}"; exit 2 ;;
esac
