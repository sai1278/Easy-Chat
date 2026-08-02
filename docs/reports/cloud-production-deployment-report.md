# Cloud Production Deployment & Architecture Report

**Date**: August 2, 2026  
**Auditors**: Google Principal Cloud Architect, Staff SRE, Cloud Networking Engineer  
**Package Namespace**: `com.nearbyconnect.app`  
**Target Domain**: `api.easychat.com`

---

## 1. Cloud Kubernetes Cluster & Ingress Topology

The target production environment utilizes managed Cloud Kubernetes (GKE / EKS / AKS) with an NGINX Ingress Controller.

```
Internet (Device A / Device B)
    ↓ HTTPS (Port 443) / WSS (Port 443)
Cloud External Static IP / Load Balancer
    ↓ TLS 1.3 Termination (Cert-Manager Let's Encrypt)
NGINX Ingress Controller
    ├─► /ws              ──► API Gateway (:8080) ──► Chat Service (:8082)
    └─► /api/v1/*        ──► API Gateway (:8080) ──► Downstream Microservices
```

---

## 2. Updated Production Ingress Manifest Audit

The Kubernetes Ingress manifest [`infrastructure/kubernetes/production/ingress.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/kubernetes/production/ingress.yaml) has been updated to:
1. Target `host: api.easychat.com`.
2. Direct all `/ws` and `/api/v1/*` routes to `gateway-service` on port `8080`.
3. Enable Let's Encrypt production certificate issuer `letsencrypt-production`.
4. Configure persistent WebSocket timeouts (`proxy-read-timeout: 3600`, `proxy-send-timeout: 3600`).

---

## 3. Database & Stateful Services Security Policy

- **PostgreSQL**: Bound to internal K8s service `postgres-service:5432`. Public access: **DISABLED**.
- **Redis**: Bound to internal K8s service `redis-service:6379`. Public access: **DISABLED**.
- **Kafka**: Bound to internal K8s service `kafka-service:9092`. Public access: **DISABLED**.

---

## 4. Observability Integration

Production deployments integrate OpenTelemetry collector, Prometheus metrics scraping, Loki log aggregation, and Grafana dashboards tracking:
- HTTP 4xx / 5xx error rates
- WebSocket active connection count & disconnect rate
- Message end-to-end delivery latency
- Redis GEOSEARCH query latency (< 5ms)
- Pod memory & CPU utilization
