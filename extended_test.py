"""Extended GPU sharding tests — solo baseline, concurrent, interference."""
import json, time, argparse, concurrent.futures, urllib.request


def send_one(url, max_tokens):
    t0 = time.time()
    try:
        data = json.dumps({
            "messages": [{"role": "user", "content": "benchmark"}],
            "max_tokens": max_tokens,
        }).encode()
        req = urllib.request.Request(url + "/v1/chat/completions", data=data,
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.loads(resp.read())
        return True, body.get("ttft_ms", (time.time() - t0) * 1000)
    except Exception:
        return False, (time.time() - t0) * 1000


def warmup(url, n=5):
    for _ in range(n):
        send_one(url, 8)


def run_load(url, concurrency, requests, max_tokens=32):
    results = []
    t0 = time.time()
    lock = __import__('threading').Lock()

    def worker():
        while True:
            with lock:
                if len(results) >= requests:
                    return
            ok, ttft = send_one(url, max_tokens)
            with lock:
                results.append({"ok": ok, "ttft_ms": ttft})

    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as ex:
        futures = [ex.submit(worker) for _ in range(concurrency)]
        concurrent.futures.wait(futures)

    elapsed = time.time() - t0
    ok_list = [r for r in results if r["ok"]]
    ttft_list = sorted([r["ttft_ms"] for r in ok_list])
    n = len(ttft_list)
    return {
        "ok": len(ok_list), "errors": len(results) - len(ok_list),
        "throughput_rps": round(len(ok_list) / elapsed, 1) if elapsed > 0 else 0,
        "p50_ms": round(ttft_list[n // 2], 1) if n else 0,
        "p99_ms": round(ttft_list[int(n * 0.99)], 1) if n else 0,
        "avg_ms": round(sum(ttft_list) / n, 1) if n else 0,
        "elapsed_s": round(elapsed, 1),
    }


def get_metrics(url):
    try:
        with urllib.request.urlopen(url + "/metrics", timeout=5) as resp:
            return json.loads(resp.read())
    except Exception:
        return {}


def test_solo_baseline(pods, concurrency, requests):
    print("=" * 60)
    print("TEST A: Solo Baseline (each pod alone at full load)")
    print("=" * 60)
    results = {}
    for name, cfg in pods.items():
        print(f"\n--- {name} (cores={cfg['cores']}, mem={cfg['memory']}Mi) ---")
        warmup(cfg["url"])
        stats = run_load(cfg["url"], concurrency, requests)
        metrics = get_metrics(cfg["url"])
        results[name] = {**stats, "gpu": metrics.get("gpu", {})}
        print(f"  Throughput: {stats['throughput_rps']} req/s  "
              f"P50={stats['p50_ms']}ms  P99={stats['p99_ms']}ms  "
              f"ok={stats['ok']}/{stats['ok']+stats['errors']}")
    return results


def test_concurrent(pods, concurrency, requests):
    print("\n" + "=" * 60)
    print("TEST B: Concurrent High-Load (all pods simultaneously)")
    print("=" * 60)
    results = {}
    t0 = time.time()

    def run_pod(name, cfg):
        warmup(cfg["url"])
        stats = run_load(cfg["url"], concurrency, requests)
        metrics = get_metrics(cfg["url"])
        return name, {**stats, "gpu": metrics.get("gpu", {})}

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(pods)) as ex:
        futures = [ex.submit(run_pod, name, cfg) for name, cfg in pods.items()]
        for f in concurrent.futures.as_completed(futures):
            name, stats = f.result()
            results[name] = stats

    total_elapsed = time.time() - t0
    total_throughput = sum(r["throughput_rps"] for r in results.values())
    print(f"\n  Total elapsed: {total_elapsed:.1f}s")
    print(f"  Combined throughput: {total_throughput:.1f} req/s")
    for name, stats in results.items():
        print(f"  {name}: {stats['throughput_rps']} req/s  "
              f"P50={stats['p50_ms']}ms  P99={stats['p99_ms']}ms")
    return results


def test_interference(pods, attacker_concurrency, requests):
    print("\n" + "=" * 60)
    print("TEST C: Interference (max Pod A, measure B/C idle latency)")
    print("=" * 60)

    pod_names = list(pods.keys())
    attacker = pod_names[0]
    victims = pod_names[1:]

    print(f"  Attacker: {attacker} (full load, concurrency={attacker_concurrency})")
    print(f"  Victims:  {', '.join(victims)} (measuring idle request latency)")

    # Phase 1: baseline latency
    print("\n  --- Phase 1: Baseline latency (no load) ---")
    baseline = {}
    for name in victims:
        warmup(pods[name]["url"])
        ttft_list = []
        for _ in range(10):
            ok, ttft = send_one(pods[name]["url"], 32)
            if ok:
                ttft_list.append(ttft)
        n = len(ttft_list)
        baseline[name] = {
            "avg_ms": round(sum(ttft_list) / n, 1) if n else 0,
            "p50_ms": sorted(ttft_list)[n // 2] if n else 0,
        }
        print(f"  {name}: avg={baseline[name]['avg_ms']}ms  P50={baseline[name]['p50_ms']}ms")

    # Phase 2: attacker running
    print(f"\n  --- Phase 2: Interference (attacker running) ---")
    attacker_url = pods[attacker]["url"]
    warmup(attacker_url)

    stop_flag = {"value": False}

    def attacker_loop():
        while not stop_flag["value"]:
            send_one(attacker_url, 32)

    with concurrent.futures.ThreadPoolExecutor(max_workers=attacker_concurrency) as ex:
        futures = [ex.submit(attacker_loop) for _ in range(attacker_concurrency)]
        time.sleep(2)

        for name in victims:
            ttft_list = []
            for _ in range(10):
                ok, ttft = send_one(pods[name]["url"], 32)
                if ok:
                    ttft_list.append(ttft)
            n = len(ttft_list)
            s = sorted(ttft_list)
            delta = round(s[n // 2] - baseline[name]["p50_ms"], 1) if n else 0
            print(f"  {name}: avg={round(sum(ttft_list)/n,1)}ms  "
                  f"P50={s[n//2]}ms  (delta: +{delta}ms)")

        stop_flag["value"] = True
        concurrent.futures.wait(futures)


def main():
    p = argparse.ArgumentParser(description="Extended GPU sharding tests")
    p.add_argument("--pods", default="all", help="Comma-separated pod names or 'all'")
    p.add_argument("--concurrency", type=int, default=8)
    p.add_argument("--requests", type=int, default=80)
    p.add_argument("--test", default="all",
                   choices=["solo", "concurrent", "interference", "all"])
    p.add_argument("--high-url", default="http://localhost:8001")
    p.add_argument("--mid-url",  default="http://localhost:8002")
    p.add_argument("--low-url",  default="http://localhost:8003")
    args = p.parse_args()

    pods = {
        "model-high": {"url": args.high_url, "cores": 40, "memory": 1600},
        "model-mid":  {"url": args.mid_url,  "cores": 35, "memory": 1200},
        "model-low":  {"url": args.low_url,  "cores": 25, "memory": 800},
    }

    if args.pods != "all":
        names = set(args.pods.split(","))
        pods = {k: v for k, v in pods.items() if k in names}

    print("Extended GPU Sharding Tests")
    print(f"Pods: {list(pods.keys())}")
    print(f"Config: concurrency={args.concurrency}, requests={args.requests}")
    print()

    results = {}

    if args.test in ("solo", "all"):
        results["solo"] = test_solo_baseline(pods, args.concurrency, args.requests)

    if args.test in ("concurrent", "all"):
        results["concurrent"] = test_concurrent(pods, args.concurrency, args.requests)

    if args.test in ("interference", "all"):
        test_interference(pods, args.concurrency, args.requests)

    # Sharing overhead summary
    if "solo" in results and "concurrent" in results:
        print("\n" + "=" * 60)
        print("SHARING OVERHEAD SUMMARY")
        print("=" * 60)
        solo_sum = sum(r["throughput_rps"] for r in results["solo"].values())
        conc_sum = sum(r["throughput_rps"] for r in results["concurrent"].values())
        overhead = (solo_sum - conc_sum) / solo_sum * 100 if solo_sum > 0 else 0
        print(f"  Solo throughput sum:     {solo_sum:.1f} req/s")
        print(f"  Concurrent throughput:   {conc_sum:.1f} req/s")
        print(f"  Sharing overhead:        {overhead:.1f}%")
        print()
        for name in pods:
            s = results["solo"][name]["throughput_rps"]
            c = results["concurrent"][name]["throughput_rps"]
            drop = (s - c) / s * 100 if s > 0 else 0
            print(f"  {name}: solo={s:.1f} → shared={c:.1f} req/s  (-{drop:.1f}%)")


if __name__ == "__main__":
    main()
