# Building the fast-start image

The whole reason this Dockerfile exists is to avoid the ~5 min apt + pip
install cycle on every pod cold-start.

## Build on the node with nerdctl

RKE2 uses containerd, so `nerdctl` builds directly into the same image
store the kubelet reads from — no push required.

```bash
ssh your-user@$NODE_IP

# One-time: install buildkit if not already present
sudo apt-get install -y buildkit
sudo systemctl enable --now buildkit

# Copy the build context
scp -r image/ your-user@$NODE_IP:/tmp/reachy-s2s/

# Build into the k8s.io namespace so kubelet can see it
sudo nerdctl -n k8s.io build -t localhost/reachy-s2s:latest /tmp/reachy-s2s/
```

Verify the image is visible to kubelet:

```bash
sudo nerdctl -n k8s.io images | grep reachy-s2s
```

## Base image choice

The Dockerfile defaults to `nvcr.io/nvidia/pytorch:25.06-py3`, which is
NVIDIA's official multi-arch PyTorch image (aarch64 SBSA works for DGX
Spark / Blackwell). If you're on:

- **x86_64 Blackwell / Hopper**: same image, but `--platform linux/amd64`.
- **Jetson / iGPU**: use `nvcr.io/nvidia/pytorch:25.06-py3-igpu` or
  `dustynv/pytorch` — has integrated GPU support built in.
- **Older GPUs (Ada, Ampere)**: drop the cu129 torch pin, use cu126 or
  cu128 which have wider hardware support but no sm_120 kernels.

Override with:

```bash
sudo nerdctl -n k8s.io build \
  --build-arg BASE=nvcr.io/nvidia/pytorch:25.06-py3-igpu \
  -t localhost/reachy-s2s:latest /tmp/reachy-s2s/
```

## Multi-node cluster (with a registry)

If you have more than one GPU node, build once and push to any registry
the nodes can reach:

```bash
# Local Harbor / Zot / Docker Hub / GHCR / ECR — any OCI-compliant registry
sudo nerdctl -n k8s.io build -t registry.example.com/reachy-s2s:latest /tmp/reachy-s2s/
sudo nerdctl -n k8s.io push registry.example.com/reachy-s2s:latest
```

Then update `k8s/statefulset.yaml`:

```yaml
image: registry.example.com/reachy-s2s:latest
imagePullPolicy: Always
```

## Cold-start timing

| Stage | Baked image | No baked image |
|---|---:|---:|
| Image pull (cached) | ~0 s | ~0 s |
| apt-get install (200 packages) | 0 s | ~120 s |
| pip install torch + torchaudio + torchvision (~2 GB) | 0 s | ~90 s |
| pip install s2s + Kokoro + deps | 0 s | ~60 s |
| Silero VAD download | 0 s | ~10 s |
| NLTK / spaCy data | 0 s | ~15 s |
| Kokoro model download | 0 s | ~20 s |
| Parakeet-TDT warmup | ~5 s | ~5 s |
| LLM cold ping to Ollama | ~1 s | ~1 s |
| Kokoro warmup | ~1 s | ~1 s |
| **Total** | **~30 s** | **~5 min** |

If the s2s package updates upstream and you need the newer git-HEAD, just
rebuild the image (`nerdctl build` is incremental — only the pip layer
re-runs).
