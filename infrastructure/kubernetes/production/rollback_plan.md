# SRE Operations Rollback Playbook

This document details the recovery plans, commands, and workflows required to handle deployment incidents and safely revert to stable revisions with zero downtime.

---

## 1. Rolling Update Rollback Plan
If a primary microservice deployment rolling update (triggered via `kubectl set image` or manifest apply) is unstable, failing health checks, or crash-looping.

### 1.1. Identify the Incident
Monitor the rollouts using:
```bash
kubectl rollout status deployment/<service-name>
```
Look for container restarts or prolonged `Readiness` failures.

### 1.2. Execute Rollback
Instantly abort and revert to the last working revision:
```bash
kubectl rollout undo deployment/<service-name>
```

To view deployment history:
```bash
kubectl rollout history deployment/<service-name>
```

To rollback to a specific revision (e.g. Revision 3):
```bash
kubectl rollout undo deployment/<service-name> --to-revision=3
```

---

## 2. Canary Deployment Rollback Plan
If metrics reveal high HTTP 5xx error rates, latency spikes, or memory leaks on the active Canary pods.

### 2.1. Abort Canary Traffic Routing
Immediately disconnect the Canary Ingress controller to cease all live traffic allocation to Canary pods:
```bash
kubectl delete ingress auth-service-canary-ingress
```
This forces the primary Ingress to immediately absorb 100% of request routing.

### 2.2. Teardown Canary Pods
Destroy the Canary pods and ClusterIP services to free cluster resources:
```bash
kubectl delete svc auth-service-canary
kubectl delete deployment auth-service-canary
```

---

## 3. Database Schema Migration and Incident Rollback Strategy

If a deployment or schema migration triggers application errors, performance degradation, or backward-compatibility issues, follow this safe, non-destructive recovery procedure.

### 3.1. Standard Procedure: Roll Back Application While Preserving Schema
1. **Preserve Database Schema:** All Easy Chat database migrations are designed using the expand/contract additive pattern (e.g., `ADD COLUMN IF NOT EXISTS`, new independent tables, nullable/defaulted attributes). Consequently, the previous stable application release is backward-compatible with the migrated schema and simply ignores newly added columns and tables.
2. **Revert Application Deployment:** Immediately execute application rollback to the previous stable release:
   ```bash
   kubectl rollout undo deployment/<service-name>
   ```
   Or revert the container image tag in Docker Compose:
   ```bash
   bash /opt/easychat/app/scripts/deploy_production_service.sh <service-name> <previous-stable-image-digest>
   ```
3. **Verify Service Health:** Confirm error rates and latency return to baseline SLO targets. Do not touch the database schema during this phase.

### 3.2. Strictly Prohibited: Destructive `migrate down`
- **NEVER** run `migrate down` or `down 1` against any production, staging, or testing database containing persistent user data.
- Down migrations (`.down.sql`) contain irreversible destructive operations—such as `DROP TABLE user_recovery_keys`, `DROP TABLE user_device_registry`, `DROP COLUMN password_hash`, and `DROP COLUMN device_id`. Executing down migrations results in immediate and permanent loss of user credentials, encryption verifiers, active sessions, and device bindings.

### 3.3. Correct Schema Remediation: Forward-Only Compensating Migrations
If the database schema itself has a defect (e.g., an unindexed foreign key, an overly restrictive constraint, or an incorrect column type):
1. **Author a Compensating Forward Migration:** Create a new sequential migration (e.g., `000011_compensate_<issue_description>.up.sql`).
2. **Review & Test:** Peer-review the compensating SQL for data safety, idempotency, and partition locking impact. Validate in an isolated pre-production database.
3. **Apply Forward:** Apply the compensating migration forward using the standard migration job:
   ```bash
   kubectl create job --from=cronjob/easychat-db-migration easychat-db-migration-compensating
   ```
   This ensures `schema_migrations` maintains clean sequential version progression without `dirty` flag corruption.

### 3.4. Exceptional Disaster Recovery: Backup Verification & Inherent Data Loss Notice
In the exceptional event where a corrupt state forces a database point-in-time recovery (PITR) or table restoration:
1. **Pre-requisite Sign-Off:** Written sign-off from Senior SRE, Security, and Database leads is mandatory before any destructive intervention.
2. **Verified Backup Required:** A verified point-in-time backup and validated recovery test plan must be executed before attempting restore operations.
3. **Inherent Data Loss Warning:** A backup alone does **not** make destructive rollback safe. Point-in-time restoration inevitably results in the permanent loss of all user registrations, messages, read receipts, and sessions committed between the backup snapshot time and the incident window. PITR is a measure of last resort for total data corruption, never a substitute for forward-only schema management.
