#!/usr/bin/env bash
# Slim runtime entrypoint. No apt / pip work — everything's baked in the image.
set -euo pipefail

# The container's LD_LIBRARY_PATH points at /usr/local/cuda/lib64 (CUDA 12.9),
# but our pip torch pulls its own bundled nvidia_* CUDA 12.9 libs. Mixing them
# causes symbol-version mismatches at `import torch`. Unset so torch uses its
# own bundled libs only.
unset LD_LIBRARY_PATH

: "${LLM_BACKEND:=responses-api}"
: "${LLM_MODEL:=llama3.1:8b}"
: "${LLM_BASE_URL:=http://ollama.ollama.svc.cluster.local:11434/v1}"
: "${LLM_API_KEY:=ollama}"
: "${TTS:=kokoro}"
: "${KOKORO_VOICE:=af_heart}"
: "${WS_HOST:=0.0.0.0}"
: "${WS_PORT:=8765}"

exec speech-to-speech \
  --mode realtime \
  --ws_host "${WS_HOST}" \
  --ws_port "${WS_PORT}" \
  --tts "${TTS}" \
  --kokoro_voice "${KOKORO_VOICE}" \
  --llm_backend "${LLM_BACKEND}" \
  --model_name "${LLM_MODEL}" \
  --responses_api_base_url "${LLM_BASE_URL}" \
  --responses_api_api_key "${LLM_API_KEY}"
