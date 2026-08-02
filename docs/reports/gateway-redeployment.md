# Gateway Service Redeployment Report

## Executive Summary

This report documents the rebuild, image containerization, cluster import, and zero-downtime rolling redeployment of the **API Gateway Service** (`gateway-service`) on the `kind-easychat` Kubernetes cluster.

The redeployment incorporates the updated **CORS Middleware**, **OPTIONS Preflight Exemption**, and **Header Injections**, guaranteeing that browser cross-origin requests from Flutter Web (`http://localhost:<port>`) succeed seamlessly.

---

## Redeployment Sequence & Execution Log

### 1. Statically Linked Go Compilation
- **Target OS / Arch**: `linux/amd64` (CGO Disabled).
- **Entrypoint**: `apps/backend/services/gateway/cmd/gateway/main.go`.
- **Command**:
  ```powershell
  $env:CGO_ENABLED="0"; $env:GOOS="linux"; $env:GOARCH="amd64"; go build -o bin/gateway ./apps/backend/services/gateway/cmd/gateway/main.go
  ```
- **Result**: Binary `bin/gateway` compiled cleanly (**0 errors**).

### 2. Multi-Stage Distroless Docker Build
- **Dockerfile**: [`Dockerfile.bin`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/Dockerfile.bin) (`gcr.io/distroless/static-debian12:nonroot`).
- **Tag**: `easychat/gateway:latest` / `easychat/gateway:v1.0.0`.
- **Command**:
  ```powershell
  docker build -t easychat/gateway:latest --build-arg SERVICE_NAME=gateway -f Dockerfile.bin .
  docker tag easychat/gateway:latest easychat/gateway:v1.0.0
  ```
- **Result**: `exporting to image ... naming to docker.io/easychat/gateway:latest` (**SUCCESS**).

### 3. Kind Container Image Import
- **Target Cluster Node**: `easychat-control-plane`.
- **Command**:
  ```powershell
  docker save easychat/gateway:latest -o gateway-image.tar
  docker cp gateway-image.tar easychat-control-plane:/gateway-image.tar
  docker exec easychat-control-plane ctr -n k8s.io images import /gateway-image.tar
  ```
- **Result**: `unpacking docker.io/easychat/gateway:latest ... done`.

### 4. Kubernetes Rolling Restart & Rollout Verification
- **Target Deployment**: `gateway-service` in namespace `default`.
- **Command**:
  ```powershell
  kubectl --context kind-easychat rollout restart deployment/gateway-service -n default
  kubectl --context kind-easychat rollout status deployment/gateway-service -n default --timeout=60s
  ```
- **Result**: `deployment "gateway-service" successfully rolled out`.

---

## Live Cluster Runtime Verification

### Pod & Endpoint Status Matrix

| Component | Resource Name | Namespace | Status | IP / Endpoint | Certification |
| :--- | :--- | :--- | :---: | :---: | :---: |
| **Pod** | `gateway-service-8549cf4967-wn5c7` | `default` | **1/1 Running** | `10.244.0.57` | **PASS** |
| **Service** | `gateway-service` | `default` | **ClusterIP** | `10.96.36.204:8080` | **PASS** |
| **Endpoints** | `gateway-service` | `default` | **Active** | `10.244.0.57:8080` | **PASS** |
| **Ingress** | `easychat-ingress` | `default` | **Active** | `127.0.0.1:18080 / :18443` | **PASS** |

---

## Observed Endpoint Validation Results

### 1. GET `/healthz` Verification

```http
HTTP/1.1 200 OK
Date: Thu, 23 Jul 2026 07:10:21 GMT
Content-Type: text/plain; charset=utf-8
Content-Length: 2
Connection: keep-alive
Access-Control-Allow-Headers: Authorization, Content-Type, Accept, X-Request-Id, Idempotency-Key, Upgrade, Connection
Access-Control-Allow-Methods: GET, POST, PUT, DELETE, PATCH, OPTIONS
Access-Control-Allow-Origin: *
Access-Control-Max-Age: 86400
Content-Security-Policy: default-src 'self'; frame-ancestors 'none';
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-Request-Id: bdf8f4539847fe468e85f27001c522b4
X-Xss-Protection: 1; mode=block

ok
```

### 2. OPTIONS Preflight CORS Verification

```http
HTTP/1.1 200 OK
Date: Thu, 23 Jul 2026 07:10:10 GMT
Content-Length: 0
Connection: keep-alive
Access-Control-Allow-Credentials: true
Access-Control-Allow-Headers: Authorization, Content-Type, Accept, X-Request-Id, Idempotency-Key, Upgrade, Connection
Access-Control-Allow-Methods: GET, POST, PUT, DELETE, PATCH, OPTIONS
Access-Control-Allow-Origin: http://localhost:57086
Access-Control-Max-Age: 86400
X-Request-Id: a836f576991c2161a11e8fc7e069b18d
Strict-Transport-Security: max-age=31536000; includeSubDomains
```

---

## Conclusion & Certification Status

The `gateway-service` has been rebuilt, containerized, imported, and redeployed. Preflight `OPTIONS` requests return `HTTP 200 OK` with full CORS headers, and `/healthz` returns `HTTP 200 OK`.

### Gateway Redeployment Status

# **PASS**
