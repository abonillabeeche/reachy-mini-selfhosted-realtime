# Troubleshooting — everything we hit while building this

Organized roughly in the order you'd hit them if you set this up from
scratch.

## 1. Image / driver / CUDA layer

### `libcudart.so.13: cannot open shared object file`

Symptom: pod crashes during `import torch` or `import torchaudio`.
Cause: pip's `torchaudio` wheel was built against CUDA 13, but the
container has CUDA 12.x.
Fix: this repo's Dockerfile installs `torchaudio` from the
`https://download.pytorch.org/whl/cu129` index — those wheels are CUDA
12.9-linked and load correctly.

### `libcusparse.so.12: undefined symbol: __nvJitLinkGetErrorLogSize_12_9`

Symptom: `import torch` at pod start fails with a symbol-version error.
Cause: container's `/usr/local/cuda/lib64` on `LD_LIBRARY_PATH` beats
pip's bundled `nvidia_*` CUDA libs; the loader mixes container libcusparse
(12.9) with pip libnvJitLink (12.6).
Fix: `unset LD_LIBRARY_PATH` in the entrypoint (baked into our image).
The pip torch stack ships its own consistent CUDA libs.

### `no kernel image is available for execution on the device`

Symptom: torch loads, but any op fails at runtime.
Cause: torch was built for compute-capability list that excludes your GPU.
Blackwell needs sm_120, which cu126 wheels lack.
Fix: use the `cu129` (or newer) index — its wheels include sm_120.

### `CUDA kernel mma has no device code compatible with CUDA arch 750`

Symptom: `qwentts.cpp` (the C++ backend behind `faster-qwen3-tts`, the
default TTS) spews thousands of these on startup, then aborts.
Cause: qwentts.cpp shipped as a wheel with CUDA compilation targeting
Turing (sm_75) through Blackwell (sm_120), but somehow fails at runtime on
Blackwell — possibly needing a rebuild against a newer CUDA toolkit.
Fix: use Kokoro instead — pass `--tts kokoro` to speech-to-speech. Kokoro
is pure-torch and just works.

### `nvrtc: invalid value for --gpu-architecture (-arch)`

Symptom: torch runtime tries to JIT-compile a kernel and fails.
Cause: bundled nvrtc doesn't recognize sm_120.
Fix: same as above — cu129 wheels include a newer nvrtc.

## 2. Speech-to-speech pip layer

### `ERROR: pip's dependency resolver ... constraint torch==2.8.0a0+…nv25.06`

Symptom: `pip install torch==2.11.0` fails because a constraint file
pins torch to NVIDIA's own build.
Cause: nvcr PyTorch images have a `/etc/pip/constraints.txt` that pins
torch.
Fix: `export PIP_CONSTRAINT=""` before the pip install (baked into our
Dockerfile).

### `operator torchvision::nms does not exist`

Symptom: `from transformers import AlbertModel` (transitive from Kokoro)
raises this at import.
Cause: container ships a torchvision built for its own torch 2.8; when
you install a different torch, transformers imports the container's stale
torchvision which tries to register an op against the new torch and fails.
Fix: `rm -rf /usr/local/lib/python3.12/dist-packages/torchvision*` and
`pip install torchvision` in the Dockerfile (both baked in).

### `does not support tools` — 400 from Ollama

Symptom: chat LLM path errors with
`registry.ollama.ai/library/qwen2.5vl:7b does not support tools`.
Cause: VLMs in Ollama don't accept tool schemas.
Fix: use a chat model that supports tools (`llama3.1:8b`, `mistral-nemo`,
etc.) and route vision through the custom `camera.py` — see
[Architecture](01-architecture.md).

## 3. HuggingFace Hub

### `401 Unauthorized` when downloading Kokoro voice files

Symptom:
```
huggingface_hub.errors.EntryNotFoundError: 404 Client Error.
Entry Not Found for url: https://cas-server.xethub.hf.co/…
```
Cause: `hf_xet` is installed and tries to fetch via HuggingFace's Xet
CAS backend, which returns 401 for anonymous requests on some public
models.
Fix: `pip uninstall hf-xet` and set `HF_HUB_DISABLE_XET=1` (both baked in).

### <a name="kokoro-voice-404"></a>Kokoro voice 404 (`Aiden.pt` etc.)

Symptom: TTS fails with
`EntryNotFoundError ... /voices/Aiden.pt` — 404.
Cause: the conversation app's `HF_AVAILABLE_VOICES` is a hardcoded list of
Qwen3-TTS speaker names (Aiden, Ryan, Dylan, …). Any voice you set that
isn't in the list gets silently mapped back to "Aiden". Kokoro doesn't
ship an `Aiden.pt`.
Two fixes:

