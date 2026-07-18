# Nearby Connect — Release Management Playbook
> **Owner:** SRE + Engineering | **Review Cycle:** Quarterly

---

## 1. Release Gates (Pre-Deployment Checklist)

All deployments to production MUST pass the following gates. A gate cannot be skipped without explicit VP Engineering approval.

### Gate 1: Code & Test Readiness
- [ ] All CI checks passing (unit tests, integration tests, SAST, SBOM)
- [ ] Code review approved by 2 engineers (1 must be senior)
- [ ] No critical or high Trivy security findings unresolved
- [ ] No `TODO: PROD` or `FIXME: PROD` comments in diff

### Gate 2: SLO Health Check
- [ ] Error budget remaining > 25% for all SLOs
- [ ] No active SEV-0 or SEV-1 incidents
- [ ] No deployment freeze in effect (check `DEPLOY_GATE` env var)

```bash
# Check current error budget
gh variable get DEPLOY_GATE --env production

# Check SLO burn rate
# PromQL: (sum(rate(http_requests_total{status=~"5.."}[1h])) / sum(rate(http_requests_total[1h]))) / 0.001
# Must be < 1.0 (not consuming budget faster than it accrues)
```

### Gate 3: Deployment Configuration
- [ ] Image tag is a specific SHA digest (never `latest`)
- [ ] Resource requests/limits set in values.yaml
- [ ] Health check endpoints validated on staging
- [ ] Migration scripts (if any) are backward-compatible and reversible

### Gate 4: Rollback Readiness
- [ ] Previous stable image tag documented
- [ ] Database migration is reversible (down migration exists)
- [ ] On-call engineer available for 60 min post-deployment

---

## 2. Deployment Strategy Selection

```
Feature type?
├── Database schema change ────────► Blue/Green Deployment
├── Breaking API change ───────────► Blue/Green with client version gate
├── Minor feature / bug fix ───────► Canary Rollout (10% → 100%)
├── Config-only change ────────────► Rolling Update (standard)
└── Hotfix for active incident ────► Rolling Update → immediate full rollout
```

---

## 3. Canary Rollout Procedure

### Stage 1: Deploy Canary (10% Traffic)

```bash
# 1. Set canary image tag
helm upgrade easychat ./infrastructure/helm/easychat \
  --set services.<service>.canaryImage=ghcr.io/easychat/<svc>:<sha> \
  --set canary.enabled=true \
  --set canary.weight=10

# 2. Verify canary pods are running
kubectl get pods -l track=canary -n default

# 3. Verify canary health endpoint
kubectl exec -it <canary-pod> -- curl -f localhost:<port>/health
```

### Stage 2: Monitor (T+0 to T+15 min at 10%)

Monitor these metrics during canary observation:

```promql
# Canary error rate (must stay < 1%)
sum(rate(http_requests_total{status=~"5..", track="canary"}[2m])) by (service)
/ sum(rate(http_requests_total{track="canary"}[2m])) by (service)

# Canary p99 latency (must stay < 200ms)
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{track="canary"}[2m])) by (le, service))
```

**Promotion criteria:**
- Error rate < 1% for full 15-minute observation window
- p99 latency < 200ms
- No new error patterns in Loki logs

### Stage 3: Progressive Promotion

| Time | Canary Weight | Action |
|---|---|---|
| T+0 | 10% | Deploy canary |
| T+15m | 25% | Promote if Stage 2 criteria met |
| T+45m | 50% | Promote if metrics still healthy |
| T+90m | 100% | Full promotion (delete canary, update primary) |

```bash
# Promote canary weight to 25%
kubectl patch ingress easychat-ingress -n default \
  --type merge \
  -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/canary-weight":"25"}}}'

# Full promotion: update primary deployment
kubectl set image deployment/<service> <container>=ghcr.io/easychat/<svc>:<sha>

# Cleanup canary resources
kubectl delete ingress <service>-canary-ingress -n default
kubectl delete deployment <service>-canary -n default
```

