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
data=json.dumps({'messages':[{'role':'user','content':'Hi'}],'max_tokens':8}).encode()
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
  kubectl exec -n "${NS}" "${pod}" -- python -c "
import urllib.request,json
r=urllib.request.urlopen('http://localhost:${port}/metrics')
d=json.loads(r.read())
g=d.get('gpu',{})
ok=d.get('requests_ok',0); total=d.get('requests_total',0)
ttft=d.get('ttft_avg_ms',0); rps=d.get('throughput_rps',0)
um=g.get('memory_used_mb',0); tm=g.get('memory_total_mb',0)
print('${pod}  ok=%d/%d  ttft=%.1fms  rps=%.1f  gpu=%d/%dMB' % (ok,total,ttft,rps,um,tm))
" 2>/dev/null || true
done

echo ""
echo "=== Load test complete ==="
