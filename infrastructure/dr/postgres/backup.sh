#!/bin/bash
# Multi-Region Postgres Backup Automation Script
set -euo pipefail

BACKUP_DIR="/var/lib/postgresql/backups"
ARCHIVE_DIR="/var/lib/postgresql/archive"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/postgres_full_${TIMESTAMP}.sql"
ENCRYPTED_FILE="${BACKUP_FILE}.gpg"
GCS_BUCKET="/mnt/gcs-backup/postgresql"

echo "Starting logical base database dump..."
mkdir -p "${BACKUP_DIR}"
pg_dumpall -U postgres -h localhost > "${BACKUP_FILE}"

echo "Encrypting backup archive using GPG symmetric key..."
# Simulate GPG encryption using a vault-provided passphrase
gpg --symmetric --batch --passphrase "BackupEncryptionSymmetricPassword123!" -o "${ENCRYPTED_FILE}" "${BACKUP_FILE}"

echo "Uploading encrypted backup to multi-region GCS bucket..."
mkdir -p "${GCS_BUCKET}"
cp "${ENCRYPTED_FILE}" "${GCS_BUCKET}/"

echo "Cleaning up local plain-text dump files..."
rm -f "${BACKUP_FILE}"

# Retain locally the last 7 days of encrypted backups
find "${BACKUP_DIR}" -name "*.gpg" -mtime +7 -delete

echo "Purging old WAL archives using pg_archivecleanup..."
# Clean up WAL logs older than the last segment archived
LATEST_WAL=$(ls -t "${ARCHIVE_DIR}" | head -n 1)
if [ -n "${LATEST_WAL}" ]; then
  pg_archivecleanup "${ARCHIVE_DIR}" "${LATEST_WAL}"
fi

echo "Database base backup completed successfully."
