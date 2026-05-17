.PHONY: all clean infra deploy verify load-test monitor status

all: clean infra deploy verify load-test monitor

clean:
	./00-cleanup.sh

infra:
	./01-infra.sh

deploy:
	./02-deploy.sh

verify:
	./03-verify.sh

load-test:
	./04-load-test.sh

DURATION ?= 30
monitor:
	./05-monitor.sh $(DURATION)

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
