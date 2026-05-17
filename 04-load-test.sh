#!/usr/bin/env bash
set -euo pipefail
NS="ai-inference-lab"

echo "=== Phase 4: Load Test ==="

declare -A PORTS
PORTS[model-high]=8001
PORTS[model-mid]=8002
PORTS[model-low]=8003

# Warmup each pod
for pod in model-high model-mid model-low; do
  port="${PORTS[$pod]}"
  kubectl exec -n "${NS}" "${pod}" -- python -c "
import urllib.request,json
data=json.dumps({'messages':[{'role':'user','content':'Hello'}],'max_tokens':16}).encode()
req=urllib.request.Request('http://localhost:${port}/v1/chat/completions',data=data,headers={'Content-Type':'application/json'})
urllib.request.urlopen(req)
" 2>/dev/null || true
done

# Load test each pod
for pod in model-high model-mid model-low; do
  port="${PORTS[$pod]}"
  echo ""
  echo "========== ${pod} (port ${port}) =========="
  kubectl exec -n "${NS}" "${pod}" -- python /load_test.py \
    --url "http://localhost:${port}/v1/chat/completions" \
    --requests 30 --concurrency 3 --max-tokens 32
done

# Post-load comparison
echo ""
echo "--- Post-load /metrics Comparison ---"
echo ""
for pod in model-high model-mid model-low; do
  port="${PORTS[$pod]}"
  kubectl exec -n "${NS}" "${pod}" -- python3 -c "
import urllib.request,json
r=urllib.request.urlopen('http://localhost:${port}/metrics')
d=json.loads(r.read())
g=d['gpu']
print('%-12s  ok=%4d  ttft=%6.1fms  rps=%6.1f  gpu=%4d/%4dMB' % ('${pod}', d['requests_ok'], d['ttft_avg_ms'], d['throughput_rps'], g['memory_used_mb'], g['memory_total_mb']))
" 2>/dev/null
done

echo ""
echo "=== Load test complete ==="
