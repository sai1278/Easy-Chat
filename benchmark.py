#!/usr/bin/env python3
import argparse
import json
import math
import os
import sys
import time
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

def run_request(url, timeout=5.0):
    start = time.perf_counter()
    status_code = 0
    err = None
    bytes_read = 0
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'EasyChat-LoadTester/1.0'})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status_code = resp.getcode()
            content = resp.read()
            bytes_read = len(content)
    except urllib.error.HTTPError as e:
        status_code = e.code
        err = str(e)
    except Exception as e:
        status_code = 0
        err = str(e)
    end = time.perf_counter()
    latency_ms = (end - start) * 1000.0
    return latency_ms, status_code, bytes_read, err

def execute_stage(url, concurrency, duration_sec, warmup_sec):
    print(f"=== Starting Warm-Up: Concurrency={concurrency}, Warmup={warmup_sec}s ===", flush=True)
    warmup_end = time.time() + warmup_sec
    with ThreadPoolExecutor(max_workers=min(concurrency, 200)) as executor:
        while time.time() < warmup_end:
            futures = [executor.submit(run_request, url) for _ in range(concurrency)]
            for f in as_completed(futures):
                pass
    print("=== Warm-Up Complete. Resetting Measurements ===", flush=True)
    time.sleep(2)

    print(f"=== Starting Benchmark Stage: Concurrency={concurrency}, Duration={duration_sec}s ===", flush=True)
    results = []
    stage_start = time.perf_counter()
    stage_deadline = time.time() + duration_sec
    
    workers = min(concurrency, 300)
    with ThreadPoolExecutor(max_workers=workers) as executor:
        while time.time() < stage_deadline:
            batch = [executor.submit(run_request, url) for _ in range(concurrency)]
            for f in as_completed(batch):
                results.append(f.result())
            time.sleep(0.01)

    stage_end = time.perf_counter()
    total_duration = stage_end - stage_start

    if not results:
        return {"error": "No requests recorded"}

    latencies = [r[0] for r in results]
    status_codes = [r[1] for r in results]
    total_bytes = sum(r[2] for r in results)
    errors = [r for r in results if r[1] < 200 or r[1] >= 400]

    latencies.sort()
    n = len(latencies)

    def percentile(p):
        k = (n - 1) * (p / 100.0)
        f = math.floor(k)
        c = math.ceil(k)
        if f == c:
            return latencies[int(k)]
        d0 = latencies[int(f)] * (c - k)
        d1 = latencies[int(c)] * (k - f)
        return d0 + d1

    p50 = percentile(50)
    p90 = percentile(90)
    p95 = percentile(95)
    p99 = percentile(99)
    max_lat = latencies[-1]
    
    total_requests = len(results)
    successful_requests = total_requests - len(errors)
    failed_requests = len(errors)
    rps = total_requests / total_duration
    throughput_mbps = (total_bytes / (1024 * 1024)) / total_duration
    error_rate_pct = (failed_requests / total_requests) * 100.0
    success_rate_pct = (successful_requests / total_requests) * 100.0

    output = {
        "concurrency": concurrency,
        "total_requests": total_requests,
        "successful_requests": successful_requests,
        "failed_requests": failed_requests,
        "duration_seconds": round(total_duration, 2),
        "rps": round(rps, 2),
        "throughput_mbps": round(throughput_mbps, 4),
        "success_rate_pct": round(success_rate_pct, 2),
        "error_rate_pct": round(error_rate_pct, 2),
        "latency_ms": {
            "p50": round(p50, 2),
            "p90": round(p90, 2),
            "p95": round(p95, 2),
            "p99": round(p99, 2),
            "max": round(max_lat, 2)
        }
    }
    return output

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', default='http://gateway-service.default.svc.cluster.local:8080/')
    parser.add_argument('--concurrency', type=int, default=100)
    parser.add_argument('--duration', type=int, default=15)
    parser.add_argument('--warmup', type=int, default=5)
    args = parser.parse_args()

    res = execute_stage(args.url, args.concurrency, args.duration, args.warmup)
    print("--- BENCHMARK JSON RESULT ---")
    print(json.dumps(res, indent=2))
