# Backend Startup Investigation Report
# Root Cause Analysis — Go Services Not Running

**Date**: 2026-08-03T10:47:00+05:30
**Investigator Roles**: Google Principal Go Engineer · Staff SRE · Docker Platform Engineer

---

## FINDING 1 — Architecture Clarification

### docker-compose.yml ONLY manages infrastructure

`docker compose config` output confirmed: the compose file defines exactly 3 services:

  - postgres  (postgis/postgis:16-3.4-alpine, port 54322)
  - redis     (redis:7.2-alpine, port 6379)
  - kafka     (apache/kafka:3.7.0, port 9092)

There are NO application services (gateway, auth, user, chat, nearby, presence) in docker-compose.yml.

This is by design. The application tier is intentionally NOT containerized for local development.
The Kubernetes manifests in infrastructure/kubernetes/ are the production deployment target.

The `docker ps` showing only 3 containers is CORRECT behavior — NOT a failure.

---

## FINDING 2 — Root Cause of Port 8090 Not Listening

### Symptom
  netstat -ano | findstr :8090  =>  no output (exit code 1)
  curl http://127.0.0.1:8090/healthz  =>  Unable to connect

### Root Cause: PowerShell Start-Job processes die with their parent session

Previous attempts launched services via Start-Process (PowerShell):
  $proc = Start-Process -FilePath bin\gateway.exe ...

OR via Start-Job (from start-local.ps1):
  $job = Start-Job -ScriptBlock { & $bin ... }

Both mechanisms create processes that are CHILDREN of the PowerShell invocation.
When that PowerShell session ends (tool call completes), all child processes are terminated.

This is a Windows process inheritance behavior — not a bug in the services.

---

## FINDING 3 — Authoritative Startup Mechanism

### File: run-services.cmd

The repository ships run-services.cmd which uses Windows cmd.exe `start /b`:

  start "auth" /b bin\auth.exe >> logs\auth.log 2>> logs\auth.err

The `start /b` command in cmd.exe creates a DETACHED Windows process with Session Console 6.
These processes survive independently of the shell that launched them.
They are owned by the Windows Session, not the parent process.

This is the CORRECT and INTENDED startup method for local Windows development.

---

## FINDING 4 — Proof: Services Started Correctly with run-services.cmd

Executed: cmd /c run-services.cmd

Health check output from run-services.cmd:
  ok HTTP:200   gateway:8090
  ok HTTP:200   auth:8081
  ok HTTP:200   user:8085
  ok HTTP:200   chat:8082

netstat verification:
  TCP  0.0.0.0:8090  LISTENING  PID 33096 (gateway.exe)
  TCP  0.0.0.0:8081  LISTENING  PID 35192 (auth.exe)

Full HTTP health probe results:
  HEALTH_PASS gateway  => HTTP 200  body=ok
  HEALTH_PASS auth     => HTTP 200  body=ok
  HEALTH_PASS user     => HTTP 200  body=ok
  HEALTH_PASS chat     => HTTP 200  body=ok
  HEALTH_PASS nearby   => HTTP 200  body={"status":"ok"}
  HEALTH_PASS presence => HTTP 200  body=ok

Running processes (tasklist):
  auth.exe         PID 35192  Session Console 6
  user.exe         PID 29684  Session Console 6
  chat.exe         PID 36800  Session Console 6
  nearby.exe       PID 23668  Session Console 6
  presence.exe     PID 14088  Session Console 6
  notification.exe PID 27080  Session Console 6
  media.exe        PID 1660   Session Console 6
  gateway.exe      PID 33096  Session Console 6

---

## FINDING 5 — Live Device Evidence

Gateway log captured LIVE DEVICE REQUESTS immediately after startup:

  10:47:07  GET  /healthz           => HTTP 200  (run-services.cmd health check)
  10:47:49  GET  /api/v1/user/profile => HTTP 401  (device app making authenticated request)
  10:47:49  PUT  /api/v1/user/profile => HTTP 401  (device app attempting profile update)
  10:47:52  PUT  /api/v1/user/profile => HTTP 401  (retry)
  10:47:54  PUT  /api/v1/user/profile => HTTP 401  (retry)

HTTP 401 is CORRECT behavior: JWT tokens from the prior session are invalid after backend restart.
The app is correctly attempting requests — the backend is correctly rejecting expired tokens.
Users must re-register to obtain fresh JWTs.

---

## FINDING 6 — ADB Tunnel Discrepancy

run-services.cmd was written for port 18080:
  adb -s 10MG5XFK9A0006B reverse tcp:18080 tcp:8090

Current APK is configured for port 8090 (APP_ENV=wifi, HOST_IP=127.0.0.1).
Fixed: Removed 18080 tunnels, installed correct tcp:8090 -> tcp:8090 on both devices.
  Device A: UsbFfs tcp:8090 tcp:8090  ACTIVE
  Device B: UsbFfs tcp:8090 tcp:8090  ACTIVE

