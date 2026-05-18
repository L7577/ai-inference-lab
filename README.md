# AI Inference Lab — HAMi-DRA GPU 分片实验

基于 [HAMi-DRA Driver](https://github.com/Project-HAMi/k8s-dra-driver) 的 GPU 分片多模型推理实验。

## 快速开始

```bash
cd /home/l/dev/testclaude/ai-inference-lab
make all
```

## 操作指南

| 命令 | 说明 |
|------|------|
| `make all` | 一键全流程 |
| `make clean` | 清理集群及所有资源 |
| `make infra` | 创建 kind 集群 + 安装 DRA 驱动 + 构建推理镜像 |
| `make deploy` | 部署 3 个分片推理 Pod (高/中/低配) |
| `make verify` | 验证 HAMi-Core 注入 + GPU 状态 |
| `make load-test` | 并发负载对比 (30req × 3 Pod) |
| `make monitor` | GPU 监控 30s (`DURATION=60 make monitor`) |
| `make status` | 查看集群/Pod/Claim 状态 |

## 前置条件

- NVIDIA GPU + 驱动 ≥ 440
- nvidia-container-toolkit（`accept-nvidia-visible-devices-as-volume-mounts=true`）
- docker、kind、kubectl
- driver 镜像：`projecthami/k8s-dra-driver:v0.1.0`
  ```bash
  cd /home/l/dev/testclaude/k8s-dra-driver && make image
  ```

## 实验拓扑

```
物理 GPU (4GB) ──┬── model-high  (40 cores / 1600Mi) → :8001
                 ├── model-mid   (35 cores / 1200Mi) → :8002
                 └── model-low   (25 cores /  800Mi) → :8003
```

## 文件说明

| 文件 | 用途 |
|------|------|
| `Makefile` | 流程封装 |
| `Dockerfile` | 推理镜像 (python + cuda runtime, 125MB) |
| `server.py` | GPU 推理服务 (/health /metrics /v1/chat) |
| `load_test.py` | 并发负载生成器 |
| `kind-config.yaml` | kind 集群配置 |
| `00-cleanup.sh` ~ `05-monitor.sh` | 分步脚本 |
| `PLAN.md` | 方案设计 |
| `EXPERIMENT-REPORT.md` | 完整实验报告 (含步骤和结果) |

## 实验结果

| Pod | cores | memory | GPU 报告显存 | 吞吐量 | P50 延迟 |
|-----|-------|--------|-------------|--------|----------|
| model-high | 40 | 1600Mi | 1600MB | 23.1 rps | 42ms |
| model-mid | 35 | 1200Mi | 1200MB | 18.9 rps | 52ms |
| model-low | 25 | 800Mi | 800MB | 17.8 rps | 56ms |

详见 [EXPERIMENT-REPORT.md](EXPERIMENT-REPORT.md)
