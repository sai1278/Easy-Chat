# k6 Load Testing Suite Guide

**Suite File:** [`infrastructure/load-testing/k6/load-test-suite.js`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/load-testing/k6/load-test-suite.js)  
**Target:** Nearby Connect Microservices Architecture

---

## 1. Overview

The k6 test suite provides a modular, production-grade load generation script capable of simulating up to 5,000 concurrent Virtual Users (VUs). It evaluates REST HTTP endpoints, WebSocket persistent connections, JWT authentication, and media uploads.

---

## 2. Configuration & Environment Variables

| Variable | Default Value | Description |
| :--- | :--- | :--- |
| `TARGET_URL` | `http://gateway.easychat.local:8090` | API Gateway HTTP endpoint |
| `WS_TARGET_URL` | `ws://chat.easychat.local:8085/ws` | Chat Service WebSocket endpoint |

---

## 3. Execution Commands

### A. Run Standard Baseline Test (100 VUs)
```bash
k6 run --vus 100 --duration 5m infrastructure/load-testing/k6/load-test-suite.js
```

### B. Run Full Ramping Load Test (100 -> 500 -> 1000 -> 5000 VUs)
```bash
k6 run -e TARGET_URL=http://staging-gateway.easychat.internal:8090 infrastructure/load-testing/k6/load-test-suite.js
```

### C. Run Distributed k6 Load Test in Kubernetes
```bash
kubectl apply -f - <<EOF
apiVersion: k6.io/v1alpha1
kind: K6
metadata:
  name: k6-load-test
spec:
  parallelism: 4
  script:
    configMap:
      name: k6-test-scripts
      file: load-test-suite.js
EOF
```

---

## 4. Custom Metrics Collected

* `auth_duration`: Trend metric for OIDC token issuance latency.
* `nearby_discovery_duration`: Trend metric for H3 spatial query resolution.
* `chat_message_latency`: Trend metric for end-to-end WebSocket receipt roundtrips.
* `media_upload_duration`: Trend metric for S3 upload URL resolution and stream scan.
* `ws_connection_success_rate`: Rate metric tracking WebSocket 101 Handshake success.
