# AI Inference Lab — HAMi-DRA GPU 分片实验

基于 [HAMi-DRA Driver](https://github.com/Project-HAMi/k8s-dra-driver) 的 GPU 分片多模型推理实验。

## 快速开始

```bash
cd ai-inference-lab
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
| `make test-extended` | 扩展测试 (solo/并发/干扰) |
| `make test-solo` | Solo 基线 (单 Pod 满负载) |
| `make test-concurrent` | 并发高负载 (三 Pod 同时) |
| `make test-interference` | 干扰测试 (邻居噪声影响) |
| `make status` | 查看集群/Pod/Claim 状态 |

## 环境要求

### 硬件

| 项目 | 规格 |
|------|------|
| GPU | NVIDIA GeForce GTX 1050 Ti（或同代次 NVIDIA GPU） |
| 物理显存 | ≥ 4 GiB（本实验 4096 MiB） |
| GPU 驱动 | ≥ 440（本实验 550.163.01） |
| PCIe | 3.0 x16 |
| 主机内存 | ≥ 8 GiB |
| 主机存储 | ≥ 20 GiB 可用 |

### 软件

| 工具 | 最低版本 | 用途 |
|------|---------|------|
| Docker | 20.10+ | 构建推理镜像；kind 节点运行 |
| kind | 0.20+ | 创建本地 Kubernetes 集群 |
| kubectl | 1.28+ | 集群管理、kubectl cp/exec |
| Python | 3.11+ | 负载测试脚本（主机侧） |
| nvidia-container-toolkit | 1.13+ | GPU 容器运行时；需配置 `accept-nvidia-visible-devices-as-volume-mounts=true` |
| nvidia-smi | — | 宿主机 GPU 状态检查（`01-infra.sh` 使用） |
| bash | 4.0+ | 所有脚本运行环境 |

### 镜像

| 镜像 | 来源 | 大小 | 用途 |
|------|------|------|------|
| `kindest/node:v1.34.0` | registry.k8s.io | ~1.2 GB | kind 集群节点 |
| `python:3.11-slim` | Docker Hub | 124 MB | 推理服务基础镜像 |
| `nvidia/cuda:12.2.2-base-ubuntu22.04` | Docker Hub | — | 提取 libcudart.so.12（COPY --from，不进入最终镜像） |
| `ai-inference-lab:latest` | 本地 `docker build` | 125 MB | 推理服务最终镜像 |
| `projecthami/k8s-dra-driver:v0.1.0` | 本地构建 | 103 MB | HAMi-DRA GPU 分片驱动 |

k8s-dra-driver 是独立 Git 仓库，需单独克隆并构建：

```bash
git clone https://github.com/Project-HAMi/k8s-dra-driver.git ../k8s-dra-driver
cd ../k8s-dra-driver && make image
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
| `load_test.py` | 基础并发负载生成器 |
| `extended_test.py` | 扩展测试脚本 (solo/并发/干扰) |
| `kind-config.yaml` | kind 集群配置 |
| `00-cleanup.sh` ~ `06-extended-test.sh` | 分步脚本 |
| `PLAN.md` | 方案设计 |
| `EXPERIMENT-REPORT.md` | 完整实验报告 (含步骤和结果) |
| `PROBLEM-REPORT.md` | 已知问题及修复记录 |

## 实验结果

| Pod | cores | memory | GPU 报告显存 | 吞吐量 | P50 延迟 |
|-----|-------|--------|-------------|--------|----------|
| model-high | 40 | 1600Mi | 1600MB | 23.1 rps | 42ms |
| model-mid | 35 | 1200Mi | 1200MB | 18.9 rps | 52ms |
| model-low | 25 | 800Mi | 800MB | 17.8 rps | 56ms |

## 扩展测试关键发现

| 结论 | 数据 | 实践意义 |
|------|------|----------|
| Cores 是软限制 | Solo 吞吐相同 (12.0 req/s)，延迟梯度 64→74ms | 独占 GPU 时可选最低 cores |
| 共享开销 35.8% | Solo 总吞吐 36.0 → 并发 23.1 req/s | 多 Pod 共享有显著性能代价 |
| 邻居噪声 +65~76% | 空闲 Pod P50 延迟从 51→90ms | 延迟敏感服务不应与高负载共卡 |

> GTX 1050 Ti (768 cores, 4GB) 建议 ≤ 2 个推理 Pod/卡。中高端 GPU 可支持更高密度。

详见 [EXPERIMENT-REPORT.md](EXPERIMENT-REPORT.md) 第 6 节和 [PROBLEM-REPORT.md](PROBLEM-REPORT.md)
