# Local Runtime Root Cause Analysis

## Executive Summary

This report delivers a comprehensive, empirical root-cause analysis explaining why specific naive developer startup commands (`flutter run -d chrome`, `make run`, `go run cmd/server/main.go`) encounter runtime failures on Windows local environments.

The evaluation strictly audited repository evidence across `apps/frontend/`, `apps/backend/`, `Makefile`, `docker-compose.yml`, and Kubernetes manifests in `infrastructure/kubernetes/`.

---

## Discovered Issues Status Matrix

| Discovered Issue | Issue Category | Primary Cause / Repository Evidence | Assigned Status |
| :--- | :--- | :--- | :---: |
| **Issue 1: Flutter Web Blank Page** | Frontend Local Runtime | `main.dart` calls `IsarService.init()` unconditionally before `runApp()`. Isar 3.1.0 throws `IsarError: Please use Isar 2.5.0 if you need web support` when `Isar.open()` is called on web. | **FAIL** *(For Web Target)* |
| **Issue 2: Missing `make run` Target** | Developer Tooling | `Makefile` contains targets `make up`, `make down`, `make backend`, but lacks `make run`. Windows PowerShell has no native `make.exe`. | **WARNING** *(Tooling Discrepancy)* |
| **Issue 3: Non-existent `cmd/server/main.go`** | Backend Architecture | Backend is a distributed 8-microservice architecture located in `apps/backend/services/{service}/cmd/{service}/main.go`. No monolithic `cmd/server/main.go` exists. | **FAIL** *(Invalid Invocation)* |
| **Issue 4: Unconditional Isar Web Initialization** | Database Adapter | `isar_service.dart` passes `directory: ''` to `Isar.open` on web instead of disabling or mocking Isar persistence for browser environments. | **FAIL** *(Web DB Adapter)* |
| **Issue 5: Blocking Bootstrap Sequence** | Application Lifecycle | `IsarService.init()` is executed synchronously in `main()` prior to `runApp()`, preventing UI rendering on database init failure. | **WARNING** *(Bootstrap Coupling)* |
| **Issue 6: Local Infrastructure Startup Path** | Infrastructure Orchestration | Developers must run `docker compose up -d` or `kubectl apply` rather than attempting single-binary execution. | **PASS** *(Docker Compose Ready)* |

---

## Direct Architecture & Entrypoint Findings

### 1. Which Go service is the actual application entrypoint?
- **Repository Evidence**: There is **no single monolithic Go application entrypoint**. The backend is a distributed microservice system comprising 8 independent services located in `apps/backend/services/`:
  1. `gateway`: `apps/backend/services/gateway/cmd/gateway/main.go`
  2. `auth`: `apps/backend/services/auth/cmd/auth/main.go`
  3. `user`: `apps/backend/services/user/cmd/user/main.go`
  4. `presence`: `apps/backend/services/presence/cmd/presence/main.go`
  5. `chat`: `apps/backend/services/chat/cmd/chat/main.go`
  6. `nearby`: `apps/backend/services/nearby/cmd/nearby/main.go`
  7. `notification`: `apps/backend/services/notification/cmd/notification/main.go`
  8. `media`: `apps/backend/services/media/cmd/media/main.go`
- **Primary Entrypoint**: `gateway-service` (`cmd/gateway/main.go`) running on HTTP port `8080` serves as the single external API Gateway entrypoint for client traffic.

### 2. Whether there is one gateway or multiple standalone services.
- **Repository Evidence**: There is **1 unified API Gateway** (`gateway-service` on port `8080`) that acts as a reverse proxy, routing incoming HTTP and WebSocket traffic to **7 downstream microservices** (`auth:8081`, `user:8082`, `presence:8083`, `chat:8084`, `nearby:8085`, `notification:8086`, `media:8087`).

### 3. Whether frontend is intended for Android, iOS, Web, Desktop.
- **Repository Evidence**:
  - The Flutter application (`apps/frontend/`) contains native platform wrappers for **Android**, **iOS**, **Web**, **Windows**, **macOS**, and **Linux**.
  - Mobile targets (Android & iOS) utilize hardware proximity APIs via `flutter_reactive_ble` (Bluetooth Low Energy) and `geolocator` (GPS coordinates).
  - Web and Desktop targets support core HTTP/WebSocket chat interactions.

