# Production-Scale Performance Testing Runbook

**Lead SRE & Performance Engineer**

---

## 1. Pre-Flight Preparation Checklist

1. **Environment Isolation:** Verify performance testing executes against dedicated staging environment (`easychat-staging` namespace), isolated from production users.
2. **Prometheus Scraping:** Confirm Prometheus is actively scraping `/metrics` endpoints across all 10 microservices.
3. **Database Pre-seeding:** Pre-seed PostgreSQL with 10,000 synthetic test users and Redis with H3 spatial test coordinates.
4. **Log Silencing:** Verify debug logging is disabled (`LOG_LEVEL=info` or `warn`).

---

## 2. Step-by-Step Load Test Execution

### Step 1: Initialize Baseline Monitoring
Launch Grafana dashboard at `http://grafana.easychat.local:3000` and verify CPU/Memory baseline is flat (< 10%).

### Step 2: Execute 100 VU Sanity Load Test
```bash
k6 run --vus 100 --duration 5m infrastructure/load-testing/k6/load-test-suite.js
```
*Verify zero 5xx errors and P95 latency < 100ms.*

### Step 3: Execute Ramping Load Test (500 -> 1000 -> 5000 VUs)
```bash
k6 run -e TARGET_URL=http://gateway.easychat.local:8090 infrastructure/load-testing/k6/load-test-suite.js
```

### Step 4: Monitor Horizontal Pod Autoscaling (HPA)
Observe pod scale-out in Kubernetes during Tier 3 (1,000 VUs) and Tier 4 (5,000 VUs):
```bash
kubectl get hpa -n easychat-staging -w
```

### Step 5: Execute Spike Test Scenario
```bash
k6 run -e SCENARIO=spike_test infrastructure/load-testing/k6/load-test-suite.js
```

---

## 3. Troubleshooting & Rollback Procedures

* **Symptom: High HTTP 503 Service Unavailable:**
  * Check API Gateway rate-limiter in Redis (`rate_limit:{ip}`). Increase `RATE_LIMIT_RPS` env variable if necessary.
* **Symptom: Kafka Consumer Lag Spikes:**
  * Scale out Notification & Chat service worker replicas: `kubectl scale deployment chat-worker --replicas=10`.
* **Symptom: Database Connection Pool Exhaustion:**
  * Increase PostgreSQL `max_connections` in `postgresql.conf` or scale out PgBouncer instances.
