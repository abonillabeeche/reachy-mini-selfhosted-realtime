# Cluster-side setup

Deploy the s2s realtime backend into your cluster.

## 1. Bake the image on the node

The Dockerfile in [`image/`](../image/) pre-installs everything the pod
needs at runtime. Build it once directly on the GPU node — no registry
required — and reference it by local tag:

```bash
# From your control machine, copy the build context to the node
scp -r image/ your-user@$NODE_IP:/tmp/reachy-s2s/

# On the node
ssh your-user@$NODE_IP
cd /tmp/reachy-s2s
sudo nerdctl -n k8s.io build -t localhost/reachy-s2s:latest .
```

First build takes ~5 min (apt, torch stack ~2 GB, s2s + Kokoro + models).
The StatefulSet references `localhost/reachy-s2s:latest` with
`imagePullPolicy: IfNotPresent`, so as long as the image exists on the
node, kubelet uses it.

If you have multiple GPU nodes, either build on each or push to a
registry (Harbor, GHCR, ECR) and update `k8s/statefulset.yaml`.

## 2. Install a StorageClass (once)

The StatefulSet claims a 20 GB PVC for the HuggingFace model cache
(Kokoro weights, Silero VAD, etc.). Simplest choice: Rancher's
[`local-path-provisioner`](https://github.com/rancher/local-path-provisioner):

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

If you already have a StorageClass, edit
[`k8s/statefulset.yaml`](../k8s/statefulset.yaml) to reference it.

## 3. Apply the manifests

```bash
kubectl apply -k k8s/
```

That creates the `reachy-s2s` namespace, the StatefulSet, the PVC (via
volumeClaimTemplates), and the Service.

## 4. Wait for the pod to become Ready

```bash
kubectl -n reachy-s2s wait --for=condition=Ready pod -l app=reachy-s2s --timeout=300s
```

With the baked image this should be ~30 s. Without it (Deployment without
the Dockerfile) expect ~5 min the first time (apt install + torch pip +
model downloads).

## 5. Verify the WebSocket is reachable

```bash
curl -o /dev/null -w "%{http_code}\n" http://$NODE_IP:31765/
# → 404 (expected — it's a WebSocket endpoint, GET / has no handler)
```

If you get `Connection refused`, the pod isn't listening yet. Check logs:

```bash
kubectl -n reachy-s2s logs sts/reachy-s2s --tail=50
```

You want to see:

```
speech_to_speech.STT.parakeet_tdt_handler - INFO - Model warmed up and ready
speech_to_speech.LLM.responses_api_language_model - INFO - ResponsesApiModelHandler: warmed up! time: X s
speech_to_speech.TTS.kokoro_handler - INFO - KokoroTTSHandler warmed up
speech_to_speech.api.openai_realtime.server - INFO - OpenAI Realtime API starting on ws://0.0.0.0:8765/v1/realtime
```

If the LLM warmup fails with a connection error, check that Ollama's
in-cluster DNS (`ollama.ollama.svc.cluster.local:11434`) matches your
actual Service name/namespace. Override with `LLM_BASE_URL` in the
StatefulSet env.
