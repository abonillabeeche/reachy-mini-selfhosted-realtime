# Reachy Mini — self-hosted realtime backend

Point the [Reachy Mini](https://www.hf.co/reachy-mini/) conversation app at
your own Kubernetes-hosted [speech-to-speech](https://github.com/huggingface/speech-to-speech)
pipeline. Local STT + LLM + TTS, plus a hybrid text-LLM-plus-VLM design so
you can use a good tool-calling chat model AND get camera vision without
either model compromising the other.

Verified end-to-end on a **Reachy Mini Wireless** talking to a single-node
**RKE2** cluster running on a **NVIDIA DGX Spark** (Grace-Blackwell, unified
memory). Should port to any single-GPU Kubernetes node with the NVIDIA
runtime and Ollama.

## Architecture

```
                    LAN (WiFi)
Reachy Mini Wireless ─────────────────────────────────────► GPU node (k8s)
  ┌──────────────────────┐                                  ┌──────────────────────┐
  │ reachy-mini-daemon   │                                  │ reachy-s2s pod        │
  │  + conversation_app  │  ws://NODE_IP:31765/v1/realtime  │  Parakeet-TDT (STT)   │
  │     • VAD/mic        │◄────────────────────────────────►│  ─► chat LLM (HTTP)   │
  │     • speaker        │                                  │  ─► Kokoro (TTS)      │
  │     • camera         │                                  └──────────────────────┘
  │     • profile+tools  │                                             │
  │       (custom        │   http://NODE_IP:31434/v1/chat/completions  │
  │        camera.py     │◄──────────────────────────── image + Q ─────┘
  │        calls VLM     │                                             ▼
  │        directly)     │                                  ┌──────────────────────┐
  └──────────────────────┘                                  │ ollama pod            │
                                                            │  llama3.1:8b   (chat) │
                                                            │  qwen2.5vl:7b  (vision)│
                                                            └──────────────────────┘
```

**Why the split?** llama3.1:8b handles OpenAI tool calling well but isn't
multimodal; qwen2.5vl:7b sees images but Ollama rejects it with
`does not support tools` when the s2s pipeline offers a tool schema. The
hybrid camera.py routes vision to the VLM out-of-band and returns a text
description, so the chat LLM never sees an image and vision never sees a
tool schema.

## Quick start

```bash
# 1. On your control machine — copy env template and edit
cp .env.example .env
$EDITOR .env

# 2. On the GPU node (once) — bake the fast-start image
scp image/* your-user@$NODE_IP:/tmp/reachy-s2s/
ssh your-user@$NODE_IP 'cd /tmp/reachy-s2s && sudo nerdctl -n k8s.io build -t localhost/reachy-s2s:latest .'
# ~5 min the first time; subsequent pod boots go from ~5 min → ~30 s.

# 3. From your control machine — deploy the k8s side (see docs/03-cluster-setup.md)
kubectl apply -k k8s/

# 4. Configure the robot (see docs/04-robot-setup.md)
NODE_IP=10.0.0.10 ROBOT_IP=10.0.0.20 PROFILE=my-profile ./robot/install.sh

# 5. Restart the conversation app on the robot
curl -X POST http://$ROBOT_IP:8000/api/apps/restart-current-app
```

Then talk to Reachy.

## Prerequisites

- **Kubernetes cluster with the NVIDIA GPU operator installed** (RKE2, K3s,
  standard k8s — any distribution). See [`docs/02-prereqs.md`](docs/02-prereqs.md).
- **Ollama running in the cluster** with the chat + vision models pulled.
  Deployed how you like; a NodePort or a ClusterIP DNS name both work.
- **A GPU with sm_120 support (Blackwell)** if you use the pinned model
  versions here. Older GPUs (Hopper H100, Ampere) work but need different
  torch/CUDA channel selection — see the Dockerfile comments.
- **A Reachy Mini Wireless** with its stock software, reachable over WiFi.
- On your control machine: `kubectl`, `ssh`, `sshpass`, `nerdctl` (or docker)
  on the node, and `gh` if you want to fork this repo.

## Repository map

| Path | What it is |
|---|---|
| [`image/`](image/) | Dockerfile + entrypoint for the baked s2s image. Build with `nerdctl build` on the node — no registry needed. |
| [`k8s/`](k8s/) | Namespace, StatefulSet, PVC (via `local-path-provisioner`), Service (NodePort). Kustomize-compatible. |
| [`robot/profile-example/`](robot/profile-example/) | A friendly generic persona (`instructions.txt`, `greeting.txt`, `tools.txt`) + the hybrid `camera.py`. Fork this for your own persona. |
| [`robot/tools/`](robot/tools/) | Reusable custom tools: `lower_antennas`, `raise_antennas`, `wiggle_antennas`. |
| [`robot/patches/`](robot/patches/) | `app_lifecycle-slow-wake.patch` — replace the choreographed `wake_up()` (fast, plays toudoum, wiggles 20°) with a smooth 5-second goto. |
| [`robot/systemd/`](robot/systemd/) | Drop-in template for the reachy-mini-daemon unit that points the app at your s2s + VLM. |
| [`robot/install.sh`](robot/install.sh) | Idempotent one-shot installer that pushes all robot-side files. |
| [`mac/say-reachy.sh`](mac/say-reachy.sh) | Speak arbitrary text through Reachy's speaker from a Mac. Handy for debugging without the whole voice loop. |

## Documentation

- [Architecture in depth](docs/01-architecture.md)
- [Prerequisites](docs/02-prereqs.md)
- [Cluster setup](docs/03-cluster-setup.md)
- [Robot setup](docs/04-robot-setup.md)
- [Building the fast-start image](docs/05-image-build.md)
- [Persistence & storage](docs/06-persistence.md)
- [Troubleshooting](docs/07-troubleshooting.md) — every pitfall found while building this

## Known behaviours / open items

- **Reachy can put herself to sleep unprompted.** llama3.1:8b will call
  `go_to_sleep` on ambiguous phrases like "ok, we're good for now". This
  repo's `tools.txt` intentionally omits `go_to_sleep`. If you re-add it,
  expect surprise naps.
- **First reply after a period of silence takes 5-8 seconds** when the
  camera is involved (VLM first-inference includes model swap-in on the
  GPU if it's been evicted; subsequent replies are 2-3 seconds).
- **Tool-only responses.** llama3.1:8b sometimes emits a tool call with an
  empty `text=` — the tool fires but Reachy doesn't speak. Mitigations in
  the profile discourage this but do not eliminate it.
- **Kokoro voice names ≠ HuggingFace realtime voice names.** The app's
  built-in voice allowlist is Qwen3-TTS speaker names (Aiden, Ryan, …); we
  patch it to accept `af_heart` and friends. See `docs/07-troubleshooting.md`.

## License

Apache 2.0 — see [LICENSE](LICENSE).
