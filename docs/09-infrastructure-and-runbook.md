# Infrastructure, current state & runbook

Single source of truth for **all the nodes**, how they connect, what state things
are in, what changed, and how to recover. Read this first in any new session.

_Last updated: 2026-08-05._

## Nodes / inventory

| Host | IP | Role | Access |
|---|---|---|---|
| **reachy-mini** (robot) | `10.0.0.154` | Reachy Mini Wireless (Raspberry Pi CM4). Runs `reachy-mini-daemon` (REST `:8000`, motors, media/WebRTC `:8443`, camera, IMU, face tracking) + the conversation app. | SSH `pollen` / `root` (Pollen default). Host alias `reachy-mini-ptt` in `~/.ssh/config`. |
| **nvidia-spark** (GPU node) | `10.0.0.12` | DGX Spark (Grace-Blackwell GB10, sm_120). Runs **RKE2**; hosts the **s2s** pod, **Ollama**, and the VLM NodePort. | SSH `abonilla@10.0.0.12` (key already installed). `kubectl` on the node: `sudo /var/lib/rancher/rke2/bin/kubectl`. |
| **agx-orin-2** | `10.0.0.10` | Jetson AGX Orin — secondary compute (this is the `NODE_IP` placeholder in `.env.example`). Not currently in the live conversation path. | — |
| **Mac** (control) | — | The `reachy` CLI (`~/bin/reachy`), SwiftBar widget, this repo. | Config in `~/.config/reachy/env` (`ROBOT_IP`, `ROBOT_USER`, `ROBOT_PASS`). |

> The Mac's `kubectl` context `local` is a **Rancher management cluster** (cattle-* namespaces) — **NOT** the s2s RKE2 cluster. To touch s2s you must SSH to `10.0.0.12` and use the node's rke2 kubectl.

## How the pieces connect
```
Reachy (10.0.0.154)  ── ws://10.0.0.12:31765/v1/realtime ──►  s2s pod (reachy-s2s ns, node 10.0.0.12)
  conversation app                                              STT (Parakeet) + Smart Turn v3.2
  profile=upbeat, voice=af_nova (Kokoro)                        → LLM (Ollama qwen2.5:14b) → TTS (Kokoro af_heart)
  camera VLM ── http://10.0.0.12:31434/v1 ──► Ollama VLM (vision, out-of-band via profile camera.py)
  audio out ── external USB DAC (ALSA card Audio_1 / reachymini_audio_sink)
```

## Current software state (as of last update)
- **Robot:** `reachy_mini` SDK **1.9.0**; conversation app **0.9.0** (rolled back — see below). Active profile **upbeat**, voice **af_heart** (Kokoro; allowlist `af_heart`/`af_nova`/`af_bella` patched into `config.py`). Voice is set in `startup_settings.json`.
- **s2s:** **0.2.12** with **Smart Turn v3.2** (endpointing: ~600 ms think-pause tolerance, 800 ms speculative, turn revision). Installed in the pod's persistent `/pip-site` (hostPath `/opt/reachy-s2s/pip-site`), launched by the `s2s-entrypoint` ConfigMap's `run.sh`. LLM = Ollama `qwen2.5:14b`.
- **Face tracking:** enabled (she follows faces). **Face greeter:** built but **disabled** (see `robot/face-greeter/`).

## What changed in the big session (2026-08-04/05)
- **s2s Smart Turn v3.2** — upgraded `speech-to-speech` 0.2.10→0.2.12 in the pod's `/pip-site` and restarted the deploy. ✅ live & verified.
- **Conversation app v1.0.0** — attempted, **blocked**: v1.0.0 requires `reachy-mini>=1.10.0rc2` (needs `reachy_mini.io.jsonrpc`); robot is on SDK 1.9.0. Also new format (profiles→`profile.md`, `external_content/`, Tool classes, Qwen voice names). **Rolled back to 0.9.0** + re-applied Kokoro voice patch + upbeat/af_nova. To proceed with v1.0.0, **update the Reachy system/FW** (SDK ≥1.10) via Pollen's official updater first, then rebuild profiles/tools in the new format.
- **Mac controls** — added `dance/dance-long/waddle/sing/sing-long/emotion/whisper/stayin-alive/kill-bill/stop/happy/test`; removed `reachy song` (real-recording playback) per request. SwiftBar Actions now run **detached** (`nohup … &`) so long ones aren't killed.
- **Sleep fix** — `reachy sleep` now disables face tracking + wobbling first (they were overriding `goto_sleep` and keeping her up); `reachy wake` re-enables tracking.
- **Face greeter** — recognition (OpenCV YuNet+SFace) works, but disabled: too heavy alongside the daemon on the CM4. See its README.

