# Master Testing & Verification Playbook

This document details the multi-layered testing strategy designed to validate system stability at scale, failure recovery, and real-time client optimizations.

---

## 1. Unit & Integration Testing
*   **Backend Services**: Table-driven tests leveraging standard `testing` libraries and mock interfaces. Integration suites configure transient local Postgres and Redis adapters.
*   **Frontend Client**: Widget and unit tests utilizing Mockito and Riverpod state controllers.

---

## 2. API Contract & Serialization Checks
Enforces protobuf serialization integrity between the mobile clients and gateway endpoints.
*   **Protobuf Specs**: Schema versioning under `proto/nearby/v1/`.
*   **Compilations**: Protoc compiler verifies that auto-generated Go structures and Dart clients match specification contracts.

---

## 3. Load & Stress Testing (k6)
Validates backend performance under high connection loads and traffic spikes.
*   **Location**: `tests/load/load_test.js`
*   **Execution**:
    ```bash
    k6 run tests/load/load_test.js
    ```
*   **Scenarios**: Simulates parallel clients connecting via WebSockets, executing HTTP logins, querying locations, and uploading attachments.
*   **SLA Bounds**: 95% of HTTP calls must complete in < 200ms.

---

## 4. Chaos Engineering (Chaos Mesh)
Verifies microservice resilience by introducing network degradation, latency, and sudden pod termination faults.
*   **Setup**: Deploy Chaos Mesh on the Kubernetes cluster.
*   **Latency Injection**:
    ```bash
    kubectl apply -f tests/chaos/network_chaos.yaml
    ```
    *   Simulates 150ms latency to Redis to verify application timeout recovery and write-through caching.
*   **Pod Failure Injection**:
    ```bash
    kubectl apply -f tests/chaos/pod_failure_chaos.yaml
    ```
    *   Terminates gateway and chat pods randomly to verify that the NGINX Ingress controller successfully load-balances requests and that clients execute reconnect handshakes.

---

## 5. BLE/GPS Battery Optimization Verification
Tests location speed modifications to measure sensor duty cycle state changes on client devices.
*   **Location**: `tests/simulation/battery_optimizer_test.dart`
*   **Verification**: Simulates walking vs. stationary states, checking that the optimizer shifts GPS accuracy (high vs. low) and duty-cycles BLE scans (active vs. standby) to preserve battery power.
