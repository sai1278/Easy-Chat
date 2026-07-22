# Nearby Connect — Beta Release Plan & Operational Framework

**Release Version:** 1.0.0-beta.1  
**Lead Authors:** Google Principal Release Manager, Technical Program Manager (TPM), and SRE  
**Target Application:** Nearby Connect Platform (Go Backend Microservices + Flutter Mobile/Desktop/Web)  
**Authoritative Evidence:** Generated Project Reports in [`docs/reports/`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports)

---

## 1. Executive Summary

This document establishes the official Beta Release Plan and operational governance for the Nearby Connect platform. 

The core software architecture is highly mature:
* **Backend Microservices:** 10/10 Go services are 100% complete and passing unit tests (`go test ./...`) with 0 tech debt ([`backend-completion-audit.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/backend-completion-audit.md)).
* **Protobuf & gRPC Contracts:** 8/8 Proto schemas and 20/20 gRPC endpoints verified ([`grpc-audit.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/grpc-audit.md)).
* **Cross-Platform Client:** Android release APK (`app-release.apk`, 23.6MB) and Web bundle (`build\web`) are 100% compiled and certified ([`frontend-production-certification.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/frontend-production-certification.md)).
* **Real-Device Physical Hardware:** 19/19 E2E scenarios passed on physical Android smartphones (vivo V2545 on Android 16 & vivo 1935 on Android 10) ([`real-device-validation.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/real-device-validation.md)).
* **Load Testing Toolchains:** Grafana k6 (`v0.52.0`) and Locust (`v2.46.1`) installed and dry-run certified ([`load-generator-installation-report.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/load-generator-installation-report.md)).

However, per the Production Readiness Review (PRR) ([`final-production-certification.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/final-production-certification.md)), the target Kubernetes staging cluster is currently offline. As a result, live production load testing, Red Team penetration testing, and Chaos Engineering remain **BLOCKED**.

**Beta Status:** Controlled Beta Readiness Framework Established; Release pending target staging cluster deployment.

---

## 2. Release Scope

### Features Included in Beta 1.0:
- **Anonymous Authentication:** PKCE OIDC authorization challenge & JWT token generation.
- **Presence Tracking:** Adaptive battery-optimized heartbeat polling (`BatteryOptimizer`).
- **Nearby Proximity Discovery:** Uber H3 hexagonal spatial indexing (`8a2a1072b59ffff`) with radius filtering (50m, 100m, 150m).
- **Instant Messaging:** WebSocket packet multiplexing (`MESSAGE`, `RECEIPT`, `TYPING`), write-through Isar local caching, and offline queueing.
- **Media Upload & Scanning:** Presigned S3 upload URLs & ClamAV stream malware scanning.
- **Cross-Platform Apps:** Native Android (APK) & Web (Chrome / Edge) user interfaces.

### Features Explicitly Excluded from Beta 1.0:
- Windows Desktop C++ Native Runner (Deferred until Visual Studio C++ workload is installed on build host).
- Public Unrestricted Cloud Access (Deferred until live penetration testing and load sweeps unblock).

---

## 3. Beta Entry Criteria

Before initiating Beta user onboarding, the following mandatory entry criteria must be met:

