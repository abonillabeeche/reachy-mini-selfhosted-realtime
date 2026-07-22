#!/usr/bin/env bash
[ -f "$HOME/.config/reachy/env" ] && . "$HOME/.config/reachy/env"
# SwiftBar toggle for `reachy see`. Mirrors reachy-listen-toggle.sh.
set -euo pipefail

STATE_DIR="${TMPDIR:-/tmp}"
PID_FILE="${STATE_DIR}/reachy-see.pid"
LOG_FILE="${STATE_DIR}/reachy-see.log"
SEE="$(cd "$(dirname "$(readlink "$0" || echo "$0")")" && pwd)/reachy-see.sh"

is_running() {
  [ -f "$PID_FILE" ] || return 1
  local pid
  pid=$(<"$PID_FILE") || return 1
  kill -0 "$pid" 2>/dev/null
}

case "${1:-status}" in
  start)
    if is_running; then echo "already running"; exit 0; fi
    nohup "$SEE" </dev/null >>"$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    disown 2>/dev/null || true
    sleep 1
    is_running && echo "watching (pid $(<"$PID_FILE"))" || { echo "failed; see $LOG_FILE"; exit 1; }
    ;;
  stop)
    if ! is_running; then echo "not running"; rm -f "$PID_FILE"; exit 0; fi
    pid=$(<"$PID_FILE")
    kill -INT "$pid" 2>/dev/null || true
    pkill -INT -P "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8; do is_running || break; sleep 1; done
    if is_running; then
      kill -TERM "$pid" 2>/dev/null || true
      pkill -TERM -P "$pid" 2>/dev/null || true
      sleep 2
    fi
    rm -f "$PID_FILE"
    echo "stopped"
    ;;
  status)
    if is_running; then echo "on"; else echo "off"; fi
    ;;
  *)
    echo "usage: reachy-see-toggle {start|stop|status}"; exit 2 ;;
esac
