#!/usr/bin/env bash
# Idempotent installer for the robot-side pieces.
#
# Run from your Mac (or any control host):
#   NODE_IP=10.0.0.10 ROBOT_IP=10.0.0.20 PROFILE=my-profile ./robot/install.sh
#
# Requires: sshpass, ssh; robot reachable at ROBOT_IP with default SSH
# credentials `pollen`/`root` unless you override ROBOT_USER/ROBOT_PASS.
set -euo pipefail

: "${ROBOT_IP:?set ROBOT_IP (e.g. 10.0.0.20)}"
: "${NODE_IP:?set NODE_IP (LAN IP of the GPU node running s2s + Ollama)}"
: "${ROBOT_USER:=pollen}"
# No baked-in password. Set ROBOT_PASS in your env (or ~/.config/reachy/env).
# Pollen's FACTORY DEFAULT on a fresh Reachy Mini Wireless is "root" — change it.
[ -f "$HOME/.config/reachy/env" ] && . "$HOME/.config/reachy/env"
: "${ROBOT_PASS:?set ROBOT_PASS (factory default is 'root' on a fresh unit — then change it)}"
: "${PROFILE:=my-profile}"

HERE="$(cd "$(dirname "$0")" && pwd)"
REMOTE_PROFILES=/venvs/apps_venv/lib/python3.12/site-packages/reachy_talk_data/profiles
REMOTE_APP=/venvs/apps_venv/lib/python3.12/site-packages/reachy_mini_conversation_app

ssh_do() { sshpass -p "${ROBOT_PASS}" ssh -o StrictHostKeyChecking=accept-new "${ROBOT_USER}@${ROBOT_IP}" "$@"; }
scp_to() { sshpass -p "${ROBOT_PASS}" scp -o StrictHostKeyChecking=accept-new "$@" "${ROBOT_USER}@${ROBOT_IP}:/tmp/"; }

echo "==> [1/5] Sanity check SSH + sudo"
ssh_do 'sudo -n true' >/dev/null

echo "==> [2/5] Install profile '${PROFILE}' with camera.py + custom tools"
scp_to "${HERE}"/profile-example/*.txt "${HERE}"/profile-example/camera.py "${HERE}"/tools/*.py
ssh_do "sudo mkdir -p ${REMOTE_PROFILES}/${PROFILE} && \
  sudo mv /tmp/instructions.txt /tmp/greeting.txt /tmp/tools.txt \
          /tmp/camera.py /tmp/lower_antennas.py /tmp/raise_antennas.py /tmp/wiggle_antennas.py \
          ${REMOTE_PROFILES}/${PROFILE}/ && \
  sudo chmod 0644 ${REMOTE_PROFILES}/${PROFILE}/* && \
  sudo rm -rf ${REMOTE_PROFILES}/${PROFILE}/__pycache__"

echo "==> [3/5] Apply app_lifecycle slow-wake patch"
scp_to "${HERE}"/patches/app_lifecycle-slow-wake.patch
ssh_do "cd ${REMOTE_APP} && \
  sudo patch -p0 -N --dry-run < /tmp/app_lifecycle-slow-wake.patch >/dev/null 2>&1 && \
  sudo patch -p0 -N < /tmp/app_lifecycle-slow-wake.patch || \
  echo '(patch already applied or file changed — skipping; re-check manually)'"
ssh_do "sudo rm -f ${REMOTE_APP}/__pycache__/app_lifecycle*.pyc"

echo "==> [4/5] Install systemd drop-in"
scp_to "${HERE}"/systemd/hf-realtime.conf.template
ssh_do "sudo mkdir -p /etc/systemd/system/reachy-mini-daemon.service.d && \
  sudo sed -e 's|__NODE_IP__|${NODE_IP}|g' -e 's|REACHY_MINI_CUSTOM_PROFILE=my-profile|REACHY_MINI_CUSTOM_PROFILE=${PROFILE}|' \
    /tmp/hf-realtime.conf.template > /tmp/hf-realtime.conf && \
  sudo mv /tmp/hf-realtime.conf /etc/systemd/system/reachy-mini-daemon.service.d/hf-realtime.conf && \
  sudo systemctl daemon-reload"

echo "==> [5/5] Sync app's own .env so it doesn't override the systemd env"
ssh_do "cat <<EOF | sudo tee ${REMOTE_APP}/.env >/dev/null
HF_REALTIME_CONNECTION_MODE=local
HF_REALTIME_WS_URL=ws://${NODE_IP}:31765/v1/realtime
REACHY_MINI_CUSTOM_PROFILE=${PROFILE}
REACHY_VLM_BASE_URL=http://${NODE_IP}:31434/v1
REACHY_VLM_MODEL=qwen2.5vl:7b
EOF"

echo
echo "Done. To activate:"
echo "  sudo systemctl restart reachy-mini-daemon.service"
echo "  # or via API: curl -X POST http://${ROBOT_IP}:8000/api/apps/restart-current-app"
echo
echo "Verify with:"
echo "  sudo journalctl -u reachy-mini-daemon.service --since '20s ago' -f | grep -E 'profile=|voice=|realtime session initialized'"
