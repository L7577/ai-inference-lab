#!/usr/bin/env bash
set -euo pipefail
NS="ai-inference-lab"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Phase 2: Deploy 3 Sharded GPU Pods ==="

# --- DeviceClass + ResourceClaims ---
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: ai-inference-lab
---
apiVersion: resource.k8s.io/v1
kind: DeviceClass
metadata:
  name: hami-core-gpu.project-hami.io
spec:
  selectors:
  - cel:
      expression: |-
        device.driver == "hami-core-gpu.project-hami.io" &&
        device.attributes["hami-core-gpu.project-hami.io"].type == "hami-gpu"
---
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: gpu-high
  namespace: ai-inference-lab
spec:
  devices:
    requests:
    - name: gpu
      exactly:
        deviceClassName: hami-core-gpu.project-hami.io
        capacity:
          requests:
            cores: "40"
            memory: "1600Mi"
---
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: gpu-mid
  namespace: ai-inference-lab
spec:
  devices:
    requests:
    - name: gpu
      exactly:
        deviceClassName: hami-core-gpu.project-hami.io
        capacity:
          requests:
            cores: "35"
            memory: "1200Mi"
---
apiVersion: resource.k8s.io/v1
kind: ResourceClaim
metadata:
  name: gpu-low
  namespace: ai-inference-lab
spec:
  devices:
    requests:
    - name: gpu
      exactly:
        deviceClassName: hami-core-gpu.project-hami.io
        capacity:
          requests:
            cores: "25"
            memory: "800Mi"
YAML

# --- Deploy pods ---
deploy_pod() {
  local name="$1" claim="$2" port="$3"
  kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  namespace: ${NS}
  labels:
    app: ${name}
spec:
  containers:
  - name: inference
    image: ai-inference-lab:latest
    imagePullPolicy: Never
    env:
    - name: PORT
      value: "${port}"
    ports:
    - containerPort: ${port}
      name: http
    resources:
      requests:
        memory: "2Gi"
        cpu: "1"
      limits:
        memory: "8Gi"
        cpu: "2"
      claims:
      - name: gpu
  resourceClaims:
  - name: gpu
    resourceClaimName: ${claim}
---
apiVersion: v1
kind: Service
metadata:
  name: ${name}
  namespace: ${NS}
spec:
  selector:
    app: ${name}
  ports:
  - port: ${port}
    targetPort: ${port}
YAML
}

deploy_pod "model-high" "gpu-high" 8001
deploy_pod "model-mid"  "gpu-mid"  8002
deploy_pod "model-low"  "gpu-low"  8003

# --- Wait for all pods ---
echo "Waiting for pods (model loading ~30s)..."
for pod in model-high model-mid model-low; do
  kubectl -n "${NS}" wait --for=condition=Ready pod/${pod} --timeout=180s
  echo "  ${pod} ready"
done

echo ""
echo "=== Deploy complete ==="
kubectl get resourceclaim -n "${NS}"
kubectl get pods -n "${NS}" -o wide
kubectl get svc -n "${NS}"
