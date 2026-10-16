#!/usr/bin/env bash
# ==============================================================================
# Easy Chat — Kubernetes Database Migration Packaging and Execution Runner
# ==============================================================================
# Strict fail-closed automation for database migrations:
# 1. Validates presence and uniqueness of required migrations 000001-000010 in checkout.
# 2. Reconciles namespace with Job manifest to prevent split-namespace drift.
# 3. Packages canonical database/migrations/ into easychat-db-migrations ConfigMap.
# 4. Verifies ConfigMap keys.
# 5. Safely inspects existing easychat-db-migration Job (handles active, failed, indeterminate).
# 6. Executes migration Job and waits for completion (timeout: 300s).
# 7. Redacts credentials from diagnostic logs upon failure.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
JOB_MANIFEST="${JOB_MANIFEST:-${PROJECT_ROOT}/infrastructure/kubernetes/production/migration-job.yaml}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-${PROJECT_ROOT}/database/migrations}"
TIMEOUT="${TIMEOUT:-300s}"

# Redact sensitive credentials (both URI-style and key-value DSNs) from diagnostic logs
sanitize_diagnostic_logs() {
  sed -E \
    -e 's#(postgres(ql)?://[^:]+:)[^@]+@#\1*****@#g' \
    -e 's#([pP][aA][sS][sS][wW][oO][rR][dD][[:space:]]*=[[:space:]]*")([^"]+)(")#\1*****\3#g' \
    -e "s#([pP][aA][sS][sS][wW][oO][rR][dD][[:space:]]*=[[:space:]]*')([^']+)(')#\1*****\3#g" \
    -e 's#([pP][aA][sS][sS][wW][oO][rR][dD][[:space:]]*=[[:space:]]*)([^"'"'"'[[:space:]]+)#\1*****#g'
}

# Reconcile namespace with Job manifest
if [ ! -f "${JOB_MANIFEST}" ]; then
  echo "[FATAL] Migration Job manifest not found: ${JOB_MANIFEST}" >&2
  exit 1
fi

MANIFEST_NAMESPACE=$(grep '^[[:space:]]*namespace:' "${JOB_MANIFEST}" | head -n1 | awk '{print $2}' | tr -d '"' || echo "")
MANIFEST_NAMESPACE="${MANIFEST_NAMESPACE:-default}"

if [ -n "${NAMESPACE:-}" ] && [ "${NAMESPACE}" != "${MANIFEST_NAMESPACE}" ]; then
  echo "[FATAL] Namespace mismatch: environment NAMESPACE='${NAMESPACE}' conflicts with manifest namespace '${MANIFEST_NAMESPACE}' in ${JOB_MANIFEST}" >&2
  echo "[FATAL] Reconcile namespace configuration to prevent split-namespace resource creation." >&2
  exit 1
fi
NAMESPACE="${MANIFEST_NAMESPACE}"

echo "[INFO] Starting migration delivery and release gate verification..."
echo "[INFO] Target Namespace: ${NAMESPACE}"
echo "[INFO] Migrations Directory: ${MIGRATIONS_DIR}"
echo "[INFO] Job Manifest: ${JOB_MANIFEST}"

# 1. Preflight Inventory Check: Ensure migrations 000001 through 000010 are present and unique
echo "[INFO] Step 1: Validating migration file inventory in checkout..."
if [ ! -d "${MIGRATIONS_DIR}" ]; then
  echo "[FATAL] Migrations directory not found: ${MIGRATIONS_DIR}" >&2
  exit 1
fi

ERROR_COUNT=0
for i in $(seq -w 1 10); do
  # Verify .up.sql
  UP_COUNT=$(find "${MIGRATIONS_DIR}" -maxdepth 1 -name "0000${i}_*.up.sql" 2>/dev/null | wc -l)
  if [ "${UP_COUNT}" -eq 0 ]; then
    echo "[ERROR] Required migration 0000${i} (.up.sql) is missing from ${MIGRATIONS_DIR}" >&2
    ERROR_COUNT=$((ERROR_COUNT + 1))
  elif [ "${UP_COUNT}" -gt 1 ]; then
    echo "[ERROR] Duplicate migration files detected for version 0000${i} (.up.sql count=${UP_COUNT}) in ${MIGRATIONS_DIR}" >&2
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi

  # Verify .down.sql
  DOWN_COUNT=$(find "${MIGRATIONS_DIR}" -maxdepth 1 -name "0000${i}_*.down.sql" 2>/dev/null | wc -l)
  if [ "${DOWN_COUNT}" -eq 0 ]; then
    echo "[ERROR] Required down migration 0000${i} (.down.sql) is missing from ${MIGRATIONS_DIR}" >&2
    ERROR_COUNT=$((ERROR_COUNT + 1))
  elif [ "${DOWN_COUNT}" -gt 1 ]; then
    echo "[ERROR] Duplicate down migration files detected for version 0000${i} (.down.sql count=${DOWN_COUNT}) in ${MIGRATIONS_DIR}" >&2
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi
done

if [ "${ERROR_COUNT}" -gt 0 ]; then
  echo "[FATAL] Preflight migration inventory validation failed (${ERROR_COUNT} defects found). Halting rollout." >&2
  exit 1
fi
echo "[INFO] Migration inventory check passed (all 000001-000010 up and down files verified uniquely)."

