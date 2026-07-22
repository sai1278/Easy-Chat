# Kubernetes Platform Deployment & Infrastructure Audit Report

**Deployment Date:** July 22, 2026  
**Lead Evaluators:** Google Principal Cloud Platform Engineer, Kubernetes Platform Engineer, and Google SRE  
**Target Cluster:** Kubernetes Staging / Production Cluster (`easychat-production`)  
**Helm Chart Reference:** [`infrastructure/helm/easychat`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat)  
**Kustomize Reference:** [`infrastructure/kubernetes/production/kustomization.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/kubernetes/production/kustomization.yaml)

---

## Executive Summary

### Final Deployment Certification: **BLOCKED**

A Kubernetes deployment audit was initiated to provision the complete Nearby Connect platform (API Gateway, Auth, User, Presence, Chat, Nearby, Notification, Media, Compliance, DR Controller, PostgreSQL, Redis, Kafka, and the Observability stack) onto a target Kubernetes cluster using Helm and Kustomize.

However, deployment execution is **BLOCKED** because:
1. **Kubernetes Control Plane Offline:** `kubectl cluster-info` failed with `dial tcp 127.0.0.1:6443: connectex: No connection could be made because the target machine actively refused it`.
2. **Helm Binary Missing on PATH:** `helm` CLI tool is not installed on system PATH.

*Note:* Local Docker infrastructure containers (`nearby-postgres`, `nearby-redis`, `nearby-kafka`) are running and healthy on the host workstation.

Per Google SRE Deployment Policy:
* Do **NOT** fabricate Kubernetes pod statuses or service IPs.
* Capture **EXACT** `kubectl` and `helm` command outputs.
* Report **ONLY** observed deployment evidence.

---

## 1. Cluster & Runtime Inspection Evidence

### A. Kubernetes Cluster API Connection Test
```powershell
$ kubectl cluster-info
Unable to connect to the server: dial tcp 127.0.0.1:6443: connectex: No connection could be made because the target machine actively refused it.
```
* **Result:** **FAIL / UNREACHABLE** — Kubernetes API server at `127.0.0.1:6443` is offline.

### B. Helm CLI Tooling Verification
```powershell
$ helm version
helm : The term 'helm' is not recognized as the name of a cmdlet, function, script file, or operable program.
```
* **Result:** **FAIL / MISSING** — `helm` command-line binary is not installed on PATH.

### C. Host Docker Infrastructure Status (`docker compose ps`)
```powershell
$ docker compose ps
NAME              IMAGE                           STATUS                   PORTS
nearby-kafka      apache/kafka:3.7.0              Up 5 minutes (healthy)   0.0.0.0:9092->9092/tcp
nearby-postgres   postgis/postgis:16-3.4-alpine   Up 5 minutes (healthy)   0.0.0.0:54322->5432/tcp
nearby-redis      redis:7.2-alpine                Up 5 minutes (healthy)   0.0.0.0:6379->6379/tcp
```
* **Result:** **HEALTHY** — Core data stores (PostgreSQL 16, Redis 7.2, Kafka 3.7) are operational in host Docker.

---

## 2. Resource Deployment Verification Matrix

| Resource Category | Target Scope | Manifest Location | Deployment Status | Observed Evidence |
| :--- | :--- | :--- | :---: | :--- |
| **Namespaces** | `easychat-prod`, `easychat-monitoring` | Helm `values.yaml` | **BLOCKED** | K8s API server unreachable |
| **Helm Releases** | `easychat` Helm release | [`infrastructure/helm/easychat`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat) | **BLOCKED** | `helm` binary missing on PATH |
| **Application Pods** | Gateway, Auth, User, Presence, Nearby, Chat, Notification, Media | [`infrastructure/kubernetes/production/deployments.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/kubernetes/production/deployments.yaml) | **BLOCKED** | K8s API server unreachable |
| **Services & ClusterIPs** | 10 Microservice ClusterIPs | [`infrastructure/kubernetes/production/services.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/kubernetes/production/services.yaml) | **BLOCKED** | K8s API server unreachable |
| **Ingress & Routing** | NGINX Ingress Controller | [`infrastructure/kubernetes/production/ingress.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/kubernetes/production/ingress.yaml) | **BLOCKED** | K8s API server unreachable |
| **TLS Certificates** | cert-manager ClusterIssuer | Helm `ingress.yaml` template | **BLOCKED** | K8s API server unreachable |
| **Autoscaling (HPA)** | CPU / Memory HPA policies | [`infrastructure/kubernetes/production/hpa.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/kubernetes/production/hpa.yaml) | **BLOCKED** | K8s API server unreachable |
| **Monitoring Stack** | Prometheus & ServiceMonitors | [`infrastructure/observability/prometheus`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/observability/prometheus) | **BLOCKED** | K8s API server unreachable |
| **Logging Stack** | Loki & Promtail DaemonSets | [`infrastructure/observability/loki`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/observability/loki) | **BLOCKED** | K8s API server unreachable |
| **Tracing Stack** | OpenTelemetry & Tempo | Observability manifests | **BLOCKED** | K8s API server unreachable |

---

## 3. Remaining Issues & Blockers

1. **Kubernetes Control Plane Inactive:** Docker Desktop Kubernetes, Minikube, or GKE/EKS cluster control plane must be started.
2. **Helm Binary Provisioning:** Install Helm v3 binary on the execution host (`winget install Helm.Helm` or `choco install kubernetes-helm`).

---

## 4. Remediation Action Plan

To unblock the Kubernetes deployment:

1. **Install Helm:**
   ```powershell
   winget install Helm.Helm
   ```
2. **Start Kubernetes Control Plane:**
   ```bash
   minikube start --cpus=4 --memory=8192
   ```
3. **Deploy via Helm Chart:**
   ```bash
   helm install easychat infrastructure/helm/easychat -n easychat-prod --create-namespace
   ```
4. **Deploy Observability Stack:**
   ```bash
   kubectl apply -f infrastructure/observability/prometheus/prometheus.yml
   ```

---

## 5. Final Deployment Certification

### Final Certification Status: **BLOCKED**

**Reason:**  
Deployment cannot proceed because the Kubernetes control plane (`127.0.0.1:6443`) is offline and the `helm` command-line tool is missing from the system PATH. All deployment manifests (`deployments.yaml`, `hpa.yaml`, `ingress.yaml`, `Chart.yaml`) are fully implemented and ready for execution once the cluster is online.
