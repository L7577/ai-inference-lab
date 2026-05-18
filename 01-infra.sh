#!/usr/bin/env bash
set -euo pipefail

CLUSTER="k8s-dra-driver-cluster"
DRIVER_IMAGE="projecthami/k8s-dra-driver:v0.1.0"
INFER_IMAGE="ai-inference-lab:latest"
DRA_DIR="/home/l/dev/testclaude/k8s-dra-driver"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Phase 1: Infrastructure ==="

# --- Pre-flight ---
for cmd in kind kubectl docker; do
  command -v "$cmd" &>/dev/null || { echo "FATAL: $cmd not found"; exit 1; }
done

docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${DRIVER_IMAGE}$" || {
  echo "FATAL: ${DRIVER_IMAGE} not found. Run: cd ${DRA_DIR} && make image"
  exit 1
}
echo "[OK] pre-flight checks"

# --- Build inference image ---
echo "Building inference image..."
docker build -t "${INFER_IMAGE}" "${DIR}"
echo "[OK] image built"

# --- GPU health check (host) ---
echo "Checking host GPU..."
if command -v nvidia-smi &>/dev/null; then
  gpu_free=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")
  echo "  GPU free memory: ${gpu_free}"
  if [ "${gpu_free}" != "unknown" ] && [ "$(echo "${gpu_free}" | grep -o '[0-9]\+')" -lt 2048 ]; then
    echo "WARNING: GPU free memory (${gpu_free} MiB) is low. A reboot may be needed if this persists."
  fi
else
  echo "  nvidia-smi not found — skipping host GPU check"
fi

# --- Create kind cluster ---
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
  kind delete cluster --name "${CLUSTER}"
fi
kind create cluster \
  --name "${CLUSTER}" \
  --image "kindest/node:v1.34.0" \
  --config "${DIR}/kind-config.yaml" \
  --retain

# --- Load images ---
kind load docker-image "${DRIVER_IMAGE}" --name "${CLUSTER}"
kind load docker-image "${INFER_IMAGE}" --name "${CLUSTER}"

# --- Install DRA driver ---
kubectl apply -f "${DRA_DIR}/demo/yaml/rbac.yaml"
kubectl apply -f "${DRA_DIR}/demo/yaml/ds.yaml"

echo "Waiting for driver..."
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=hami-dra-driver \
  -n hami-dra-driver --timeout=120s

for i in $(seq 1 10); do
  count=$(kubectl get resourceslices --no-headers 2>/dev/null | wc -l)
  if [ "$count" -gt 0 ]; then
    break
  fi
  [ "$i" -eq 10 ] && { echo "FATAL: no ResourceSlice"; exit 1; }
  sleep 3
done

echo ""
echo "=== Infrastructure ready ==="
kubectl get nodes
kubectl get pods -n hami-dra-driver
kubectl get resourceslices -o wide
