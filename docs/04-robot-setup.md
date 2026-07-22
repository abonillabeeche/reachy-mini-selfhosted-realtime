# Robot-side setup

Once the cluster is running your s2s + VLM, point the robot at it.

## One-shot install

```bash
NODE_IP=10.0.0.10 \
ROBOT_IP=10.0.0.20 \
PROFILE=my-profile \
./robot/install.sh
```

That script:
1. Copies the example profile + custom tools + the hybrid `camera.py` into
   `/venvs/apps_venv/lib/python3.12/site-packages/reachy_talk_data/profiles/${PROFILE}/`.
2. Applies the slow-wake patch to `app_lifecycle.py` (so app restarts don't
   trigger the fast wake_up + toudoum + 20° head wiggle).
3. Installs the systemd drop-in at
   `/etc/systemd/system/reachy-mini-daemon.service.d/hf-realtime.conf` with
   your NODE_IP substituted.
4. Writes a matching `.env` file inside the app's package dir (the app calls
   `load_dotenv(override=True)` and this file wins over systemd env vars, so
   both must match).

## Activate

```bash
# Restart the daemon (picks up new env vars):
sshpass -p "$ROBOT_PASS" ssh pollen@$ROBOT_IP 'sudo systemctl restart reachy-mini-daemon.service'

# Or restart just the conversation app (faster; env is already loaded):
curl -X POST http://$ROBOT_IP:8000/api/apps/restart-current-app
```

## Verify

Tail the daemon log and confirm the session is initialized against your
backend and profile:

```bash
sshpass -p "$ROBOT_PASS" ssh pollen@$ROBOT_IP \
  'sudo journalctl -u reachy-mini-daemon.service --since "30s ago" -f' \
  | grep -E 'profile=|voice=|realtime session initialized|WebSocket'
```

You want to see:

```
Loading tools for profile: my-profile
Loading prompt from profile 'my-profile'
Realtime session initialized with profile='my-profile' voice='af_heart'
```

Then say *"Reachy, are you there?"*.

## Custom persona

Edit [`robot/profile-example/instructions.txt`](../robot/profile-example/instructions.txt)
before running install.sh (or edit the deployed file directly at
`/venvs/apps_venv/lib/python3.12/site-packages/reachy_talk_data/profiles/${PROFILE}/instructions.txt`).

The example is deliberately generic. The wake-word handling, tone rules,
"never leak reasoning" section, and tool-result trust section have all
been battle-tested — replace the IDENTITY paragraph with your own persona
and keep the rest.

## Kokoro voice patch

The conversation app validates the runtime voice against a hardcoded
allowlist of HuggingFace Realtime speaker names (Aiden, Ryan, Dylan, …).
Any voice not in that list gets silently mapped back to "Aiden", which
Kokoro doesn't have — so TTS 404s and Reachy stays silent.

The install script doesn't patch this because it depends on which Kokoro
voice you want. To use `af_heart` (default in our StatefulSet):

```bash
sshpass -p "$ROBOT_PASS" ssh pollen@$ROBOT_IP 'sudo python3 -c "
p = \"/venvs/apps_venv/lib/python3.12/site-packages/reachy_mini_conversation_app/config.py\"
src = open(p).read()
if \"af_heart\" not in src:
    open(p, \"w\").write(src.replace(
        \"HF_AVAILABLE_VOICES: list[str] = [\",
        \"HF_AVAILABLE_VOICES: list[str] = [\n    \\\"af_heart\\\",\n    \\\"af_bella\\\",\n    \\\"am_michael\\\",\"
    ))
    print(\"patched\")
"'

# Set the startup voice:
sshpass -p "$ROBOT_PASS" ssh pollen@$ROBOT_IP 'echo "{\"profile\": \"'"$PROFILE"'\", \"voice\": \"af_heart\"}" | \
  sudo tee /venvs/apps_venv/lib/python3.12/site-packages/reachy_mini_conversation_app/startup_settings.json'
```

Alternative: create a symlink in the Kokoro cache so `Aiden.pt` resolves
to an existing voice file. See [`docs/07-troubleshooting.md`](07-troubleshooting.md#kokoro-voice-404).

## Volume

Kokoro's output is quieter than Qwen3-TTS. If you can't hear Reachy at 60 %:

```bash
curl -X POST http://$ROBOT_IP:8000/api/volume/set \
  -H "Content-Type: application/json" -d '{"volume":100}'
```

## Reachy sleeping unprompted

Reachy has an inactivity timeout of 24 hours by default, so idle sleep
isn't the usual culprit. What DOES cause surprise naps: the LLM calling
`go_to_sleep` on ambiguous phrasing ("ok we're good for now"). This
repo's `tools.txt` intentionally omits that tool. To wake her back up:

```bash
curl -X POST http://$ROBOT_IP:8000/api/motors/set_mode/enabled
curl -X POST http://$ROBOT_IP:8000/api/move/goto \
  -H "Content-Type: application/json" \
  -d '{"head":{"x":0,"y":0,"z":0,"roll":0,"pitch":0,"yaw":0,"degrees":true,"mm":true},"antennas":[-0.1745, 0.1745],"duration":5.0}'
```
