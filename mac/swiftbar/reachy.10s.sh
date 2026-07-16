#!/usr/bin/env bash
# SwiftBar plugin — Reachy Mini live status + quick actions.
#
# Install:
#   1. brew install --cask swiftbar
#   2. Set SwiftBar's plugin folder to ~/Documents/SwiftBar (first launch prompts)
#   3. Copy this file there. Filename encodes the refresh interval:
#        reachy.10s.sh  → refresh every 10 seconds
#   4. chmod +x ~/Documents/SwiftBar/reachy.10s.sh
#
# Environment overrides (edit here or set globally in SwiftBar's app settings):
: "${ROBOT_IP:=10.0.0.154}"
: "${REACHY_CLI:=$HOME/bin/reachy}"

# <xbar.title>Reachy Mini</xbar.title>
# <xbar.desc>Live status and quick controls for a Reachy Mini via its daemon REST API.</xbar.desc>
# <xbar.author>abonillabeeche</xbar.author>
# <xbar.image>https://www.hf.co/reachy-mini/reachy-mini-logo.png</xbar.image>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>

BASE="http://${ROBOT_IP}:8000"

# --- Fetch state (all-or-nothing; if daemon unreachable, show offline) ---
JSON=$(curl -sS --max-time 3 "${BASE}/api/daemon/status" 2>/dev/null || true)
if [ -z "$JSON" ]; then
  echo "🔴 Reachy"
  echo "---"
  echo "Offline — daemon at ${ROBOT_IP}:8000 not reachable | color=red disabled=true"
  echo "---"
  echo "Refresh | refresh=true"
  exit 0
fi

POSE_JSON=$(curl -sS --max-time 3 "${BASE}/api/state/present_head_pose" 2>/dev/null || echo '{"pitch":0}')
MOTOR_JSON=$(curl -sS --max-time 3 "${BASE}/api/motors/status" 2>/dev/null || echo '{"mode":"unknown"}')
VOL_JSON=$(curl -sS --max-time 3 "${BASE}/api/volume/current" 2>/dev/null || echo '{"volume":0}')
APP_JSON=$(curl -sS --max-time 3 "${BASE}/api/apps/current-app-status" 2>/dev/null || echo 'null')

PITCH=$(echo "$POSE_JSON" | python3 -c "import sys,json,math; d=json.load(sys.stdin); print(round(math.degrees(d.get('pitch',0)),1))")
MODE=$(echo "$MOTOR_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('mode','?'))")
VOL=$(echo "$VOL_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('volume','?'))")
APP=$(echo "$APP_JSON" | python3 -c "import sys,json
d=json.load(sys.stdin)
if not d: print('<none>')
else: print(((d.get('info') or {}).get('name') or '<none>'))")
APP_STATE=$(echo "$APP_JSON" | python3 -c "import sys,json
d=json.load(sys.stdin)
if not d: print('')
else: print(d.get('state') or '')")

# --- Compose menu-bar title based on posture ---
# pitch > 15° ≈ asleep (head folded down)
awake_icon="🤖"
sleep_icon="💤"
if python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) > 15 else 1)" "$PITCH" 2>/dev/null; then
  echo "${sleep_icon} Reachy"
else
  echo "${awake_icon} Reachy"
fi

# --- Menu ---
cat <<EOF
---
Head:   pitch=${PITCH}° | color=gray disabled=true
Motors: ${MODE} | color=gray disabled=true
Volume: ${VOL}% | color=gray disabled=true
App:    ${APP} (${APP_STATE}) | color=gray disabled=true
---
🌅 Wake  | bash="${REACHY_CLI}" param1="wake" refresh=true terminal=false
🌙 Sleep | bash="${REACHY_CLI}" param1="sleep" refresh=true terminal=false
---
🗣 Speak | bash="${REACHY_CLI}" param1="say-prompt" refresh=true terminal=false
🔇 Mute   | bash="${REACHY_CLI}" param1="mute" refresh=true terminal=false
🔊 Unmute | bash="${REACHY_CLI}" param1="unmute" refresh=true terminal=false
---
$(
  LISTEN_TOGGLE="$(dirname "$0")/../claude/reachy-mini-selfhosted-realtime/mac/reachy-listen-toggle.sh"
  # Prefer the ~/bin symlink if present, else absolute path.
  if [ -x "$HOME/bin/reachy-listen-toggle" ]; then
    LISTEN_TOGGLE="$HOME/bin/reachy-listen-toggle"
  fi
  if [ -x "$LISTEN_TOGGLE" ] && "$LISTEN_TOGGLE" status 2>/dev/null | grep -q on; then
    echo "🎧 Stop Listening | bash=\"$LISTEN_TOGGLE\" param1=\"stop\" refresh=true terminal=false color=orange"
  else
    echo "🎧 Start Listening | bash=\"$LISTEN_TOGGLE\" param1=\"start\" refresh=true terminal=false"
  fi
)
---
Volume | color=gray disabled=true
--0%   | bash="${REACHY_CLI}" param1="volume" param2="0"   refresh=true terminal=false
--30%  | bash="${REACHY_CLI}" param1="volume" param2="30"  refresh=true terminal=false
--60%  | bash="${REACHY_CLI}" param1="volume" param2="60"  refresh=true terminal=false
--90%  | bash="${REACHY_CLI}" param1="volume" param2="90"  refresh=true terminal=false
--100% | bash="${REACHY_CLI}" param1="volume" param2="100" refresh=true terminal=false
---
Refresh now | refresh=true
EOF
