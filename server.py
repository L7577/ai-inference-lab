"""GPU inference server — uses CUDA runtime via ctypes (no torch needed)."""
import json, os, time, ctypes, threading
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = int(os.getenv("PORT", "8000"))
MODEL = os.getenv("MODEL_NAME", "gpu-worker")
MAX_TOKENS = int(os.getenv("MAX_TOKENS", "32"))

# Load CUDA runtime
_cuda = ctypes.CDLL("libcudart.so.12")

def _check(ret, msg="CUDA error"):
    if ret != 0:
        raise RuntimeError(f"{msg}: {ret}")

def gpu_info():
    free = ctypes.c_size_t()
    total = ctypes.c_size_t()
    ret = _cuda.cudaMemGetInfo(ctypes.byref(free), ctypes.byref(total))
    if ret != 0:
        return {"error": f"cudaMemGetInfo failed: {ret}"}
    used = total.value - free.value
    return {
        "device": "GPU",
        "memory_total_mb": total.value // (1024 * 1024),
        "memory_used_mb": used // (1024 * 1024),
        "memory_free_mb": free.value // (1024 * 1024),
    }

def gpu_alloc_compute(mb, iterations):
    """Allocate GPU memory and run memcpy ops, measure bandwidth."""
    size = mb * 1024 * 1024
    d_ptr = ctypes.c_void_p()
    ret = _cuda.cudaMalloc(ctypes.byref(d_ptr), size)
    if ret != 0:
        return {"error": f"cudaMalloc({mb}MB) failed: {ret}"}

    h_data = (ctypes.c_ubyte * size)()
    t0 = time.time()
    for _ in range(iterations):
        _cuda.cudaMemcpy(d_ptr, h_data, size, 1)  # host→device
        _cuda.cudaMemcpy(h_data, d_ptr, size, 2)  # device→host
    _cuda.cudaDeviceSynchronize()
    elapsed = time.time() - t0
    _cuda.cudaFree(d_ptr)
    bw = (2 * size * iterations) / elapsed / (1024 * 1024)
    return {"ok": True, "alloc_mb": mb, "iterations": iterations,
            "elapsed_ms": round(elapsed * 1000, 1), "bandwidth_mbps": round(bw, 1)}

# Stats
_start = time.time()
_stats = {"req_total": 0, "req_ok": 0, "req_err": 0, "ttft_ms": []}
_lock = threading.Lock()

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass

    def _json(self, data, status=200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._json({"status": "ok", "model": MODEL, "gpu": gpu_info()})
        elif self.path == "/metrics":
            with _lock:
                ttft = list(_stats["ttft_ms"])
                total = _stats["req_total"]
                ok = _stats["req_ok"]
                err = _stats["req_err"]
            recent = ttft[-100:] or [0]
            sorted_ttft = sorted(ttft) if ttft else [0]
            uptime = time.time() - _start
            self._json({
                "uptime_sec": int(uptime),
                "requests_total": total, "requests_ok": ok, "requests_err": err,
                "ttft_avg_ms": round(sum(recent) / len(recent), 1),
                "ttft_p50_ms": sorted_ttft[len(sorted_ttft) // 2],
                "ttft_p99_ms": sorted_ttft[int(len(sorted_ttft) * 0.99)],
                "throughput_rps": round(total / uptime, 2) if uptime > 0 else 0,
                "gpu": gpu_info(),
            })
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self):
        global _stats
        if self.path == "/v1/compute":
            try:
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length))
                mb = min(int(body.get("mb", 100)), 2048)
                iters = min(int(body.get("iterations", 10)), 100)
            except Exception:
                self._json({"error": "bad request"}, 400)
                return

            with _lock:
                _stats["req_total"] += 1
            t0 = time.time()
            try:
                result = gpu_alloc_compute(mb, iters)
                result["ttft_ms"] = round((time.time() - t0) * 1000, 1)
                with _lock:
                    _stats["req_ok"] += 1
                    _stats["ttft_ms"].append(result["ttft_ms"])
                self._json(result)
            except Exception as e:
                with _lock:
                    _stats["req_err"] += 1
                self._json({"error": str(e)}, 500)
        elif self.path == "/v1/chat/completions":
            # Compat endpoint: treat it as compute
            try:
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length))
                prompt = body.get("messages", [{}])[-1].get("content", "Hello")
                mt = min(int(body.get("max_tokens", 32)), 128)
            except Exception:
                self._json({"error": "bad request"}, 400)
                return

            with _lock:
                _stats["req_total"] += 1
            t0 = time.time()
            try:
                # Simulate "inference" with GPU compute proportional to max_tokens
                result = gpu_alloc_compute(mb=mt, iterations=3)
                elapsed_ms = (time.time() - t0) * 1000
                with _lock:
                    _stats["req_ok"] += 1
                    _stats["ttft_ms"].append(elapsed_ms)
                self._json({
                    "choices": [{"message": {"role": "assistant",
                        "content": f"Computed {mt}MB GPU workload in {elapsed_ms:.1f}ms"}}],
                    "usage": {"completion_tokens": mt},
                    "ttft_ms": round(elapsed_ms, 1),
                })
            except Exception as e:
                with _lock:
                    _stats["req_err"] += 1
                self._json({"error": str(e)}, 500)
        else:
            self._json({"error": "not found"}, 404)

if __name__ == "__main__":
    print(f"GPU worker starting on port {PORT}...")
    info = gpu_info()
    print(f"GPU info: {info}")
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
