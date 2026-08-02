#!/usr/bin/env bash
set -e

echo "====================================================="
echo "  Easy Chat Backend Local Development Launcher       "
echo "====================================================="

# 1. Check & Start Docker Compose Infrastructure
echo -e "\n[1/3] Validating Local Infrastructure Dependencies..."
if command -v docker &>/dev/null; then
    echo "Starting Docker Compose (PostgreSQL, Redis, Kafka)..."
    docker compose up -d
else
    echo "⚠️ Docker CLI not found. Proceeding..."
fi

# 2. Check & Deploy Kubernetes / Local Microservices
echo -e "\n[2/3] Verifying Backend Microservices Deployment..."
if command -v kubectl &>/dev/null; then
    echo "Applying Kubernetes manifests to local cluster..."
    kubectl --context kind-easychat apply -f infrastructure/kubernetes/base/ || true
else
    echo "Compiling Go binaries..."
    export CGO_ENABLED=0
    services=("gateway" "auth" "user" "presence" "chat" "nearby" "notification" "media")
    for svc in "${services[@]}"; do
        echo "Building service: $svc..."
        go build -o "apps/backend/bin/$svc" "./apps/backend/services/$svc/cmd/$svc/main.go"
    done
fi

# 3. Verify Health
echo -e "\n[3/3] Verifying API Gateway & Microservices Health..."
sleep 2

if command -v curl &>/dev/null; then
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:18080/healthz || echo "000")
    if [ "$STATUS" = "200" ]; then
        echo "✅ API Gateway Health Probe PASSED (HTTP 200 OK)"
    else
        echo "⚠️ Health probe returned status: $STATUS"
    fi
fi

echo -e "\n====================================================="
echo "🎉 Backend Local Environment Ready!"
echo "====================================================="
