#!/usr/bin/env bash
# Extended GPU sharding tests: solo baseline, concurrent load, interference
# Usage: ./06-extended-test.sh {solo|concurrent|interference|all} [concurrency] [requests]
set -euo pipefail

NS="ai-inference-lab"
TEST="${1:-all}"
CONCURRENCY="${2:-8}"
REQUESTS="${3:-80}"
RUNNER_POD="model-high"

HIGH_URL="http://model-high:8001"
MID_URL="http://model-mid:8002"
LOW_URL="http://model-low:8003"

echo "=== Extended GPU Sharding Tests ==="
echo "Test:    ${TEST}"
echo "Config:  concurrency=${CONCURRENCY}, requests=${REQUESTS}"
echo "Runner:  ${RUNNER_POD}"
echo ""

# Copy test script to runner pod
echo "Copying extended_test.py to ${RUNNER_POD}..."
kubectl cp extended_test.py "${NS}/${RUNNER_POD}:/extended_test.py" 2>/dev/null || true

# Run test inside the pod (uses in-cluster service DNS)
kubectl exec -n "${NS}" "${RUNNER_POD}" -- \
  python3 /extended_test.py \
    --test "${TEST}" \
    --concurrency "${CONCURRENCY}" \
    --requests "${REQUESTS}" \
    --high-url "${HIGH_URL}" \
    --mid-url  "${MID_URL}" \
    --low-url  "${LOW_URL}"

echo ""
echo "=== Extended tests complete ==="