## Recovery runbook (common failure → fix)
- **"Backend not running" / motors fail / app can't connect** → daemon backend stopped. `sudo systemctl restart reachy-mini-daemon.service` (not `daemon/start?wake_up=false` — that leaves it `ready=False`). App does **not** auto-start after a daemon restart → `POST /api/apps/start-app/reachy_mini_conversation_app`.
- **Motors enabled but `goto` doesn't move (`ready=False`, `last_alive=None`)** → wedged Dynamixel bus (often from rapid daemon restarts). **Reboot** the robot: `sshpass -p root ssh pollen@10.0.0.154 sudo reboot`. After boot, motion works again.
- **Camera dark / app crashes after `listen`/`see`/`open-control`** → media released; the `:8443` pipeline only runs while media is acquired. `POST /api/media/acquire`.
- **App errors on start: `Profile '…' has no profile.md`** → v1.0.0 running against old-format profile. (You're likely on v1.0.0 without SDK 1.10 — roll back or update FW.)
- **Speak/Whisper silent** → `say-reachy.sh` targets `$ROBOT`/`ROBOT_IP`; ensure `~/.config/reachy/env` has the right IP.
- **Audio seems to come from the built-in speaker after a reboot** → the external USB DAC (`Audio_1`) volume resets on reboot (and the card index can shift, e.g. 3→1; the `~/.asoundrc` sink targets it by name so routing is fine). Restore with `reachy volume 90`. Routing is `reachymini_audio_sink` → `hw:CARD=Audio_1` in `~/.asoundrc`; verify with `speaker-test -D reachymini_audio_sink`.
- **Change her voice** → edit `voice` in the app's `startup_settings.json` to a Kokoro voice in the `config.py` allowlist (e.g. `af_heart`), then `POST /api/apps/restart-current-app`. Heard only in live conversation (not via `reachy say`).
- **s2s changes** → rebuild by bumping the install marker or `pip install --user --upgrade` s2s in the pod's `/pip-site`, then `kubectl -n reachy-s2s rollout restart deploy/reachy-s2s` (on node 10.0.0.12).
- Quick health: **`reachy test`** (Mac) exercises motion + audio + happy mode end-to-end.

## Backups on the robot (rollback safety)
- `~/reachy_talk_data-backup-0.9.0.tgz` — profiles (incl. custom `suse`/`upbeat` + their tools).
- `~/app-custom-backup-0.9.0.tgz` — profiles + startup_settings.
- 0.9.0 app snapshot cached at `~/.cache/huggingface/hub/spaces--pollen-robotics--reachy_mini_conversation_app/snapshots/a52a98aef…`.

## Open items
- **v1.0.0 upgrade** — blocked on a Reachy system/FW update to SDK ≥1.10 (see above). Then: reinstall app, rebuild `suse`/`upbeat` as `profile.md` in `external_content/`, re-add tools (VLM camera, web_search, antennas, mute/unmute) as Tool classes, migrate to the Tools/MCP page.
- **Face greeter** — deferred; better as in-app (reuse app frames) or GPU-offloaded recognition.
- **Whistle synth** — WIP prototype (`mac/whistle-synth.py`), "too MIDI", parked for community input.
- **s2s deployment vs repo** — the live deploy (base image + `s2s-entrypoint` ConfigMap + `/pip-site`) differs from this repo's `image/` + `k8s/statefulset.yaml`; reconcile if you want the repo to be authoritative.