# 2. Package ConfigMap from canonical migrations directory
echo "[INFO] Step 2: Packaging easychat-db-migrations ConfigMap in namespace '${NAMESPACE}'..."
if ! kubectl create configmap easychat-db-migrations \
  --from-file="${MIGRATIONS_DIR}/" \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -; then
  echo "[FATAL] Failed to create or apply ConfigMap easychat-db-migrations." >&2
  exit 1
fi

# Verify ConfigMap contains required data
CONFIGMAP_DATA=$(kubectl get configmap easychat-db-migrations -n "${NAMESPACE}" -o jsonpath='{.data}' 2>/dev/null || echo "")
if [ -z "${CONFIGMAP_DATA}" ]; then
  echo "[FATAL] ConfigMap easychat-db-migrations exists but has no data." >&2
  exit 1
fi

for i in $(seq -w 1 10); do
  if ! echo "${CONFIGMAP_DATA}" | grep -q "0000${i}_.*\.up\.sql"; then
    echo "[FATAL] ConfigMap easychat-db-migrations missing verified migration 0000${i}." >&2
    exit 1
  fi
done
echo "[INFO] ConfigMap easychat-db-migrations successfully verified in namespace '${NAMESPACE}'."

# 3. Inspect existing migration Job (Handle active, failed, indeterminate, and succeeded states)
echo "[INFO] Step 3: Inspecting existing migration Job in namespace '${NAMESPACE}'..."
if kubectl get job easychat-db-migration -n "${NAMESPACE}" >/dev/null 2>&1; then
  ACTIVE_COUNT=$(kubectl get job easychat-db-migration -n "${NAMESPACE}" -o jsonpath='{.status.active}' 2>/dev/null || echo "0")
  ACTIVE_COUNT="${ACTIVE_COUNT:-0}"
  FAILED_COUNT=$(kubectl get job easychat-db-migration -n "${NAMESPACE}" -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
  FAILED_COUNT="${FAILED_COUNT:-0}"
  SUCCEEDED_COUNT=$(kubectl get job easychat-db-migration -n "${NAMESPACE}" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
  SUCCEEDED_COUNT="${SUCCEEDED_COUNT:-0}"

  # Case A: Active Job -> Prohibit overlapping execution
  if [ "${ACTIVE_COUNT}" -gt 0 ]; then
    echo "[FATAL] An existing migration Job 'easychat-db-migration' is currently ACTIVE (active=${ACTIVE_COUNT})." >&2
    echo "[FATAL] Concurrent or overlapping migration execution is strictly prohibited." >&2
    echo "[INFO] A previous migration is in progress. Await its completion or investigate active pods." >&2
    exit 1
  fi

  # Case B: Failed Job -> Preserve Job, emit diagnostic logs, hard stop
  if [ "${FAILED_COUNT}" -gt 0 ]; then
    echo "[FATAL] An existing migration Job 'easychat-db-migration' has FAILED status (failed=${FAILED_COUNT})." >&2
    echo "[FATAL] Blind deletion or automatic rerun of failed migration Jobs is STRICTLY PROHIBITED." >&2
    echo "[INFO] Fetching sanitized logs of failed migration Job for diagnostic inspection:" >&2
    kubectl logs job/easychat-db-migration -n "${NAMESPACE}" --tail=50 2>&1 | sanitize_diagnostic_logs >&2 || true
    echo "[FATAL] Halting release immediately. Database Administrator must investigate dirty state." >&2
    exit 1
  fi

  # Case C: Indeterminate state (neither succeeded, failed, nor active)
  if [ "${SUCCEEDED_COUNT}" -eq 0 ]; then
    echo "[FATAL] Existing migration Job 'easychat-db-migration' is in an indeterminate state." >&2
    echo "[FATAL] Refusing to modify or replace Job in indeterminate state without manual operator triage." >&2
    exit 1
  fi

  # Case D: Succeeded Job -> Safely prune completed Job
  echo "[INFO] Existing migration Job succeeded in a prior release. Safely pruning completed Job."
  if ! kubectl delete job easychat-db-migration -n "${NAMESPACE}"; then
    echo "[FATAL] Failed to delete completed migration Job." >&2
    exit 1
  fi
fi

# 4. Launch migration Job
echo "[INFO] Step 4: Applying migration Job manifest: ${JOB_MANIFEST}..."
if ! kubectl apply -f "${JOB_MANIFEST}" -n "${NAMESPACE}"; then
  echo "[FATAL] Failed to apply migration Job manifest ${JOB_MANIFEST}." >&2
  exit 1
fi

# 5. Wait for Job completion with fail-closed timeout
echo "[INFO] Step 5: Waiting for migration Job to reach Complete status (timeout: ${TIMEOUT})..."
if ! kubectl wait --for=condition=complete job/easychat-db-migration -n "${NAMESPACE}" --timeout="${TIMEOUT}"; then
  echo "[FATAL] Migration Job failed to complete within ${TIMEOUT} or encountered an error!" >&2
  echo "[INFO] Fetching sanitized migration Job logs:" >&2
  kubectl logs job/easychat-db-migration -n "${NAMESPACE}" --tail=100 2>&1 | sanitize_diagnostic_logs >&2 || true
  echo "[FATAL] Application rollout BLOCKED. Do not deploy application pods against failed schema." >&2
  exit 1
fi

echo "[INFO] Migration Job completed successfully. Schema is up to date."
exit 0
