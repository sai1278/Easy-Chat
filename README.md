# Nearby Connect Monorepo Workspace
**Enterprise Monorepo Infrastructure Specification**

Nearby Connect is a privacy-first, ephemeral, real-time proximity communication utility. This repository represents the complete monorepo structure enclosing Go microservices backend, Flutter client frontend, configuration matrices, and build system.

---

## 1. Prerequisites & Tool Pinned Versions

To guarantee deterministic, reproducible builds across developer workstations and CI runners, you must install the following tools:

| Tool | Version Target | Scope / Purpose |
| :--- | :--- | :--- |
| **Go Compiler** | `1.22.x` | Backend runtime & module compilation |
| **Flutter SDK** | `3.22.x` | Cross-platform client application framework |
| **protoc compiler** | `v25.x` | Protocol Buffer compiler base |
| **protoc-gen-go** | `v1.34.1` | Go Protobuf generation plugin |
| **protoc-gen-go-grpc**| `v1.4.0` | Go gRPC code generation plugin |
| **protoc-gen-dart** | `v3.2.0` | Dart Protobuf and gRPC generation plugin |
| **Docker** | `24.x+` | Container runtime engine |
| **Docker Compose** | `v2.x+` | Orchestrator for local system services |
| **GNU Make** | `3.81+` | Main interface command wrapper |

---

## 2. Directory Layout & Boundaries

```
.
├── .github/                  # CI/CD pipelines (GitHub Workflows)
├── apps/                     # Application projects
│   ├── backend/              # Go Microservices
│   │   ├── cmd/              # Microservice entrypoints (Auth, Chat, etc.)
│   │   ├── internal/         # Sealed private Go domain logic
│   │   └── internal/gen/     # Generated Protobuf stubs (Git Ignored)
│   └── frontend/             # Flutter Mobile Client
│       ├── lib/              # View and State presentation layer
│       └── lib/gen/          # Generated Dart Protobuf code (Git Ignored)
├── proto/                    # Central Protocol Buffer definition contracts
├── scripts/                  # Automated helper utilities
├── docker-compose.yml        # Local backing services environment (DB, Redis, Kafka)
├── go.work                   # Multi-module Go Workspace config
└── Makefile                  # Task management interface
```

---

## 3. Developer Quick Start

Bootstrap your environment, compile schemas, and verify builds with local automation targets:

### Step 1: Clone the Repository
Clone the codebase to your local directory.

### Step 2: Initialize & Install Plugins
Verify that Go, Flutter, and `protoc` are installed on your path. Then execute:
```bash
make setup
```
This runs `scripts/setup_dev.sh` to install the pinned versions of `protoc-gen-go`, `protoc-gen-go-grpc`, and `protoc-gen-dart`.

> [!NOTE]
> Make sure your shell PATH environment variable includes your language package cache bin directories:
> - Go: `$HOME/go/bin` or `%USERPROFILE%\go\bin`
> - Dart: `$HOME/.pub-cache/bin` or `%APPDATA%\Pub\Cache\bin`

### Step 3: Compile API Definitions
Generate the gRPC stubs for Go and Dart client-server messaging:
```bash
make proto
```
This writes Go files into `apps/backend/internal/gen/` and Dart files into `apps/frontend/lib/gen/`. These folders are configured in `.gitignore` and are never committed to git.

### Step 4: Run Verifications
Simulate a complete CI test cycle locally:
```bash
make ci
```
This sequentially runs validation formatting (`make fmt`), linters (`make lint`), and testing (`make test`) across both codebases.

### Step 5: Run Local Dependencies
Start the Docker backing services (PostgreSQL, Redis, Kafka, ZooKeeper) in the background:
```bash
make up
```
To spin down the containers, run:
```bash
make down
```

---

## 4. Key Developer Commands Reference

*   `make setup`: Checks prerequisites, retrieves plugins.
*   `make proto`: Re-generates stubs from `.proto` schemas.
*   `make fmt`: Runs `go fmt` and `flutter format`.
*   `make lint`: Runs code health static analysis checkers (`go vet` and `flutter analyze`).
*   `make test`: Executes tests.
*   `make backend`: Compiles microservice targets in `apps/backend/bin/`.
*   `make mobile`: Compiles Flutter web bundle target.
*   `make docker`: Build project images using Compose.
*   `make clean`: Resets the workspace, purging binary targets and generated caches.
