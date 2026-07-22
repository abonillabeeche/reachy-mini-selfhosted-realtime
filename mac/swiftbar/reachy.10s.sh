#!/usr/bin/env bash
[ -f "$HOME/.config/reachy/env" ] && . "$HOME/.config/reachy/env"
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
: "${ROBOT_IP:=10.0.0.20}"
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

# --- mic (push-to-talk) + DAC volume state, one SSH round trip ---
ROBOT_USER="${ROBOT_USER:-pollen}"
ROBOT_PASS="${ROBOT_PASS:-}"
APPDIR="/venvs/apps_venv/lib/python3.12/site-packages/reachy_mini_conversation_app"
PROFDIR="/venvs/apps_venv/lib/python3.12/site-packages/reachy_talk_data/profiles"
STATE=$(sshpass -p "$ROBOT_PASS" ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=3 "${ROBOT_USER}@${ROBOT_IP}" \
  "m=\$(amixer -c 0 sget Headset,0 2>/dev/null | grep -oE '\[on\]|\[off\]' | head -1); \
   v=\$(amixer -c Audio_1 sget PCM 2>/dev/null | grep -oE '[0-9]+%' | head -1); \
   p=\$(grep -oE '\"profile\": *\"[^\"]*\"' ${APPDIR}/startup_settings.json 2>/dev/null | sed -E 's/.*\"([^\"]*)\"\$/\1/'); \
   echo \"\$m|\$v|\$p\"" 2>/dev/null || echo "||")
MIC_STATE="${STATE%%|*}"; rest="${STATE#*|}"; DAC_VOL="${rest%%|*}"; CUR_PROF="${rest#*|}"
[ "$MIC_STATE" = "[on]" ] && MIC_TXT="ON (listening)" || MIC_TXT="OFF"
[ -z "$CUR_PROF" ] && CUR_PROF="default"
# Featured profiles (custom first); the rest listed after.
FEATURED="upbeat suse"

# Build the personality submenu lines (no `case` — its ')' breaks $() in heredocs)
ALL_PROFILES=$(sshpass -p "$ROBOT_PASS" ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=3 "${ROBOT_USER}@${ROBOT_IP}" "ls -1 ${PROFDIR} 2>/dev/null | grep -vE '__pycache__'" 2>/dev/null)
PERSONALITY_MENU=""
_emit_prof() {
  local p="$1"
  if [ "$p" = "$CUR_PROF" ]; then
    PERSONALITY_MENU="${PERSONALITY_MENU}--✓ ${p} (active) | color=green refresh=false terminal=false"$'\n'
  else
    PERSONALITY_MENU="${PERSONALITY_MENU}--${p} | bash=\"${REACHY_CLI}\" param1=\"profile\" param2=\"${p}\" refresh=true terminal=true"$'\n'
  fi
}
for p in $FEATURED; do _emit_prof "$p"; done
PERSONALITY_MENU="${PERSONALITY_MENU}-----"$'\n'
for p in $ALL_PROFILES; do
  echo "$FEATURED" | grep -qw "$p" && continue
  _emit_prof "$p"
done

# --- Compose menu-bar title: posture + mic-live indicator ---
# pitch > 15° ≈ asleep (head folded down)
if python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) > 15 else 1)" "$PITCH" 2>/dev/null; then
  icon="💤"
else
  icon="🤖"
fi
[ "$MIC_STATE" = "[on]" ] && icon="🔴"   # mic hot — overrides
echo "${icon} Reachy"

# --- Menu ---
cat <<EOF
---
Reachy Mini | color=gray disabled=true size=11
IP:     ${ROBOT_IP} — copy | bash="/bin/sh" param1="-c" param2="printf '%s' '${ROBOT_IP}' | pbcopy" refresh=false terminal=false
Daemon: http://${ROBOT_IP}:8000 — open | bash="/usr/bin/open" param1="http://${ROBOT_IP}:8000" refresh=false terminal=false
Head:   pitch=${PITCH}° | color=gray disabled=true
Motors: ${MODE} | color=gray disabled=true
Speaker (DAC): ${DAC_VOL:-?} | color=gray disabled=true
Mic:    ${MIC_TXT} | color=gray disabled=true
Personality: ${CUR_PROF} | color=gray disabled=true
App:    ${APP} (${APP_STATE}) | color=gray disabled=true
---
🎭 Personality: ${CUR_PROF} | color=gray
${PERSONALITY_MENU}
---
$(
  if [ "$MIC_STATE" = "[on]" ]; then
    echo "🎙 Mic ON — tap to mute | bash=\"${REACHY_CLI}\" param1=\"mic\" param2=\"off\" refresh=true terminal=false color=red"
  else
    echo "🎙 Mic OFF — tap to talk | bash=\"${REACHY_CLI}\" param1=\"mic\" param2=\"on\" refresh=true terminal=false"
  fi
)
⏱ Talk 4s (countdown) | bash="/opt/homebrew/bin/hs" param1="-c" param2="reachyTalk(4)" refresh=false terminal=false
---
🌅 Wake  | bash="${REACHY_CLI}" param1="wake" refresh=true terminal=false
🌙 Sleep | bash="${REACHY_CLI}" param1="sleep" refresh=true terminal=false
---
🗣 Speak | bash="${REACHY_CLI}" param1="say-prompt" refresh=true terminal=false
---
$(
  LISTEN_TOGGLE="${HOME}/bin/reachy-listen-toggle"
  SEE_TOGGLE="${HOME}/bin/reachy-see-toggle"
  if [ -x "$LISTEN_TOGGLE" ] && "$LISTEN_TOGGLE" status 2>/dev/null | grep -q on; then
    echo "🎧 Stop Listening | bash=\"$LISTEN_TOGGLE\" param1=\"stop\" refresh=true terminal=false color=orange"
  else
    echo "🎧 Start Listening | bash=\"$LISTEN_TOGGLE\" param1=\"start\" refresh=true terminal=false"
  fi
  # Camera view: the daemon locks libcamera exclusively, so live video from
  # a plain SSH+gst pipeline fights it. Route via the official Reachy Mini
  # Control desktop app instead — it uses the daemon's WebRTC preview.
  OPEN_CTRL="${HOME}/bin/reachy-open-control"
  if [ -d "/Applications/Reachy Mini Control.app" ] && [ -x "$OPEN_CTRL" ]; then
    echo "📷 Open Reachy Control (stops listen, frees mic) | bash=\"$OPEN_CTRL\" refresh=true terminal=false"
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
