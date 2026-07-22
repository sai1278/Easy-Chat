# Locust Distributed Load Testing Guide

**Suite File:** [`infrastructure/load-testing/locust/locustfile.py`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/load-testing/locust/locustfile.py)  
**Target:** Nearby Connect Microservices Architecture

---

## 1. Overview

Locust provides a Python-based, highly scalable load testing framework with real-time Web UI telemetry, custom user behavior weighting, and custom step load shapes.

---

## 2. Running Locust

### A. Local Web Interface Mode
```bash
locust -f infrastructure/load-testing/locust/locustfile.py --host=http://localhost:8090
```
Open web UI at `http://localhost:8089` to specify target VUs and ramp-up spawn rate.

### B. Headless CI/CD Execution
```bash
locust -f infrastructure/load-testing/locust/locustfile.py \
  --host=http://staging-gateway.easychat.internal:8090 \
  --headless \
  --users 1000 \
  --spawn-rate 50 \
  --run-time 30m \
  --csv=docs/performance/results/locust_summary
```

### C. Distributed Master / Worker Execution
**Master Node:**
```bash
locust -f infrastructure/load-testing/locust/locustfile.py --master
```

**Worker Nodes (Run on multiple machines):**
```bash
locust -f infrastructure/load-testing/locust/locustfile.py --worker --master-host=10.0.0.15
```

---

## 3. Simulated User Tasks & Weights

* `presence_heartbeat` (Weight: 3): High-frequency state heartbeats.
* `nearby_discovery` (Weight: 3): Uber H3 spatial proximity queries.
* `media_upload` (Weight: 2): Attachment uploads.
* `websocket_messaging` (Weight: 1): Persistent WebSocket session & receipt ACK.
