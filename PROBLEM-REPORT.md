# 问题报告: `make all` 重复执行失败

## 症状

重启宿主机之前，多次执行 `make all` 会失败。重启宿主机后，`make all` 可以多次执行，且结果正常。

## 根因: NVIDIA GPU 驱动状态泄漏

**主要原因是 NVIDIA GPU 内核驱动在反复创建/销毁容器的过程中积累了脏状态。**

### 发生机制

每次 `make all` 会执行:

```
make clean  →  kind delete cluster（强制删除 Docker 容器）
make infra  →  kind create cluster → DRA 驱动发现 GPU → 发布 ResourceSlice
make deploy →  3 个 GPU Pod 在同一张物理 GPU 上启动
```

kind worker 节点容器以访问宿主机 GPU 的方式运行。当 `kind delete cluster` 被调用时，它强制删除 Docker 容器，但 NVIDIA 内核模块（nvidia.ko、nvidia-uvm.ko）不一定能感知到 GPU 上下文应当被销毁。关键故障点:

| 资源 | 容器强杀的影响 |
|------|--------------|
| CUDA 主上下文 | 若未显式销毁，可能在 NVIDIA 驱动中残留 |
| GPU 设备文件 (`/dev/nvidia*`) | 已死进程持有的内核引用未被清理 |
| nvidia-uvm（统一内存） | 容器删除后内存映射仍然存在 |
| GPU 显存分配 | 进程退出理论上应释放，但强杀绕过 CUDA 清理路径 |

### 为什么重启能修复

重启会从零重新加载 NVIDIA 内核模块:
- 所有 GPU 显存被物理重置
- 所有 CUDA 上下文被销毁
- `/dev/nvidia0`、`/dev/nvidiactl`、`/dev/nvidia-uvm` 被重新创建
- nvidia-persistenced 以干净状态重新启动

## 代码层面的促成因素

### 问题 1: 资源清理顺序错误（`00-cleanup.sh:10-16`）

```bash
# 错误: ResourceClaim 先于持有它的 Pod 被删除
kubectl delete resourceclaims --all -n "${ns}" --ignore-not-found --wait=false
kubectl delete pods --all -n "${ns}" --ignore-not-found --wait=false
kubectl delete namespace "${ns}" --ignore-not-found --wait=false
```

**问题**: ResourceClaim 在 Pod 仍然持有它时被删除。Kubernetes 准入控制器会阻止删除正在使用中的 Claim。加上 `--wait=false`，命令立即返回而不确认实际是否删除成功。正确顺序应为: Pod → ResourceClaim → Namespace。

### 问题 2: Docker 镜像从不更新（`01-infra.sh:24-30`）

```bash
if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${INFER_IMAGE}$"; then
    echo "[OK] inference image already built: ${INFER_IMAGE}"
else
    docker build -t "${INFER_IMAGE}" "${DIR}"
fi
```

**问题**: 仅检查 `ai-inference-lab:latest` 标签是否存在。如果 `server.py` 或 `Dockerfile` 被修改，后续 `make all` 也不会触发 `docker build`，因为标签始终存在。Pod 部署的是旧代码。Dockerfile 中的 `COPY server.py` 步骤被完全绕过。例如，当前 `server.py`（05/18 12:17）引入的修复可能永远不会进入镜像。

### 问题 3: 缺少 GPU 健康检查门禁（`01-infra.sh`）

DRA 驱动启动并发布 ResourceSlice 后，未验证 GPU 是否真正可用。脚本等待 ResourceSlice 出现（第 56-62 行），但不检查 GPU 健康状态。如果 GPU 因上次运行而处于降级状态，新集群会静默继承此状态。

## 重启前多次运行为何失败

多次 `make all` 循环的故障累积机制:

```
第1次: GPU 干净 → kind 集群（GPU 正常）→ Pod 运行 → kind delete（GPU 上下文泄漏）
第2次: GPU 脏 → kind 集群（GPU 部分可用）→ DRA 驱动报告缩水的 ResourceSlice
       → ResourceClaim 超出可用容量 → deploy 失败
第N次: GPU 积累更多脏状态 → 故障更频繁/稳定
```

### 具体故障模式:

1. **ResourceSlice 显示降级容量**: DRA 驱动发现 GPU 并报告可用核心数/显存。如果 GPU 显存因泄漏的分配而碎片化，报告的容量可能小于 4096MB，导致 ResourceClaim（合计 3600MB）分配失败。

2. **GPU 计算失败**: 即使 Pod 已启动，如果 CUDA 上下文已损坏，`server.py:36` 中的 `cudaMalloc` 或 `cudaMemGetInfo` 调用可能返回错误，导致 `/health` 和 `/v1/chat/completions` 返回错误。

3. **CDI spec 冲突**: kind 配置（`kind-config.yaml:14`）将 `/dev/null` 挂载到 `/var/run/nvidia-container-devices/cdi/runtime.nvidia.com/gpu/all` 以抑制 CDI 自动生成。但如果宿主机的 `nvidia-container-toolkit` 保留了上次容器运行的过期 CDI spec，Docker 运行时可能在创建新的 GPU 访问容器时失败。

## 修复记录 (2026-05-18)

### 已修复

1. **`00-cleanup.sh`** — 清理顺序已修正: Pod → ResourceClaim → Namespace，并添加 `--wait=true --timeout=30s` 确保资源被实际释放后再继续。

2. **`01-infra.sh`** — 移除了"镜像已存在则跳过"的检查，改为始终执行 `docker build`，确保最新源码始终被打入推理镜像。

3. **`01-infra.sh`** — 新增 GPU 健康检查门禁：创建 kind 集群前通过 `nvidia-smi` 查询宿主机 GPU 空闲显存，低于 2048 MiB 时输出警告。

### 说明

修复 1 和 2 解决了代码层面的逻辑缺陷。修复 3 提供 GPU 状态的早期预警，但不能替代 GPU 驱动的状态泄漏问题——该问题的根治需要 NVIDIA 驱动层面的改进。重启宿主机仍然是最可靠的 GPU 状态重置手段。

### 代码修复（立即 — 防止用户误操作）

1. **`00-cleanup.sh`**: 重新排序为: 删除 Pod → 等待 → 删除 ResourceClaim → 删除 Namespace
2. **`01-infra.sh`**: 当源文件比镜像新时，添加 `--pull` 或强制重建
3. **`01-infra.sh`**: 驱动安装后增加 GPU 健康检查

### GPU 状态问题的缓解措施

1. 新增 `make reset-gpu` 目标，执行 `nvidia-smi --gpu-reset`（需要关闭计算独占模式）
2. 文档记录: `sudo rmmod nvidia_uvm && sudo modprobe nvidia_uvm` 可在不重启的情况下重置 GPU
3. 在 `00-cleanup.sh` 中增加清理后的 GPU 状态检查

### 长期方案

1. 在创建 kind 集群前使用 `nvidia-smi` 验证 GPU 可用显存
2. 在 `01-infra.sh` 中，创建 kind 集群后 exec 进入 worker 节点验证 `/dev/nvidia0` 是否可访问
3. 考虑为 kind create 添加 `--preserve-failures`，并检查 worker 容器内的 GPU 状态

---

*报告生成于 2026-05-18，基于 `ai-inference-lab/` 静态代码分析*
