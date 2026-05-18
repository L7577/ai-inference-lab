#!/usr/bin/env bash
set -euo pipefail
NS="ai-inference-lab"

echo "=== Phase 3: Verify ==="

echo ""
echo "--- 1. ResourceClaims ---"
kubectl get resourceclaim -n "${NS}" -o wide

echo ""
echo "--- 2. Pods ---"
kubectl get pods -n "${NS}" -o wide

declare -A PORTS
PORTS[model-high]=8001
PORTS[model-mid]=8002
PORTS[model-low]=8003

for pod in model-high model-mid model-low; do
  port="${PORTS[$pod]}"
  echo ""
  echo "========== ${pod} (port ${port}) =========="

  echo "--- HAMi-Core env ---"
  kubectl exec -n "${NS}" "${pod}" -- env | grep -E "CUDA_DEVICE_SM_LIMIT|CUDA_DEVICE_MEMORY_LIMIT" || echo "  WARN: no HAMi env vars"

  echo "--- /health ---"
  kubectl exec -n "${NS}" "${pod}" -- python -c "
import urllib.request,json
r=urllib.request.urlopen('http://localhost:${port}/health')
print(json.dumps(json.loads(r.read()),indent=2))
" 2>/dev/null || echo "  WARN: health check failed"

  echo "--- /metrics ---"
  kubectl exec -n "${NS}" "${pod}" -- python -c "
import urllib.request,json
r=urllib.request.urlopen('http://localhost:${port}/metrics')
d=json.loads(r.read())
print('  requests: ' + str(d.get('requests_ok',0)) + '/' + str(d.get('requests_total',0)))
print('  ttft_avg: ' + str(d.get('ttft_avg_ms',0)) + 'ms  rps: ' + str(round(d.get('throughput_rps',0),1)))
g=d.get('gpu',{})
print('  GPU mem: ' + str(g.get('memory_used_mb',0)) + 'MB used / ' + str(g.get('memory_total_mb',0)) + 'MB total')
" 2>/dev/null || echo "  WARN: metrics failed"
done

echo ""
echo "=== Verify complete ==="
