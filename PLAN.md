# GPU 分片实验方案

## 目标

在单张物理 GPU 上部署 3 个推理 Pod，通过 HAMi-Core 实现 GPU 分片（cores + memory），对比不同资源配比下的性能差异，采集 GPU 监控数据。

## 拓扑

```
物理 GPU (GTX 1050 Ti, 4096MiB)
├── Pod-A: cores=40, memory=1600Mi  (高配) → 端口 8001
├── Pod-B: cores=35, memory=1200Mi  (中配) → 端口 8002
└── Pod-C: cores=25, memory=800Mi   (低配) → 端口 8003
总计: cores=100, memory=3600Mi ≤ GPU 4096Mi
```

## 实验环境

| 类别 | 关键项 | 规格 |
|------|--------|------|
| 硬件 | GPU / 显存 | GTX 1050 Ti / 4096 MiB GDDR5 |
| 硬件 | PCIe | 3.0 x16 |
| 软件 | 编排平台 | Kubernetes v1.34.0 (kind) |
| 软件 | 容器运行时 | Docker + nvidia-container-toolkit 1.13+ |
| 软件 | Python | 3.11 |
| 驱动 | GPU 驱动 | NVIDIA 550.163.01 |
| 驱动 | HAMi-DRA | projecthami/k8s-dra-driver:v0.1.0 |
| 镜像 | 推理服务 | ai-inference-lab:latest (125 MB) |

详见 [README.md](README.md) 环境要求节和 [EXPERIMENT-REPORT.md](EXPERIMENT-REPORT.md) 1.3 节。

## 技术方案

- **推理镜像**: python:3.11-slim (124MB) + libcudart.so.12 (从 nvidia/cuda 提取)
- **GPU 调用**: Python ctypes → CUDA Runtime API，零 pip 安装、零模型下载
- **API**: /health, /metrics, /v1/chat/completions
- **负载测试**: Python ThreadPoolExecutor 并发请求
- **扩展测试**: Solo 基线 + 并发高负载 + 干扰测试，量化共享开销和性能隔离效果
- **监控**: /metrics 端点返回 GPU 显存 + 请求统计

## 文件结构

```
ai-inference-lab/
├── Makefile              # 流程封装
├── Dockerfile            # 推理镜像
├── server.py             # GPU 推理服务
├── load_test.py          # 基础并发负载生成器
├── extended_test.py      # 扩展测试脚本 (solo/并发/干扰)
├── kind-config.yaml      # kind 集群配置
├── 00-cleanup.sh         # 全量清理
├── 01-infra.sh           # 基础设施
├── 02-deploy.sh          # 部署分片 Pod
├── 03-verify.sh          # 分片验证
├── 04-load-test.sh       # 基础负载对比
├── 05-monitor.sh         # GPU 监控
├── 06-extended-test.sh   # 扩展测试执行
├── PLAN.md               # 本文档
├── EXPERIMENT-REPORT.md  # 实验报告
├── PROBLEM-REPORT.md     # 已知问题及修复
└── README.md             # 项目入口
```

## 操作

```bash
cd /home/l/dev/testclaude/ai-inference-lab

# 一键全流程
make all

# 分步执行
make clean           # 清理环境
make infra           # 集群 + 驱动 + 镜像构建
make deploy          # 部署 3 个分片 Pod
make verify          # 验证 GPU 分片
make load-test       # 基础并发负载对比
make monitor         # GPU 监控 30s

# 扩展测试
make test-solo       # Solo 基线
make test-concurrent # 并发高负载
make test-interference # 干扰测试
make test-extended   # 全部扩展测试

make status          # 查看当前状态
```

## 验收标准

| 检查项 | 要求 |
|--------|------|
| Pod 就绪 | 3/3 Running |
| HAMi 注入 | CUDA_DEVICE_SM_LIMIT 等于 ResourceClaim cores |
| 显存限制 | GPU 报告总量等于 ResourceClaim memory |
| 推理可用 | /health 返回 200 |
| 负载差异 | 高配吞吐量 > 中配 > 低配 |
| 扩展测试 | Solo/并发/干扰三项测试量化性能隔离 |
| 监控数据 | /metrics 返回 GPU 显存 + 请求统计 |

## 扩展测试设计

三项扩展测试逐一验证 GPU 分片的不同维度：

1. **Solo 基线** — 验证 cores 限制的本质（软限制 vs 硬上限）
2. **并发高负载** — 量化多 Pod 共享 GPU 的吞吐损失
3. **干扰测试** — 检测算力隔离对空闲邻居的保护程度

详见 [EXPERIMENT-REPORT.md](EXPERIMENT-REPORT.md) 第 6 节。
