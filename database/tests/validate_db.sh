#!/usr/bin/env bash
# validate_db.sh - Boots up a local database container to verify migrations and run DDL assertions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATABASE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "====================================================="
echo "Nearby Connect - PostgreSQL Validation Test Runner"
echo "====================================================="

# Check Docker dependency
if ! command -v docker &>/dev/null; then
    echo "❌ Error: 'docker' command not found. This test requires a Docker container environment." >&2
    exit 1
fi

CONTAINER_NAME="nearby-test-postgres"
DB_USER="nearby_user"
DB_NAME="nearby_connect"
DB_PASS="nearby_secure_pass"

# Cleanup any stale running containers
docker rm -f "${CONTAINER_NAME}" &>/dev/null || true

echo "Starting transient PostgreSQL container..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  -e POSTGRES_USER="${DB_USER}" \
  -e POSTGRES_DB="${DB_NAME}" \
  -e POSTGRES_PASSWORD="${DB_PASS}" \
  -p 54321:5432 \
  postgres:16-alpine

# Register container cleanup on exit
trap 'echo "Cleaning up test container..."; docker rm -f "${CONTAINER_NAME}" &>/dev/null || true' EXIT

echo "Waiting for PostgreSQL to become ready..."
until docker exec "${CONTAINER_NAME}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" &>/dev/null; do
  sleep 1
done
echo "✅ PostgreSQL is ready."

run_sql() {
    docker exec -i "${CONTAINER_NAME}" psql -U "${DB_USER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1
}

echo "Applying migrations..."
run_sql < "${DATABASE_DIR}/migrations/000001_init_schema.up.sql"
run_sql < "${DATABASE_DIR}/migrations/000002_chat_and_messaging.up.sql"
run_sql < "${DATABASE_DIR}/migrations/000003_jobs_and_auditing.up.sql"
echo "✅ Migrations applied successfully."

echo "Running DDL and behavior assertions..."
run_sql < "${SCRIPT_DIR}/validate_schema.sql"

echo "Testing down migrations (rollback verify)..."
run_sql < "${DATABASE_DIR}/migrations/000003_jobs_and_auditing.down.sql"
run_sql < "${DATABASE_DIR}/migrations/000002_chat_and_messaging.down.sql"
run_sql < "${DATABASE_DIR}/migrations/000001_init_schema.down.sql"
echo "✅ Rollback schema dropped successfully without errors."

echo "====================================================="
echo "🎉 ALL SCHEMA INTEGRATION TESTS PASSED SUCCESSFULLY."
echo "====================================================="
