.PHONY: all clean infra deploy verify load-test monitor \
        test-solo test-concurrent test-interference test-extended \
        status help

# ============================================
# Full pipeline
# ============================================
all: clean infra deploy verify load-test monitor
	@echo; echo "=== Full pipeline complete ==="

# ============================================
# Lifecycle
# ============================================
clean:
	./00-cleanup.sh

infra:
	./01-infra.sh

deploy:
	./02-deploy.sh

verify:
	./03-verify.sh

# ============================================
# Tests
# ============================================
load-test:
	./04-load-test.sh

DURATION ?= 30
monitor:
	./05-monitor.sh $(DURATION)

CONCURRENCY ?= 8
REQUESTS    ?= 80

test-solo:
	./06-extended-test.sh solo $(CONCURRENCY) $(REQUESTS)

test-concurrent:
	./06-extended-test.sh concurrent $(CONCURRENCY) $(REQUESTS)

test-interference:
	./06-extended-test.sh interference $(CONCURRENCY) $(REQUESTS)

test-extended:
	./06-extended-test.sh all $(CONCURRENCY) $(REQUESTS)

# ============================================
# Status
# ============================================
status:
	@echo "=== Clusters ==="
	@kind get clusters 2>/dev/null || true
	@echo ""
	@echo "=== Nodes ==="
	@kubectl get nodes -o wide 2>/dev/null || true
	@echo ""
	@echo "=== Driver ==="
	@kubectl -n hami-dra-driver get pods -o wide 2>/dev/null || true
	@echo ""
	@echo "=== ResourceSlice ==="
	@kubectl get resourceslices -o wide 2>/dev/null || true
	@echo ""
	@echo "=== Claims ==="
	@kubectl -n ai-inference-lab get resourceclaim -o wide 2>/dev/null || true
	@echo ""
	@echo "=== Pods ==="
	@kubectl -n ai-inference-lab get pods -o wide 2>/dev/null || true

# ============================================
# Help
# ============================================
help:
	@echo "AI Inference Lab — HAMi-DRA GPU Sharding Experiment"
	@echo ""
	@echo "  Setup & Lifecycle:"
	@echo "    make infra          Build kind cluster + DRA driver + inference image"
	@echo "    make deploy         Deploy 3 GPU-sharded Pods (high/mid/low)"
	@echo "    make verify         Verify GPU sharding is working"
	@echo "    make clean          Remove everything"
	@echo "    make status         Show cluster, pods, and claims state"
	@echo ""
	@echo "  Tests:"
	@echo "    make load-test      Basic load test (30 req, conc=3 per pod)"
	@echo "    make monitor        GPU monitoring (default 30s, DURATION=60 to override)"
	@echo ""
	@echo "  Extended tests:"
	@echo "    make test-solo          Solo baseline (each pod alone, full load)"
	@echo "    make test-concurrent    Concurrent load (all 3 pods simultaneously)"
	@echo "    make test-interference  Interference (max Pod A, measure B/C latency)"
	@echo "    make test-extended      All extended tests"
	@echo ""
	@echo "  Pipeline:"
	@echo "    make all            Clean + infra + deploy + verify + load-test + monitor"
	@echo ""
	@echo "  Options:"
	@echo "    DURATION=60 make monitor       Custom monitoring duration"
	@echo "    CONCURRENCY=16 make test-solo  Custom concurrency for extended tests"
	@echo "    REQUESTS=200 make test-solo    Custom request count"