1. **Patch the allowlist** — add Kokoro voices (`af_heart`, `af_bella`, …)
   to `config.HF_AVAILABLE_VOICES` and set `startup_settings.json` to
   one of them. See [Robot setup](04-robot-setup.md#kokoro-voice-patch).
2. **Symlink** — inside the pod's Kokoro cache, `ln -s af_heart.pt Aiden.pt`.
   Simpler; works even if the app insists on "Aiden".

## 4. Motor / body

### Head snaps up hard when the app restarts

Symptom: on `restart-current-app`, Reachy's head jerks up violently
(fast goto + "toudoum" sound + 20° roll wiggle).
Cause: `app_lifecycle.wake_up_if_sleeping()` calls `robot.wake_up()`,
which is the SDK's choreographed wake sequence (fixed 2 s goto + audio
+ 20° roll each way in 0.2 s).
Fix: apply [`robot/patches/app_lifecycle-slow-wake.patch`](../robot/patches/app_lifecycle-slow-wake.patch)
which replaces it with `robot.enable_motors()` +
`goto_target(INIT_HEAD_POSE, duration=5.0)`. Smooth.

### Waking via REST looks like it works but nothing moves

Symptom: `POST /api/motors/set_mode/enabled` returns 200, `POST /api/move/goto`
returns a task UUID, but Reachy stays limp.
Cause: on app shutdown, `AppManager` (in the SDK) detects Reachy is at
sleep pose and calls `MotorControlMode.Disabled` to "leave it limp".
Subsequent goto commands enqueue but can't execute — motors are off.
Fix: the correct sequence is always
`set_mode/enabled` → `move/goto`. If motors were disabled beforehand,
`enable_motors()` in the SDK pins the target to the present pose before
energizing (so no snap). Our patch does this in the wake path.

### `Motor communication error! Check connections and power supply.`

Symptom: transient hardware bus error, disappears within seconds.
Cause: rapid mode changes can hiccup the Dynamixel bus. Usually harmless.
Fix: wait 5 s, try again. If persistent, power-cycle the robot.

## 5. LLM behaviour

### `text=''` — Reachy calls a tool but doesn't speak

Symptom: `Sending to clients: text='', tools=['play_emotion']`.
Cause: llama3.1:8b treats a tool call as a complete response and produces
no text. The tool fires but Reachy stays silent.
Mitigation (imperfect): the profile's `## CRITICAL RESPONSE RULES` section
tells the LLM to always speak alongside tools. Works ~half the time.
Full fix would require a different chat model with stronger
text-plus-tool concurrent output behaviour.

### Reachy puts herself to sleep unexpectedly

Symptom: after a casual sign-off ("ok we're good", "thanks Reachy"),
Reachy folds down and disables motors.
Cause: `go_to_sleep` tool description is permissive; the LLM interprets
these phrases as "end the conversation".
Fix: don't include `go_to_sleep` in `tools.txt`. This repo's example
tools list already omits it.

### Reachy leaks her prompt / reasoning after a correction

Symptom: user corrects Reachy; her next turn dumps chain-of-thought or
system-prompt text.
Fix: the profile's `## NEVER LEAK INTERNAL STATE` section addresses this.
If it still happens intermittently, that's model behaviour drift; try a
stricter system-prompt or a different chat model.

## 6. Connectivity

### `error trying to reach service: cluster agent disconnected`

Symptom: kubectl via Rancher fails with this.
Cause: `cattle-cluster-agent` in `cattle-system` namespace crashed.
Fix: `kubectl -n cattle-system rollout restart deploy/cattle-cluster-agent`
via a locally-scoped kubeconfig (SSH to the node, use
`/etc/rancher/rke2/rke2.yaml` with `sudo /var/lib/rancher/rke2/bin/kubectl`).

### App connected but no audio comes back

- Volume: Kokoro output is quieter than the HF Realtime default. Set
  volume to 90-100 via
  `POST /api/volume/set` with `{"volume":100}`.
- WebSocket dropped: check the s2s pod for `WebSocket /v1/realtime [accepted]`
  in recent logs. If missing after a restart, the conversation app didn't
  reconnect — restart it via `POST /api/apps/restart-current-app`.

## 7. GPU memory

### Node reports high VRAM usage even when idle

Cause: Ollama models loaded with `keep_alive: -1` never expire.
`llama3.1:8b` runs at ~30 GB, `qwen2.5vl:7b` at ~70 GB, and Ollama's
per-model VRAM math on unified-memory Blackwell tends to over-report.

Free memory:

```bash
# Unload a specific model (does NOT delete from disk; auto-reloads on next call)
curl http://$NODE_IP:31434/api/generate \
  -d '{"model":"gpt-oss:20b","keep_alive":0}'
```

Check what's loaded:

```bash
curl http://$NODE_IP:31434/api/ps
```

If sharing the cluster with other users' agents, treat any model you
didn't pull yourself as belonging to them — unload only after asking.

## Reachy randomly switches accent/language (goes "full Italian")

Kokoro's TTS auto-detects the language of each turn (from the STT result) and
swaps the whole voice to that language's default (e.g. English→Italian
`if_sara`, or British `bm_fable` which is also *male*). Mis-detections make
Reachy flip accent/gender mid-conversation.

There's no "mild accent only" mode — it's all-or-nothing per language. To lock
Reachy to English (stay on your chosen voice), disable the switch in the s2s
Kokoro handler:

```
# in the s2s pod: /pip-site/.../speech_to_speech/TTS/kokoro_handler.py
# replace:  new_lang_code = WHISPER_LANGUAGE_TO_KOKORO_LANG.get(language_code, self.lang_code)
# with:     new_lang_code = self.lang_code   # disable language/voice auto-switch
```
Then restart the s2s pod. (Two occurrences in the file.)
