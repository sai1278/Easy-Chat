#!/usr/bin/env bash
# ==============================================================================
# Easy Chat - Production First-Boot TLS & Certbot ACME Bootstrap Script
# ==============================================================================
# This script eliminates the chicken-and-egg problem where Nginx cannot start
# because Let's Encrypt certificates do not exist yet.
#
# Process:
# 1. Inspect if real Let's Encrypt certificates exist for $DOMAIN_NAME.
# 2. If missing, generate temporary self-signed certificates so Nginx can start
#    and bind ports 80 and 443 immediately.
# 3. Start Nginx and backend microservices via Docker Compose.
# 4. Check whether public DNS for $DOMAIN_NAME points to this host.
# 5. If DNS is pointing to this host, request real Let's Encrypt certificates
#    via the ACME webroot challenge on port 80.
# 6. Gracefully reload Nginx to activate the real certificates.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load production environment variables if available
if [ -f "${PROJECT_ROOT}/.env.production" ]; then
  # shellcheck disable=SC1091
  set -a
  source "${PROJECT_ROOT}/.env.production"
  set +a
elif [ -f "${PROJECT_ROOT}/.env" ]; then
  # shellcheck disable=SC1091
  set -a
  source "${PROJECT_ROOT}/.env"
  set +a
fi

DOMAIN_NAME="${DOMAIN_NAME:-api.easychat.com}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-admin@easychat.com}"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.production.yml"
CERT_DIR="certbot_etc"
LIVE_PATH="/etc/letsencrypt/live/${DOMAIN_NAME}"

echo "============================================================"
echo "Easy Chat TLS Bootstrap for: ${DOMAIN_NAME}"
echo "============================================================"

# Helper function to check if cert is self-signed
is_self_signed() {
  local cert_file="$1"
  if [ ! -f "${cert_file}" ]; then
    return 1
  fi
  local issuer
  local subject
  issuer=$(openssl x509 -in "${cert_file}" -noout -issuer 2>/dev/null || echo "")
  subject=$(openssl x509 -in "${cert_file}" -noout -subject 2>/dev/null || echo "")
  if [ -n "${issuer}" ] && [ "${issuer}" = "${subject}" ]; then
    return 0 # self-signed
  fi
  return 1 # not self-signed
}

# 1. Check if temporary certificate is needed inside the certbot_etc volume
echo "--> Checking TLS certificates status for ${DOMAIN_NAME}..."

# Create certbot directories inside docker volumes if running via compose
docker compose -f "${COMPOSE_FILE}" run --rm --entrypoint sh certbot -c "mkdir -p '${LIVE_PATH}' /var/www/certbot" >/dev/null 2>&1 || true

# Test if certificate exists inside volume
CERT_EXISTS=0
docker compose -f "${COMPOSE_FILE}" run --rm --entrypoint sh certbot -c "test -f '${LIVE_PATH}/fullchain.pem'" >/dev/null 2>&1 && CERT_EXISTS=1 || CERT_EXISTS=0

if [ "${CERT_EXISTS}" -eq 0 ]; then
  echo "--> No certificates found. Creating temporary self-signed certificate for initial Nginx boot..."
  docker compose -f "${COMPOSE_FILE}" run --rm --entrypoint sh certbot -c "\
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
      -keyout '${LIVE_PATH}/privkey.pem' \
      -out '${LIVE_PATH}/fullchain.pem' \
      -subj '/CN=${DOMAIN_NAME}'"
  echo "--> Temporary self-signed certificate generated successfully."
else
  echo "--> Certificate already exists at ${LIVE_PATH}."
fi

# 2. Start Nginx and dependent containers
echo "--> Starting Nginx and API Gateway stack..."
docker compose -f "${COMPOSE_FILE}" up -d nginx gateway

# 3. DNS Verification before calling Let's Encrypt
echo "--> Verifying DNS resolution for ${DOMAIN_NAME}..."
RESOLVED_IP=""
if command -v dig >/dev/null 2>&1; then
  RESOLVED_IP=$(dig +short "${DOMAIN_NAME}" | tail -n1 || echo "")
elif command -v getent >/dev/null 2>&1; then
  RESOLVED_IP=$(getent hosts "${DOMAIN_NAME}" | awk '{ print $1 }' || echo "")
fi

PUBLIC_IP=$(curl -s -m 5 https://checkip.amazonaws.com || curl -s -m 5 https://ifconfig.me || echo "")

echo "    Target Domain : ${DOMAIN_NAME}"
echo "    Resolved IP   : ${RESOLVED_IP:-Unknown}"
echo "    Host Public IP: ${PUBLIC_IP:-Unknown}"

if [ -n "${RESOLVED_IP}" ] && [ -n "${PUBLIC_IP}" ] && [ "${RESOLVED_IP}" = "${PUBLIC_IP}" ]; then
  echo "--> DNS verified: ${DOMAIN_NAME} resolves correctly to ${PUBLIC_IP}."
  
  # Check if certificate is already a valid Let's Encrypt certificate
  IS_LE=0
  if docker compose -f "${COMPOSE_FILE}" run --rm --entrypoint sh certbot -c "openssl x509 -in '${LIVE_PATH}/fullchain.pem' -noout -issuer 2>/dev/null | grep -qi 'Let.s Encrypt'" >/dev/null 2>&1; then
    IS_LE=1
  fi

  if [ "${IS_LE}" -eq 1 ] && [ "${1:-}" != "--force" ]; then
    echo "--> [INFO] Active certificate is already a valid Let's Encrypt certificate."
    echo "--> Automatic renewals are managed by the background certbot container."
    echo "--> (Pass --force to force re-issuance if required)."
  else
    echo "--> Requesting production Let's Encrypt certificate..."
    docker compose -f "${COMPOSE_FILE}" run --rm --entrypoint certbot certbot certonly --webroot \
      -w /var/www/certbot \
      --email "${CERTBOT_EMAIL}" \
      --agree-tos \
      --no-eff-email \
      --keep-until-expiring \
      -d "${DOMAIN_NAME}" \
      --non-interactive

    echo "--> Certificate issuance completed. Reloading Nginx with production TLS..."
    docker compose -f "${COMPOSE_FILE}" exec nginx nginx -s reload
    echo "--> [SUCCESS] Production Let's Encrypt TLS active for https://${DOMAIN_NAME}"
  fi
else
  echo "============================================================"
  echo "[WARNING] DNS is not yet pointed to this server's public IP (${PUBLIC_IP:-Not Detected})."
  echo "Nginx has been started using the temporary certificate to allow port 80 routing."
  echo ""
  echo "Next Steps:"
  echo "1. In your DNS provider, create an 'A' record pointing ${DOMAIN_NAME} to ${PUBLIC_IP}."
  echo "2. Once DNS propagation finishes, run:"
  echo "   bash infrastructure/docker/bootstrap-tls.sh"
  echo "============================================================"
fi