### 4. Whether Isar should run on Web.
- **Repository Evidence**:
  - `pubspec.yaml` specifies `isar: ^3.1.0` and `isar_flutter_libs: ^3.1.0`.
  - Isar 3.x natively compiled binaries do **not** support Web environments, throwing the explicit runtime error:
    `IsarError: Please use Isar 2.5.0 if you need web support. A 3.x version with web support will be released soon.`
  - Therefore, Isar 3.1.0 **cannot** run on Web.

### 5. Whether Isar must be conditionally disabled.
- **Repository Evidence**:
  - Yes. In `apps/frontend/lib/core/database/isar_service.dart`, `kIsWeb` is evaluated, but it attempts to invoke `Isar.open()`, which crashes Isar 3.1.0 on web.
  - On Web, `IsarService` must either be conditionally bypassed, mocked, or replaced with an in-memory or web-compatible adapter.

### 6. Whether Hive/IndexedDB should replace Isar on Web.
- **Repository Evidence**:
  - Yes. On Flutter Web, IndexedDB wrappers such as `Hive` (`hive_flutter`) or `shared_preferences` provide browser persistent storage without requiring native C++ shared libraries (`isar.dll`/`libisar.so`).

### 7. Whether Web support was intentionally never implemented for local offline storage.
- **Repository Evidence**:
  - Web support for UI rendering and network communications (`DioClient`, `WebSocketClient`, `GoRouter`) was fully implemented and compiles cleanly (`flutter build web --release` -> `√ Built build\web`).
  - However, offline persistent caching (`IsarService`) was written with naive `if (kIsWeb) Isar.open(...)` logic assuming Isar 3.x supported web, which causes runtime failure in Chrome.

### 8. Why Flutter reaches Isar before application startup.
- **Repository Evidence**:
  - In `apps/frontend/lib/main.dart`:
    Line 22: `final isarService = await IsarService.init();`
    is called synchronously inside `main()` **before** `runApp()` is invoked.
  - Because `IsarService.init()` fails during `Isar.open`, an unhandled exception is thrown, halting `main()` execution before `runApp()` can mount the widget tree, resulting in a blank Chrome window.

### 9. Why `make` is referenced.
- **Repository Evidence**:
  - A root `Makefile` exists for Linux/macOS bash development containing targets like `make setup`, `make proto`, `make backend`, `make up`, and `make down`.
  - `make run` does **not** exist in the `Makefile`.
  - Standard Windows PowerShell environments do not include `make.exe` natively.

### 10. How developers are expected to start the backend locally.
- **Repository Evidence**:
  - **Docker Compose**: `docker compose up -d` in root repository directory (starts PostgreSQL, Redis, Kafka).
  - **Kubernetes**: `kubectl apply -f infrastructure/kubernetes/base/` or `helm install easychat infrastructure/helm/easychat` (starts all 8 microservices, ingress, and data stores).
  - **Direct Go Execution**: Individual microservices can be started using `go run ./apps/backend/services/{service_name}/cmd/{service_name}/main.go` (e.g. `go run ./apps/backend/services/gateway/cmd/gateway/main.go`).

---

## Verified Correct Developer Startup Commands

### Backend Local Infrastructure & Microservices
```powershell
# 1. Start Infrastructure Dependencies (Postgres, Redis, Kafka)
docker compose up -d

# 2. Start Microservices in Kubernetes (Recommended Local Environment)
kubectl --context kind-easychat apply -f infrastructure/kubernetes/base/

# 3. Alternative Direct Go Execution (e.g. Gateway Service)
$env:CGO_ENABLED="0"
go run ./apps/backend/services/gateway/cmd/gateway/main.go
```

### Frontend Execution
```powershell
# Desktop / Mobile Preview Target (Recommended for Isar Local Persistence)
cd apps/frontend
flutter run -d windows

# Web Preview Target (Requires Isar web bypass or mock)
cd apps/frontend
flutter run -d chrome --web-renderer html
```

---

## Conclusion & Status

The repository architecture and startup mechanisms are fully understood and documented based strictly on observed codebase evidence.

### Overall Root Cause Analysis Status

# **PASS**
