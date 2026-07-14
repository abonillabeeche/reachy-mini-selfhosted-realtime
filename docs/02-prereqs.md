# Prerequisites

Nothing in this repo installs Kubernetes, the GPU operator, or Ollama —
those are assumed. This page documents the specific setup we validated on.

## Cluster

Any single-GPU Kubernetes distribution will work. We used **RKE2 v1.35** on
Ubuntu 24.04 (Rancher's standard turnkey install):

```bash
curl -sfL https://get.rke2.io | sh -
systemctl enable --now rke2-server
# kubectl config
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
```

K3s or vanilla kubeadm work the same way. Multi-node is fine; you'll just
need the s2s pod pinned to the GPU node with a `nodeSelector`.

## GPU operator

The NVIDIA [gpu-operator](https://github.com/NVIDIA/gpu-operator) provides
the container runtime, driver, and device plugin. Install via Helm:

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm install --wait --generate-name -n gpu-operator --create-namespace \
  nvidia/gpu-operator --set driver.enabled=false
```

We disabled the operator's driver install (`driver.enabled=false`) because
the DGX Spark ships with the driver pre-installed. Adjust for your host.

Verify the node has the GPU resource:

```bash
kubectl describe node | grep -i "nvidia.com/gpu"
```

If you want multiple pods to share the single GPU, enable time-slicing in
the `ClusterPolicy`. On a single-tenant node (only Ollama and our s2s pod)
you can skip this: our StatefulSet does NOT request `nvidia.com/gpu: 1`
(it uses `runtimeClassName: nvidia` + `NVIDIA_VISIBLE_DEVICES=all` to see
the GPU without competing with Ollama for the device-plugin slot).

## Ollama

Any Ollama deployment works. We used the [`ollama/ollama`](https://hub.docker.com/r/ollama/ollama)
image as a Deployment in an `ollama` namespace, exposed as a NodePort so
the robot can reach it directly:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ollama
  namespace: ollama
spec:
  type: NodePort
  selector: {app: ollama}
  ports:
    - port: 11434
      targetPort: 11434
      nodePort: 31434
```

Pull the two models we need:

```bash
kubectl -n ollama exec deploy/ollama -- ollama pull llama3.1:8b
kubectl -n ollama exec deploy/ollama -- ollama pull qwen2.5vl:7b
```

Then (optional) pin the VLM in VRAM so the first camera call isn't slow:

```bash
curl http://NODE_IP:31434/api/generate \
  -d '{"model":"qwen2.5vl:7b","prompt":"hi","keep_alive":-1,"stream":false}'
```

## Reachy Mini

Any **Reachy Mini Wireless** running the stock OS from Pollen Robotics.
No modifications needed beyond what `robot/install.sh` does (drops in an
env file, patches one Python file, installs a profile).

Default SSH credentials for a fresh unit are documented at
<https://huggingface.co/docs/reachy_mini/platforms/reachy_mini/> — `pollen`
/ `root`. Change them.
