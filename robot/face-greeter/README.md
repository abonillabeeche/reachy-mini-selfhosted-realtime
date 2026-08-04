# Face greeter (WIP — disabled by default)

Recognize familiar faces from Reachy's camera and greet them by name. Runs on
the robot in the daemon venv (which has `cv2` + `onnxruntime`). Uses OpenCV's
built-in **YuNet** (detection) + **SFace** (recognition) — no `insightface`/`dlib`.

**Status:** functional but **not enabled**. On the Raspberry Pi CM4 the
recognition inference competes with the daemon's motor/face-tracking loops, so
greeting timing is slow/inconsistent when run at low priority (and it lags
tracking when run at normal priority). Kept here for a future, more efficient
integration (see "Better paths" below). Face *tracking* (Reachy following a
face) is a separate daemon feature and is unaffected.

## Files
- `face_greeter.py` — recognition engine + CLI (`enroll` / `identify` / `list` from image files)
- `livecam.py` — live camera helper (`capture` / `enroll-live` / `identify-live` / `watch`); reads frames via `MediaManager(LOCAL)` (shared-memory IPC, second consumer alongside the app)
- `fetch_models.sh` — downloads the YuNet + SFace ONNX models into `models/`
- `run-greeter.sh` — service launcher: waits for the daemon, re-uploads greeting WAVs, sets thresholds, runs the watcher
- `reachy-face-greeter.service` — systemd unit (SCHED_IDLE priority)

Runtime state lives on the robot under `~/reachy-face/` (models, `known_faces.npz`, `greetings/*.wav`).

## Install / enable
```bash
# on the robot (pollen@<ROBOT_IP>)
mkdir -p ~/reachy-face && cd ~/reachy-face
# copy this dir's files here, then:
bash fetch_models.sh
/venvs/mini_daemon/bin/python livecam.py enroll-live <Name>      # learn a face
# drop a greet_<Name>.wav in ~/reachy-face/greetings/ (e.g. via mac/say-reachy.sh)
sudo cp reachy-face-greeter.service /etc/systemd/system/
sudo systemctl enable --now reachy-face-greeter        # start + auto-start on boot
sudo systemctl disable --now reachy-face-greeter       # stop + disable
```

Tuning knobs (env in `run-greeter.sh`): `FACE_MATCH_THRESHOLD` (0.6),
`GREET_MIN_FRAMES` (3), `GREET_MIN_FACE_W` (26 on the downscaled frame),
`DET_WIDTH` (960), `GREET_CADENCE` (0.8s), `GREET_COOLDOWN` (60s). Greetings
are gated by `/api/move/running` so they never interrupt a playing move/sing.

## Better paths (future)
- **In-app:** run recognition inside the conversation app, reusing the frames
  it already decodes (no second camera pipeline ≈ half the load) and greet in
  her own LLM voice. Needs `opencv-python-headless` in `apps_venv`.
- **Offload:** send occasional frames to the GPU node for recognition; near-zero
  load on the Pi; trigger the greeting back over REST.
