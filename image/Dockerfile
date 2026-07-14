# syntax=docker/dockerfile:1.6
#
# Baked runtime image for the HuggingFace speech-to-speech server used as
# Reachy Mini's realtime backend.
#
# Rationale: without this image, the pod does apt-install + pip-install at
# every fresh container start (~5 min). Baking it drops cold-start to ~30 s.
#
# Build directly on the GPU node (no registry required):
#   sudo nerdctl -n k8s.io build -t localhost/reachy-s2s:latest .
# Then reference `localhost/reachy-s2s:latest` in the StatefulSet with
# imagePullPolicy: IfNotPresent.
#
# Base image assumes an aarch64 SBSA Blackwell (DGX Spark GB10) host with
# CUDA 12.9 in the container. Adjust `--platform`/tag for x86 or other GPUs.

ARG BASE=nvcr.io/nvidia/pytorch:25.06-py3
FROM ${BASE}

# --- 1. System audio stack ---
# Everything speech-to-speech + Kokoro need at runtime (ffmpeg, portaudio,
# espeak-ng for phonemization, libsndfile for wav I/O).
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ffmpeg \
      libsndfile1 \
      portaudio19-dev \
      espeak-ng \
    && rm -rf /var/lib/apt/lists/*

# --- 2. Python stack: matched torch+torchaudio+torchvision for Blackwell ---
# The container's NVIDIA-built torch (2.8.0a0) has no PyPI torchaudio wheel
# for the same version, and cu126/cu128 PyPI torch lacks sm_120 kernels. cu129
# has full Blackwell support and a matched torchaudio/torchvision pair.
# Override the container's /etc/pip constraint that would otherwise pin torch.
ENV PIP_CONSTRAINT=""
RUN pip install --no-cache-dir \
      --index-url https://download.pytorch.org/whl/cu129 \
      --extra-index-url https://pypi.org/simple \
      torch==2.11.0 torchaudio==2.11.0 torchvision

# The container ships a torchvision built for its own torch 2.8; strip it so
# the pip-installed one wins (avoids `operator torchvision::nms does not exist`).
RUN rm -rf /usr/local/lib/python3.12/dist-packages/torchvision \
           /usr/local/lib/python3.12/dist-packages/torchvision-*.dist-info

# --- 3. speech-to-speech + Kokoro + support libs ---
# Installed from HuggingFace's main branch; pypi 0.2.10 lacks the CLI flags
# and `chat-completions`/`responses-api` LLM backends we rely on.
# `hf-xet` is uninstalled because it 401s against the CAS backend for public
# models in this environment; the classic HTTP download path works fine.
RUN pip install --no-cache-dir \
      "speech-to-speech @ git+https://github.com/huggingface/speech-to-speech.git" \
      "hf-transfer" \
      "kokoro>=0.9.2" \
      "soundfile" \
      "httpx" \
  && pip uninstall -y hf-xet || true

# --- 4. NLTK + spaCy assets that s2s and Kokoro download on first run ---
# Pre-fetch them so the pod doesn't hit the network on startup.
RUN python -m nltk.downloader -d /usr/share/nltk_data punkt_tab averaged_perceptron_tagger_eng \
 && python -m spacy download en_core_web_sm

ENV NLTK_DATA=/usr/share/nltk_data

# --- 5. Runtime env ---
# HF cache and Kokoro downloads land in /hf-cache (mounted from a PVC in k8s).
# LD_LIBRARY_PATH is unset in the entrypoint so pip's bundled nvidia_* CUDA
# libs are used instead of the container's /usr/local/cuda, which otherwise
# causes symbol-version mismatches at torch import time.
ENV HF_HOME=/hf-cache \
    HF_HUB_ENABLE_HF_TRANSFER=0 \
    HF_HUB_DISABLE_XET=1 \
    PYTHONUNBUFFERED=1

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8765
ENTRYPOINT ["/entrypoint.sh"]
