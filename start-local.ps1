# start-local.ps1 — Launches all EasyChat backend microservices locally on Windows
# Run from project root: .\start-local.ps1
# Stop all: Get-Job | Stop-Job | Remove-Job

param([switch]$Stop)

if ($Stop) {
    Write-Host "Stopping all background jobs..." -ForegroundColor Yellow
    Get-Job | Stop-Job
    Get-Job | Remove-Job
    Write-Host "All jobs stopped." -ForegroundColor Green
    exit 0
}

$ROOT = Get-Location

# Shared environment variables (localhost addresses, not Kubernetes DNS)
$commonEnv = @{
    "DISABLE_TLS"    = "true"
    "ENVIRONMENT"    = "development"
    "LOG_LEVEL"      = "info"
    "JWT_SECRET"     = "very-long-and-secure-random-gateway-signing-secret-key-123"
    "DATABASE_URL"   = "postgres://nearby_user:nearby_secure_pass@127.0.0.1:54322/nearby_connect?sslmode=disable"
    "REDIS_URL"      = "127.0.0.1:6379"
    "REDIS_ADDR"     = "127.0.0.1:6379"
    "KAFKA_BROKERS"  = "127.0.0.1:9092"
    "AUTH_HOSTS"     = "http://127.0.0.1:8081"
    "USER_HOSTS"     = "http://127.0.0.1:8085"
    "CHAT_HOSTS"     = "http://127.0.0.1:8082"
    "NEARBY_HOSTS"   = "http://127.0.0.1:8088"
    "PRES_HOSTS"     = "http://127.0.0.1:8084"
    "MEDIA_HOSTS"    = "http://127.0.0.1:8086"
    "COMPLIANCE_HOSTS" = "http://127.0.0.1:8087"
}

$services = @(
    @{ Name="auth";         Binary="bin\auth.exe";         Port="8081"; ExtraEnv=@{} },
    @{ Name="user";         Binary="bin\user.exe";         Port="8085"; ExtraEnv=@{} },
    @{ Name="chat";         Binary="bin\chat.exe";         Port="8082"; ExtraEnv=@{} },
    @{ Name="nearby";       Binary="bin\nearby.exe";       Port="8088"; ExtraEnv=@{} },
    @{ Name="presence";     Binary="bin\presence.exe";     Port="8084"; ExtraEnv=@{} },
    @{ Name="notification"; Binary="bin\notification.exe"; Port="8087"; ExtraEnv=@{} },
    @{ Name="media";        Binary="bin\media.exe";        Port="8086"; ExtraEnv=@{} },
    @{ Name="gateway";      Binary="bin\gateway.exe";      Port="8090"; ExtraEnv=@{} }
)

$logDir = Join-Path $ROOT "logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

foreach ($svc in $services) {
    $bin = Join-Path $ROOT $svc.Binary
    if (-not (Test-Path $bin)) {
        Write-Host "  SKIP: $($svc.Name) binary not found at $bin" -ForegroundColor Yellow
        continue
    }

    $logFile = Join-Path $logDir "$($svc.Name).log"
    $port    = $svc.Port
    $name    = $svc.Name

    $job = Start-Job -Name $name -ScriptBlock {
        param($bin, $port, $commonEnv, $extraEnv, $logFile)
        $allEnv = $commonEnv + $extraEnv
        foreach ($k in $allEnv.Keys) { [System.Environment]::SetEnvironmentVariable($k, $allEnv[$k]) }
        [System.Environment]::SetEnvironmentVariable("PORT", $port)
        & $bin *>> $logFile 2>&1
    } -ArgumentList $bin, $port, $commonEnv, $svc.ExtraEnv, $logFile

    Write-Host "  Started $name (port $port) as job $($job.Id) → $logFile" -ForegroundColor Green
}

Write-Host ""
Write-Host "Waiting 4 seconds for services to initialize..." -ForegroundColor Cyan
Start-Sleep -Seconds 4

Write-Host ""
Write-Host "=== Health Checks ===" -ForegroundColor Cyan

$checks = @(
    @{ Name="Gateway";  Url="http://127.0.0.1:8090/healthz" },
    @{ Name="Auth";     Url="http://127.0.0.1:8081/healthz" },
    @{ Name="User";     Url="http://127.0.0.1:8085/healthz" },
    @{ Name="Chat";     Url="http://127.0.0.1:8082/healthz" },
    @{ Name="Nearby";   Url="http://127.0.0.1:8083/healthz" },
    @{ Name="Presence"; Url="http://127.0.0.1:8084/healthz" }
)

foreach ($c in $checks) {
    try {
        $r = Invoke-WebRequest -Uri $c.Url -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        Write-Host "  ✅ $($c.Name): HTTP $($r.StatusCode)" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ $($c.Name): $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== ADB Reverse Tunnel ===" -ForegroundColor Cyan
adb reverse tcp:8090 tcp:8090 2>&1 | ForEach-Object { Write-Host "  $_" }
adb devices 2>&1 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "Gateway listening on http://127.0.0.1:8090" -ForegroundColor Green
Write-Host "Android devices connect via adb reverse tcp:8090 tcp:8090" -ForegroundColor Green
Write-Host ""
Write-Host "View logs: Get-Content logs\gateway.log -Wait" -ForegroundColor Cyan
Write-Host "Stop all:  .\start-local.ps1 -Stop" -ForegroundColor Cyan
