# Architecture

## Data flow — one voice turn

```
1.  You speak                           mic on Reachy
2.  VAD detects speech onset            speech-to-speech (in s2s pod, on GPU)
3.  Audio streams over WebSocket        ws://NODE_IP:31765/v1/realtime
4.  VAD detects speech end (~0.5 s)     s2s
5.  Parakeet-TDT transcribes            s2s (60-150 ms)
6.  Chat LLM decides + generates        Ollama /v1/responses on node (~1 s)
       └─ may call a tool:
          • idle_do_nothing        → silence
          • move_head / dance / …  → local motion via app tool
          • lower_antennas / …     → local motion via custom tool
          • camera(question)       ┐
                                   ▼
                       ┌──────────────────────┐
                       │ camera.py            │
                       │  grabs JPEG from     │
                       │  deps.reachy_mini    │
                       │  .media.get_frame()  │
                       │  POSTs to VLM        │
                       │  ← text description  │
                       └──────────────────────┘
                                   │
                       tool result (text) returns to chat LLM
                                   │
7.  Chat LLM generates final text       Ollama (~1 s)
8.  Kokoro synthesises audio            s2s TTS (~0.5-2 s)
9.  Audio streams back over WebSocket   ws://…
10. Speaker plays                       Reachy speaker
```

Total end-to-end latency, typical:
- No tool: **1.5 – 3 seconds** from end-of-speech to first spoken word.
- With camera: **4 – 8 seconds** (VLM first-call on cold model is slower).

## Why this split rather than one big multimodal model?

We ran into two independent limits:

1. **VLMs in Ollama don't accept tool schemas.** `qwen2.5vl:7b` returns
   `400 Bad Request: registry.ollama.ai/library/qwen2.5vl:7b does not
   support tools` the moment the s2s pipeline sends a request with a
   `tools` array. So we can't use a VLM as the chat LLM if we want tools.
2. **Small text LLMs handle tool calling well but aren't multimodal.**
   `llama3.1:8b` handles the Responses API tool loop cleanly but has no
   vision path.

So: **use both, and keep them apart.** llama3.1:8b runs in the s2s
pipeline (with tools). qwen2.5vl:7b runs on the same Ollama, only called
by the custom `camera.py` tool over HTTP with an image + question, and
returns text.

## Physical topology (our reference)

- **DGX Spark** (10.0.0.10 in our LAN) — Grace-Blackwell, single GB10 GPU,
  128 GB unified memory. Runs a single-node RKE2 cluster with:
  - `ollama` namespace: Ollama server, GPU-scheduled, NodePort 31434.
  - `reachy-s2s` namespace: this repo's pod, NodePort 31765.
  - `gpu-operator`, `local-path-provisioner`, etc.
- **Reachy Mini Wireless** (10.0.0.20) — Raspberry Pi CM4, WiFi to the
  same LAN. Runs the daemon + conversation app that connect out to the
  DGX Spark.

The robot never sees the internal cluster network; it hits NodePort
endpoints on the GPU node's LAN address.

## GPU memory budget (reference)

| Model | Loaded VRAM (unified) | Notes |
|---|---:|---|
| llama3.1:8b | ~30 GB | pinned by `keep_alive: 10m` after each turn |
| qwen2.5vl:7b | ~70 GB | pinned by `keep_alive: -1` for low camera latency |
| Parakeet-TDT 0.6B v3 | ~1 GB | in s2s pod |
| Kokoro-82M | ~0.5 GB | in s2s pod |
| **Total peak** | **~102 GB** | out of ~128 GB unified — enough headroom for one more small model |

If tight, unpin the VLM (drops to ~30 GB) and pay 3-8 s first-call
latency each time the camera is used.