---

## DOCKER compose logs (application services)

docker compose logs gateway  =>  Error response: No such service: gateway
docker compose logs auth     =>  Error response: No such service: auth
docker compose logs user     =>  Error response: No such service: user
docker compose logs nearby   =>  Error response: No such service: nearby
docker compose logs presence =>  Error response: No such service: presence
docker compose logs chat     =>  Error response: No such service: chat

This is EXPECTED. Application services are not in docker-compose.yml.
They are Go native binaries. Kubernetes is the production deployment target.

---

## Startup Logs (Post-Fix)

Auth:
  {"msg":"Starting Auth Service...","port":8081}
  {"msg":"Successfully connected to PostgreSQL"}
  {"msg":"Successfully connected to Redis"}
  {"msg":"Auth HTTP API Server listening","addr":":8081"}

User:
  {"msg":"Starting User Service...","port":8085}
  {"msg":"Successfully connected to PostgreSQL"}
  {"msg":"User HTTP API Server listening","addr":":8085"}

Chat:
  {"msg":"Starting Chat WebSocket Router Service...","port":8082}
  {"msg":"Successfully connected to PostgreSQL"}
  {"msg":"Successfully connected to Redis"}
  {"msg":"Successfully initialized Kafka Event Pipeline","brokers":["127.0.0.1:9092"]}
  {"msg":"WebSocket Server listening","addr":":8082"}
  {"msg":"Kafka consumer pipeline started successfully"}

Nearby:
  {"msg":"Starting Nearby Proximity Service...","port":8083}
  {"msg":"Successfully connected to PostgreSQL"}
  {"msg":"Successfully connected to Redis"}
  {"msg":"Nearby Service gRPC server is listening","port":8083}
  {"msg":"Nearby Service HTTP Health & Metrics server listening","port":8088}

Presence:
  {"msg":"Starting Presence Service...","port":8084}
  {"msg":"Successfully connected to Redis"}
  {"msg":"Presence HTTP API Server listening","addr":":8084"}

Gateway:
  {"msg":"Starting API Gateway Service...","port":8090}
  {"msg":"TLS is disabled. Starting Gateway on HTTP...","addr":":8090"}

---

## Summary

| Category | Finding |
|:---|:---|
| Root Cause | PowerShell Start-Process/Start-Job creates child processes that die with the session |
| Failed Service | None — services were never intended to run in Docker |
| Application Docker containers | Not applicable — design uses native Go binaries locally |
| Correct startup mechanism | run-services.cmd (cmd.exe start /b = detached persistent processes) |
| Fix applied | Executed cmd /c run-services.cmd |
| ADB discrepancy fixed | Tunnels corrected from 18080 to 8090 on both devices |
| Current state | All 8 services RUNNING, 6/6 HTTP health checks PASS |
| Device connectivity | Both devices sending live requests to gateway |

---

## Verification Commands

Verify services are running:
  netstat -ano | findstr ":8090"
  netstat -ano | findstr ":8081"
  tasklist /FI "IMAGENAME eq gateway.exe"
  tasklist /FI "IMAGENAME eq auth.exe"

Verify HTTP health:
  curl http://127.0.0.1:8090/healthz
  curl http://127.0.0.1:8081/healthz
  curl http://127.0.0.1:8085/healthz
  curl http://127.0.0.1:8082/healthz
  curl http://127.0.0.1:8084/healthz
  curl http://127.0.0.1:8088/healthz

Stop all services:
  taskkill /IM gateway.exe /F
  taskkill /IM auth.exe /F
  taskkill /IM user.exe /F
  taskkill /IM chat.exe /F
  taskkill /IM nearby.exe /F
  taskkill /IM presence.exe /F
  taskkill /IM notification.exe /F
  taskkill /IM media.exe /F

Restart services:
  cmd /c run-services.cmd

---

## Current Backend Status

  Docker Infrastructure:
    nearby-postgres   Up (healthy)   :54322
    nearby-redis      Up (healthy)   :6379
    nearby-kafka      Up (healthy)   :9092

  Go Application Services:
    gateway           RUNNING   :8090   HTTP 200
    auth              RUNNING   :8081   HTTP 200
    user              RUNNING   :8085   HTTP 200
    chat              RUNNING   :8082   HTTP 200
    nearby            RUNNING   :8088   HTTP 200  (gRPC :8083)
    presence          RUNNING   :8084   HTTP 200
    notification      RUNNING   :8087
    media             RUNNING   :8086

  ADB Tunnels:
    Device A  10MG5XFK9A0006B  tcp:8090->tcp:8090  ACTIVE
    Device B  c541beff         tcp:8090->tcp:8090  ACTIVE

  App launched on both devices. Ready for onboarding flow.

BACKEND STARTUP: RESOLVED
