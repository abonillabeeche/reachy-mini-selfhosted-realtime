# Persistence & storage

What survives what.

| State | Where it lives | Survives pod restart | Survives node reboot |
|---|---|:---:|:---:|
| HuggingFace model cache (Kokoro, Silero VAD, Parakeet) | PVC `hf-cache` (StatefulSet volumeClaimTemplate) | ✅ | ✅ |
| pip site (s2s, torch, kokoro package) | Baked into image | ✅ | ✅ |
| apt packages (ffmpeg, portaudio, espeak-ng) | Baked into image | ✅ | ✅ |
| Ollama models (llama3.1, qwen2.5vl) | Ollama's own PVC | ✅ | ✅ |
| Reachy conversation-app runtime state | Robot filesystem | ✅ | ✅ |
| WebSocket session | In-memory in s2s + app | ❌ (auto-reconnects) | ❌ (auto-reconnects) |

## StatefulSet + PVC — why?

Earlier versions of this repo used a Deployment with `hostPath` mounts.
That worked but had two problems:

1. **No scheduling guarantees.** `hostPath` volumes are node-local, so if
   the pod is rescheduled to a different node it starts from scratch.
2. **No lifecycle around the data.** Deleting the Deployment doesn't
   clean up `hostPath` directories.

Moving to StatefulSet + `volumeClaimTemplates` gives you:

- Stable pod identity (`reachy-s2s-0`) — makes debugging easier.
- The `hf-cache` PVC is bound to the pod's identity. If you delete and
  recreate the StatefulSet, the same PVC re-binds.
- A real StorageClass can implement replication, snapshots, backup — you
  choose based on what you plug in (`local-path`, Longhorn, cloud CSI, …).

## First-cold-start expectations

After you build the image and apply the StatefulSet:

- **Fresh cluster, fresh PVC.** ~30 s to Ready. Kokoro's weights get pulled
  from HuggingFace during the first request (~2 s added to first turn).
- **Pod restart, same PVC.** ~15 s to Ready — everything's cached.
- **Node reboot.** ~30 s if the image is still in containerd's image
  store; ~5 min if garbage collection wiped the image (rare).

## What about restarting the whole cluster?

- `kubectl rollout restart sts/reachy-s2s -n reachy-s2s` — pod restart, PVC preserved.
- `kubectl delete sts reachy-s2s -n reachy-s2s` — pod removed, **PVC preserved**.
- `kubectl delete pvc hf-cache-reachy-s2s-0 -n reachy-s2s` — the actual data goes away.

## Sizing

The `hf-cache` PVC is 20 GB by default. Contents after a warm state:

```
~350 MB  hexgrad/Kokoro-82M model + voices
~500 MB  nvidia/parakeet-tdt-0.6b-v3
 ~20 MB  silero-vad
 ~50 MB  NLTK data / spaCy en_core_web_sm
```

Under a gigabyte in practice. Overprovision so future model swaps don't
force resize dance.
