#!/usr/bin/env bash
set -euo pipefail
NS="ai-inference-lab"
DURATION=${1:-30}
INTERVAL=5

echo "=== Phase 5: GPU Monitor (${DURATION}s, every ${INTERVAL}s) ==="

declare -A PORTS
PORTS[model-high]=8001
PORTS[model-mid]=8002
PORTS[model-low]=8003

start=$(date +%s)
while true; do
  elapsed=$(($(date +%s) - start))
  [ "$elapsed" -ge "$DURATION" ] && break

  ts=$(date +%H:%M:%S)
  echo "--- ${ts} (t+${elapsed}s) ---"
  printf "  %-12s %5s %8s %7s %9s %9s\n" POD OK AVG_TTFT RPS GPU_USED GPU_TOTAL

  for pod in model-high model-mid model-low; do
    port="${PORTS[$pod]}"
    kubectl exec -n "${NS}" "${pod}" -- python -c "
import urllib.request,json
try:
    r=urllib.request.urlopen('http://localhost:${port}/metrics')
    d=json.loads(r.read())
    g=d.get('gpu',{})
    ok=d.get('requests_ok',0); ttft=d.get('ttft_avg_ms',0)
    rps=d.get('throughput_rps',0); um=g.get('memory_used_mb',0)
    tm=g.get('memory_total_mb',0)
    print('  %-12s  ok=%4d  ttft=%6.1fms  rps=%6.1f  gpu=%4d/%4dMB' % ('${pod}',ok,ttft,rps,um,tm))
except Exception as e:
    print('  %-12s  error: %s' % ('${pod}',str(e)))
" 2>/dev/null || true
  done
  sleep "${INTERVAL}"
done

echo ""
echo "=== Monitor complete ==="