### Automatic Rollback Trigger
The CI/CD pipeline monitors canary metrics. If error rate > 1% is detected by Prometheus alerting (`CanaryErrorRateExceedsThreshold`), the pipeline automatically:
1. Removes canary ingress (stops canary traffic)
2. Deletes canary deployment
3. Posts alert to `#incidents` channel
4. Opens a rollback incident ticket

---

## 4. Blue/Green Deployment Procedure

### Step 1: Deploy Green Environment
```bash
kubectl apply -f deployments-green.yaml -n default
kubectl apply -f services-green.yaml -n default
```

### Step 2: Validate Green
```bash
# Wait for all green pods to be Ready
kubectl wait --for=condition=ready pod -l env=green -n default --timeout=120s

# Run smoke tests against green
curl -f https://easychat.local/api/v1/auth/health --resolve easychat.local:443:<green-svc-ip>
```

### Step 3: Traffic Switch
```bash
# Patch ingress to point to green services
kubectl patch ingress easychat-ingress -n default \
  --type json \
  -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service/name","value":"auth-service-green"}]'
```

### Step 4: Monitor (15 min)
- Error rate must stay < 0.1%
- Latency must stay < 200ms
- If metrics degrade: patch ingress back to blue

### Step 5: Decommission Blue
```bash
kubectl delete deployment <service>-blue -n default
kubectl delete service <service>-blue -n default
```

---

## 5. Hotfix Procedure

Used only during active incidents where a canary promotion is too slow.

```bash
# 1. Build and push hotfix image (CI pipeline with HOTFIX=true flag)
# This bypasses integration tests but still runs unit tests + Trivy

# 2. Apply immediately to all replicas
kubectl set image deployment/<service> \
  <container>=ghcr.io/easychat/<svc>:<hotfix-sha> -n default

# 3. Monitor rollout
kubectl rollout status deployment/<service> -n default

# 4. If rollout fails, immediate rollback
kubectl rollout undo deployment/<service> -n default

# 5. Create post-mortem ticket within 24h for hotfix root cause
```

**Hotfix constraints:**
- Must have 1 approver from SRE + 1 from engineering lead
- Unit tests MUST pass (never skip)
- Must create follow-up ticket for proper fix within next sprint

---

## 6. Release Calendar

| Day | Activity |
|---|---|
| Monday | Deployment window opens (except Fridays and day before holidays) |
| Tuesday–Thursday | Active deployment window |
| Friday | **NO PRODUCTION DEPLOYMENTS** (reduced on-call coverage on weekends) |
| Saturday–Sunday | Emergency hotfixes only (SEV-0/1 active incident) |

### Freeze Periods
- 48 hours before major product launches
- 72 hours before scheduled peak events (marketing campaigns)
- During active SEV-0/1 incidents
- When error budget < 10% remaining

---

## 7. Deployment Verification (Smoke Test Suite)

Run after every production deployment to verify correctness:

```bash
#!/bin/bash
# smoke-test.sh — Run after every production deployment

BASE_URL="https://easychat.local"
FAILURES=0

check() {
  local url="$1"
  local expected="$2"
  local status=$(curl -o /dev/null -s -w "%{http_code}" "$url")
  if [ "$status" != "$expected" ]; then
    echo "FAIL: $url returned $status (expected $expected)"
    FAILURES=$((FAILURES+1))
  else
    echo "PASS: $url → $status"
  fi
}

check "$BASE_URL/api/v1/auth/health" "200"
check "$BASE_URL/api/v1/chat/health" "200"
check "$BASE_URL/api/v1/nearby/health" "200"
check "$BASE_URL/api/v1/presence/health" "200"
check "$BASE_URL/api/v1/user/health" "200"
check "$BASE_URL/api/v1/media/health" "200"
check "$BASE_URL/api/v1/notification/health" "200"

if [ $FAILURES -gt 0 ]; then
  echo "SMOKE TESTS FAILED: $FAILURES endpoints unhealthy"
  echo "Initiating automatic rollback..."
  kubectl rollout undo deployment/<service>
  exit 1
fi

echo "ALL SMOKE TESTS PASSED"
```
