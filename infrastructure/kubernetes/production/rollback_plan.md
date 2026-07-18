# SRE Operations Rollback Playbook

This document details the recovery plans, commands, and workflows required to handle deployment incidents and safely revert to stable revisions with zero downtime.

---

## 1. Rolling Update Rollback Plan
If a primary microservice deployment rolling update (triggered via `kubectl set image` or manifest apply) is unstable, failing health checks, or crash-looping.

### 1.1. Identify the Incident
Monitor the rollouts using:
```bash
kubectl rollout status deployment/<service-name>
```
Look for container restarts or prolonged `Readiness` failures.

### 1.2. Execute Rollback
Instantly abort and revert to the last working revision:
```bash
kubectl rollout undo deployment/<service-name>
```

To view deployment history:
```bash
kubectl rollout history deployment/<service-name>
```

To rollback to a specific revision (e.g. Revision 3):
```bash
kubectl rollout undo deployment/<service-name> --to-revision=3
```

---

## 2. Canary Deployment Rollback Plan
If metrics reveal high HTTP 5xx error rates, latency spikes, or memory leaks on the active Canary pods.

### 2.1. Abort Canary Traffic Routing
Immediately disconnect the Canary Ingress controller to cease all live traffic allocation to Canary pods:
```bash
kubectl delete ingress auth-service-canary-ingress
```
This forces the primary Ingress to immediately absorb 100% of request routing.

### 2.2. Teardown Canary Pods
Destroy the Canary pods and ClusterIP services to free cluster resources:
```bash
kubectl delete svc auth-service-canary
kubectl delete deployment auth-service-canary
```

---

## 3. Database Schema Migration Rollback
If a database schema migration breaks backwards compatibility or causes application crashes.

### 3.1. Revert Go Migrate/Database Actions
Locate backend service schemas and run rollback commands using migration tools:
```bash
# Revert migration by 1 step
migrate -path ./migrations -database "postgres://user:pass@host:5432/db" down 1
```

### 3.2. Re-deploy Previous Stable Build
Ensure application services are rolled back to the version matching the reverted database schema.