1. **Target Staging Environment Deployment:** Minikube, Kind, or GKE cluster online with API Gateway reachable on HTTP `:8090` ([`kubernetes-deployment.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/kubernetes-deployment.md)).
2. **Live Load Testing Unblocked:** Successful execution of k6 load suite under 100, 500, 1000, and 5000 VUs with P95 latency $< 200\text{ ms}$ ([`production-load-test-results.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-load-test-results.md)).
3. **Live Penetration Testing Unblocked:** Red Team security scan completed with 0 Critical/High vulnerabilities ([`security-certification.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/security-certification.md)).

---

## 4. Release Checklist

| Domain | Checklist Item | Verification Reference | Status |
| :--- | :--- | :--- | :---: |
| **Infrastructure** | Distroless container images & Helm charts | [`docker-deployment-validation.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/docker-deployment-validation.md) | **PASS** |
| **Deployment** | Kubernetes API server online | [`kubernetes-deployment.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/kubernetes-deployment.md) | **BLOCKED** |
| **Database** | PostgreSQL 16 schema & PostGIS extensions | [`backend-completion-audit.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/backend-completion-audit.md) | **PASS** |
| **Authentication** | OIDC PKCE flow & `FlutterSecureStorage` | [`frontend-backend-integration.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/frontend-backend-integration.md) | **PASS** |
| **Notifications** | Kafka `chat-events` consumer & push gateway | [`end-to-end-validation.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/end-to-end-validation.md) | **PASS** |
| **Monitoring** | Prometheus scrapers & Grafana dashboards | [`prometheus-metrics.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/performance/prometheus-metrics.md) | **PASS** |
| **Backups** | Redis AOF & Postgres WAL archiving | [`docker-deployment-validation.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/docker-deployment-validation.md) | **PASS** |
| **Documentation** | Operational runbooks & ADRs | [`performance-testing-runbook.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/performance/performance-testing-runbook.md) | **PASS** |
| **Support** | Incident escalation path & chat channels | [`beta-release.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/release/beta-release.md#9-incident-response-plan) | **PASS** |
| **Operations** | Disaster recovery & failover playbooks | [`final-production-validation.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/final-production-validation.md) | **PASS** |

---

## 5. Known Issues & Environmental Blockers

### A. Environmental Blockers:
- **ENV-01: Target Staging Cluster Offline:** Kubernetes API server at `127.0.0.1:6443` is currently offline, preventing live Helm deployment sweeps ([`kubernetes-deployment.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/kubernetes-deployment.md)).
- **ENV-02: Live Traffic Sweeps Halted:** Production load testing (`production-load-test-results.md`), penetration testing (`security-certification.md`), and chaos experiments (`chaos-validation.md`) are BLOCKED pending cluster start.

### B. Known Defects / Deferred Improvements:
- **DEF-01: Windows Desktop Toolchain Missing:** Host machine lacks Visual Studio 2022 C++ workload required for native Windows desktop builds ([`frontend-production-certification.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/frontend-production-certification.md)).

---

## 6. Risk Assessment & Mitigation Matrix

| Risk Level | Risk Description | Root Cause | Mitigation Strategy |
| :---: | :--- | :--- | :--- |
| **CRITICAL** | Production load testing & penetration testing unexecuted prior to Beta | Target staging environment offline | Spin up staging cluster (`docker-compose up` or `minikube start`) and execute k6 load test suite before Beta user onboarding. |
| **HIGH** | Unmonitored WebSocket disconnect spikes under high concurrency | Potential socket descriptor exhaustion | Enforce Kubernetes HPA pod autoscaling rules (`hpa.yaml`) and WebSocket heartbeat interval adjustments. |
| **MEDIUM** | Missing Windows Desktop binary | Host C++ toolchain absent | Distribute Web (Chrome) and Android (APK) clients for Beta tier 1; add Windows C++ builder to CI pipeline. |
| **LOW** | Background location battery drain | Continuous GPS polling | Enforced `BatteryOptimizer` duty cycle throttling based on peer density. |

---

## 7. Rollback Plan

### Rollback Triggers:
1. **Critical Latency Breach:** HTTP P95 latency $> 500\text{ ms}$ for $> 5\text{ minutes}$.
2. **Error Rate Spike:** 5xx HTTP error rate $> 2.0\%$.
3. **Data Loss Event:** Database corruption or unhandled write failures.

### Rollback Procedure:
1. **Traffic Redirection:** Route API Gateway traffic to previous stable version via NGINX Ingress canary switch (`canary-weight: 0`).
2. **Helm Rollback:**
   ```bash
   helm rollback easychat 1 -n easychat-prod
   ```
3. **Database Point-in-Time Recovery (PITR):** Restore PostgreSQL state from latest WAL archive backup if schema changes occurred.
4. **Data Integrity Verification:** Run `go test ./tests/...` verification suite against restored data store.

---

## 8. Monitoring & Observability Plan

* **Key Dashboards:** [`infrastructure/observability/grafana/dashboards/system_dashboard.json`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/observability/grafana/dashboards/system_dashboard.json)
* **Prometheus Alert Rules:** [`infrastructure/observability/prometheus/alerts.yml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/observability/prometheus/alerts.yml)
* **SLOs & Error Budgets:**
  * Availability SLO: `99.9%` (Error budget: 43 minutes/month).
  * Latency SLO: `95%` of requests $< 200\text{ ms}$.
* **On-Call Ownership:** Primary SRE On-Call via PagerDuty / Alertmanager webhook.

---

## 9. Incident Response Plan

| Severity Level | Response Time | Escalation Path | Communication Channel |
| :---: | :---: | :--- | :--- |
| **SEV-1 (Critical outage)** | $< 5\text{ mins}$ | Lead SRE + Engineering VP | `#incident-sev1` Slack / PagerDuty Call |
| **SEV-2 (Major degradation)**| $< 15\text{ mins}$ | Service Owner + On-Call SRE | `#incident-sev2` Slack |
| **SEV-3 (Minor issue)** | $< 2\text{ hours}$ | Component Developer | Jira Ticket / Slack |

---

## 10. Beta Success Metrics

* **Crash-Free Sessions:** $> 99.5\%$ on Android & Web.
* **Authentication Success Rate:** $> 99.9\%$.
* **Chat Message Delivery Success Rate:** $> 99.9\%$.
* **Nearby Proximity Discovery Rate:** $> 98.0\%$ within 150m radius.
* **API Availability:** $> 99.9\%$ HTTP 200 OK.
* **Target P95 Latency:** $< 200\text{ ms}$ (once live load test sweeps unblock).

---

## 11. Go / No-Go Checklist

| Prerequisite Item | Status | Justification & Report Reference |
| :--- | :---: | :--- |
| **Go Backend Services** | **PASS** | 10/10 services 100% complete & passing tests ([`backend-completion-audit.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/backend-completion-audit.md)) |
| **gRPC Architecture** | **PASS** | 20/20 RPC endpoints verified ([`grpc-audit.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/grpc-audit.md)) |
| **Flutter Client Apps** | **PASS** | Android APK & Web certified ([`frontend-production-certification.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/frontend-production-certification.md)) |
| **Real Hardware Testing** | **PASS** | 19/19 scenarios passed on physical Android devices ([`real-device-validation.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/real-device-validation.md)) |
| **Load Test Toolchains** | **PASS** | k6 v0.52.0 & Locust 2.46.1 installed & verified ([`load-generator-installation-report.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/load-generator-installation-report.md)) |
| **Kubernetes Staging Deployment** | **BLOCKED** | K8s control plane offline ([`kubernetes-deployment.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/kubernetes-deployment.md)) |
| **Production Load Testing** | **BLOCKED** | Target API Gateway unreachable ([`production-load-test-results.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-load-test-results.md)) |
| **Red Team Security Scans** | **BLOCKED** | Target API Gateway unreachable ([`security-certification.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/security-certification.md)) |
| **Chaos Engineering Scans** | **BLOCKED** | Target API Gateway unreachable ([`chaos-validation.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/chaos-validation.md)) |

---

## 12. Beta Release Recommendation

# **NO GO**
*(Pending Target Staging Environment Deployment and Completion of Live Load, Security, and Chaos Sweeps)*

### Recommendation Justification:
While software implementation, code quality, unit test coverage, cross-platform builds, and real-device physical hardware tests are 100% complete and passing, Google PRR governance prohibits releasing to Beta users while live load testing, penetration testing, and chaos validation remain **BLOCKED** due to an offline staging cluster. Once the target staging environment is brought online and live sweeps pass, Beta release approval will be granted immediately.
