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
- [ ] Migration scripts (if any) are backward-compatible with expand/contract schema evolution and forward-only recovery

### Gate 3.1: Database Migration Delivery & Preflight Gate
Before deploying application pods or promoting traffic, database migrations must be audited, packaged, and verified:

#### 1. Target Database Preflight Inspection
An authorized operator must inspect current migration metadata and physical schema state. **DO NOT assume the target database is at version 8 or any other pre-supposed version.**
```sql
-- Step 1.1: Verify schema version and dirty status
SELECT version, dirty FROM schema_migrations;

-- Step 1.2: Inspect actual users table columns and constraints
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'users';

-- Step 1.3: Inspect actual user_sessions columns and partition structure
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'user_sessions';

-- Step 1.4: Inspect recovery tables and constraints
SELECT table_name FROM information_schema.tables
WHERE table_name IN ('user_recovery_keys', 'user_device_registry', 'recovery_idempotency_records');
```
- **STOP & HALT RELEASE**:
  - If `dirty = true`, an earlier migration failed midway. Stop immediately; do not proceed until a DBA performs manual triage and resolves the dirty state.
  - If the migration history or version is unexpected, or if discrepancies exist between `schema_migrations` and physical schema tables.
- **Reconcile Migration History**: Reconcile the recorded version with the actual schema before deciding whether to migrate.
- **DO NOT** edit already-applied migration files.
- If a concrete schema discrepancy is established, apply only an approved, peer-reviewed forward-only corrective migration (e.g., `000011_*.up.sql`). Never force a dirty version or execute down migrations.
- Verify that automated database backup and recovery procedures have executed and passed before authorizing a production rollout.

#### 2. Migration ConfigMap Delivery & Packaging
The migration files under canonical `database/migrations/` are the single source of truth. Packaging must use only files present in the selected release checkout:

> [!IMPORTANT]
> **Clean-Checkout & Git Tracking Prerequisite**: Migrations `000009` and `000010` must be tracked in version control and present in the release commit/artifact. In a clean checkout (e.g., CI/CD or production deployment runner), untracked local working-tree files will not exist, causing Step 2.1 preflight inventory validation to immediately halt rollout.

```bash
# Step 2.1: Verify inventory and uniqueness of required migrations (000001 through 000010) in release checkout
ERROR_COUNT=0
for i in $(seq -w 1 10); do
  UP_COUNT=$(find database/migrations -maxdepth 1 -name "0000${i}_*.up.sql" 2>/dev/null | wc -l)
  if [ "${UP_COUNT}" -eq 0 ]; then
    echo "ERROR: Required migration 0000${i} (.up.sql) missing in checkout!"
    ERROR_COUNT=$((ERROR_COUNT+1))
  elif [ "${UP_COUNT}" -gt 1 ]; then
    echo "ERROR: Duplicate migration files detected for version 0000${i} (.up.sql count=${UP_COUNT})!"
    ERROR_COUNT=$((ERROR_COUNT+1))
  fi

  DOWN_COUNT=$(find database/migrations -maxdepth 1 -name "0000${i}_*.down.sql" 2>/dev/null | wc -l)
  if [ "${DOWN_COUNT}" -eq 0 ]; then
    echo "ERROR: Required down migration 0000${i} (.down.sql) missing in checkout!"
    ERROR_COUNT=$((ERROR_COUNT+1))
  elif [ "${DOWN_COUNT}" -gt 1 ]; then
    echo "ERROR: Duplicate down migration files detected for version 0000${i} (.down.sql count=${DOWN_COUNT})!"
    ERROR_COUNT=$((ERROR_COUNT+1))
  fi
done
if [ $ERROR_COUNT -gt 0 ]; then
  echo "FATAL: Preflight migration inventory check failed (${ERROR_COUNT} defects). Stopping release rollout."
  exit 1
fi

# Step 2.2: Package easychat-db-migrations ConfigMap directly from database/migrations/
# Ensure target namespace matches migration-job.yaml (default)
kubectl create configmap easychat-db-migrations \
  --from-file=database/migrations/ \
  -n default \
  --dry-run=client -o yaml | kubectl apply -f -

# Step 2.3: Verify ConfigMap contains required migration keys
kubectl get configmap easychat-db-migrations -n default -o jsonpath='{.data}' | grep -q "000010_.*\.up\.sql" || {
  echo "FATAL: ConfigMap missing required migration keys. Stopping rollout."
  exit 1
}
```

#### 3. Execute Pre-Rollout Migration Job
Run the migration Job and block rollout until successful completion. Failed migration execution **MUST** block application rollout:
```bash
# Step 3.1: Inspect existing migration Job (NEVER blindly delete a failed or active Job!)
if kubectl get job easychat-db-migration -n default >/dev/null 2>&1; then
  ACTIVE=$(kubectl get job easychat-db-migration -n default -o jsonpath='{.status.active}' 2>/dev/null || echo "0")
  ACTIVE="${ACTIVE:-0}"
  FAILED=$(kubectl get job easychat-db-migration -n default -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
  FAILED="${FAILED:-0}"
  SUCCEEDED=$(kubectl get job easychat-db-migration -n default -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
  SUCCEEDED="${SUCCEEDED:-0}"

  if [ "${ACTIVE}" -gt 0 ]; then
    echo "FATAL: Existing migration Job 'easychat-db-migration' is currently ACTIVE (active=${ACTIVE})."
    echo "Concurrent or overlapping migration execution is strictly prohibited. Halting release."
    exit 1
  fi

  if [ "${FAILED}" -gt 0 ]; then
    echo "FATAL: Existing migration Job 'easychat-db-migration' has failed status (failed=${FAILED})."
    echo "DO NOT blindly delete or rerun a failed Job! Dumping sanitized logs for DBA analysis:"
    kubectl logs job/easychat-db-migration -n default --tail=50 2>&1 | sed -E 's#(postgres(ql)?://[^:]+:)[^@]+@#\1*****@#g' || true
    echo "Halt release immediately. Reconcile database state manually."
    exit 1
  fi

  if [ "${SUCCEEDED}" -eq 0 ]; then
    echo "FATAL: Existing migration Job 'easychat-db-migration' is in an indeterminate state."
    echo "Manual operator triage required before modifying migration Job. Halting release."
    exit 1
  fi

  echo "Existing migration job succeeded in a prior release. Safely pruning completed Job:"
  kubectl delete job easychat-db-migration -n default
fi

# Step 3.2: Launch migration Job
kubectl apply -f infrastructure/kubernetes/production/migration-job.yaml

# Step 3.3: Block until completed (fail-closed timeout 300s)
if ! kubectl wait --for=condition=complete job/easychat-db-migration -n default --timeout=300s; then
  echo "FATAL: Migration Job failed or timed out! Application rollout BLOCKED."
  kubectl logs job/easychat-db-migration -n default --tail=100 2>&1 | sed -E 's#(postgres(ql)?://[^:]+:)[^@]+@#\1*****@#g' || true
  exit 1
fi
```
Alternatively, execute the automated runner script which performs all the above steps:
```bash
bash infrastructure/scripts/deliver-migrations.sh
```
- If ConfigMap generation, Job execution, or the wait condition fails, **HALT APPLICATION ROLLOUT IMMEDIATELY**. Application pods must never be rolled out against an unmigrated, mismatched, or failed schema.
- **NEVER** automatically execute down migrations or force a dirty migration version.

### Gate 4: Rollback Readiness
- [ ] Previous stable image tag documented
- [ ] Forward-only rollback compatibility verified (application rollback preserves schema; down migrations strictly prohibited)
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
