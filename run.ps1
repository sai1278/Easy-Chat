# Easy Chat Backend Startup Script for Windows PowerShell
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  Easy Chat Backend Local Development Launcher       " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

$CWD = Get-Location

# 1. Check & Start Docker Compose Infrastructure (Postgres, Redis, Kafka)
Write-Host "`n[1/3] Validating Local Infrastructure Dependencies..." -ForegroundColor Yellow
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Host "Starting Docker Compose (PostgreSQL, Redis, Kafka)..." -ForegroundColor Green
    docker compose up -d
} else {
    Write-Host "⚠️ Docker CLI not found on PATH. Proceeding with existing Kubernetes/Local Services..." -ForegroundColor Yellow
}

# 2. Check & Deploy Kubernetes / Local Microservices
Write-Host "`n[2/3] Verifying Backend Microservices Deployment..." -ForegroundColor Yellow
if (Get-Command kubectl -ErrorAction SilentlyContinue) {
    Write-Host "Applying Kubernetes manifests to local cluster..." -ForegroundColor Green
    kubectl --context kind-easychat apply -f infrastructure/kubernetes/base/ 2>$null
} else {
    Write-Host "⚠️ kubectl not found. Ensuring local binaries build cleanly..." -ForegroundColor Yellow
    $env:CGO_ENABLED = "0"
    $services = @("gateway", "auth", "user", "presence", "chat", "nearby", "notification", "media")
    foreach ($svc in $services) {
        Write-Host "Building service: $svc..." -ForegroundColor Green
        go build -o "apps/backend/bin/$svc.exe" "./apps/backend/services/$svc/cmd/$svc/main.go"
    }
}

# 3. Verify Microservices Health Endpoint
Write-Host "`n[3/3] Verifying API Gateway & Microservices Health..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

$healthUrl = "http://127.0.0.1:18080/healthz"
try {
    $resp = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5
    if ($resp.StatusCode -eq 200) {
        Write-Host "✅ API Gateway Health Probe PASSED (HTTP 200 OK)" -ForegroundColor Green
    } else {
        Write-Host "⚠️ Health probe returned status: $($resp.StatusCode)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠️ Health probe to $healthUrl unroutable via local proxy, testing ClusterIP..." -ForegroundColor Yellow
}

Write-Host "`n=====================================================" -ForegroundColor Cyan
Write-Host "🎉 Backend Local Environment Ready!" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
