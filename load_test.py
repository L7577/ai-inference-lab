"""Concurrent load tester for inference endpoints."""
import json, sys, time, urllib.request, concurrent.futures, argparse


def send_one(url, prompt, max_tokens):
    t0 = time.time()
    try:
        data = json.dumps({
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
        }).encode() if "/chat" in url else json.dumps({
            "mb": max_tokens, "iterations": 3,
        }).encode()
        req = urllib.request.Request(url, data=data, headers={
            "Content-Type": "application/json",
        })
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.loads(resp.read())
        ttft_ms = body.get("ttft_ms", (time.time() - t0) * 1000)
        return {"ok": True, "ttft_ms": ttft_ms}
    except Exception as e:
        return {"ok": False, "error": str(e), "ttft_ms": (time.time() - t0) * 1000}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--url", required=True)
    p.add_argument("--concurrency", type=int, default=3)
    p.add_argument("--requests", type=int, default=30)
    p.add_argument("--prompt", default="Explain GPU computing in one sentence.")
    p.add_argument("--max-tokens", type=int, default=32)
    args = p.parse_args()

    print(f"Target: {args.url}")
    print(f"Config: {args.requests} requests, concurrency={args.concurrency}")
    print()

    t0 = time.time()
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as ex:
        futures = [
            ex.submit(send_one, args.url, args.prompt, args.max_tokens)
            for _ in range(args.requests)
        ]
        for f in concurrent.futures.as_completed(futures):
            results.append(f.result())

    elapsed = time.time() - t0
    ok_results = [r for r in results if r["ok"]]
    ttft_list = sorted([r["ttft_ms"] for r in ok_results])
    err_count = len(results) - len(ok_results)

    print(f"Duration:    {elapsed:.1f}s")
    print(f"Completed:   {len(ok_results)}/{len(results)} (errors: {err_count})")
    print(f"Throughput:  {len(ok_results)/elapsed:.1f} req/s")
    if ttft_list:
        n = len(ttft_list)
        print(f"TTFT avg:    {sum(ttft_list)/n:.0f} ms")
        print(f"TTFT P50:    {ttft_list[n//2]:.0f} ms")
        print(f"TTFT P99:    {ttft_list[int(n*0.99)]:.0f} ms")
        print(f"TTFT min:    {ttft_list[0]:.0f} ms")
        print(f"TTFT max:    {ttft_list[-1]:.0f} ms")


if __name__ == "__main__":
    main()
