#!/usr/bin/env bash
set -euo pipefail

CLUSTER="k8s-dra-driver-cluster"
NS_APP="ai-inference-lab"
NS_DRIVER="hami-dra-driver"

echo "=== Cleanup ==="

for ns in "${NS_APP}" test-dra; do
  # Delete pods first — they hold ResourceClaims, which can't be released while in use
  kubectl delete pods --all -n "${ns}" --ignore-not-found --wait=true --timeout=30s 2>/dev/null || true
  # Now safe to delete claims (pods have released them)
  kubectl delete resourceclaims --all -n "${ns}" --ignore-not-found --wait=true --timeout=30s 2>/dev/null || true
  kubectl delete services --all -n "${ns}" --ignore-not-found 2>/dev/null || true
  kubectl delete configmaps --all -n "${ns}" --ignore-not-found 2>/dev/null || true
  kubectl delete namespace "${ns}" --ignore-not-found --wait=false 2>/dev/null || true
done

kubectl delete deviceclasses hami-core-gpu.project-hami.io --ignore-not-found 2>/dev/null || true
DRA_DIR="$(cd "$(dirname "$0")" && pwd)/../k8s-dra-driver"
kubectl delete -f "${DRA_DIR}/demo/yaml/ds.yaml" --ignore-not-found 2>/dev/null || true
kubectl delete -f "${DRA_DIR}/demo/yaml/rbac.yaml" --ignore-not-found 2>/dev/null || true
kubectl delete -f "${DRA_DIR}/demo/yaml/setup.yaml" --ignore-not-found 2>/dev/null || true
helm uninstall hami-dra-driver -n "${NS_DRIVER}" 2>/dev/null || true
kubectl delete namespace "${NS_DRIVER}" --ignore-not-found --wait=false 2>/dev/null || true

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER}$"; then
  kind delete cluster --name "${CLUSTER}"
fi

echo "Cleanup done."
