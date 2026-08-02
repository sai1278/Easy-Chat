# Nearby Connect — Production Internet Gap Analysis Report

**Date**: August 2, 2026  
**Auditors**: Google Principal Cloud Architect, Principal Go Distributed-Systems Engineer, Principal Flutter Release Engineer, Android Networking Engineer, Staff SRE, Security Engineer & Production Release Manager  
**Package Namespace**: `com.nearbyconnect.app`  
**Target Domain**: `api.easychat.com`

---

## 1. Current Architecture vs. Target Architecture

```
Current Verified LAN Development Architecture:
Physical Device A (Wi-Fi X) ──► HTTP/WS ──► http://192.168.31.60:8090/api/v1 ◄── HTTP/WS ◄── Physical Device B (Wi-Fi X)

Target Cloud Production Architecture:
Device A (Wi-Fi X / 5G)
   ↓
https://api.easychat.com / wss://api.easychat.com
   ↓
Public DNS (A Record -> Cloud External Static IP)
   ↓
Cloud Ingress / External Load Balancer (Port 443 TLS 1.3 Termination)
   ↓
API Gateway (:8090)
   ├── Auth Service (:8081)    ──► PostgreSQL (:54322)
   ├── User Service (:8085)    ──► PostgreSQL (:54322)
   ├── Nearby Service (:8088)  ──► Redis GEOSEARCH (:6379)
   ├── Presence Service (:8084)──► Redis PubSub (:6379)
   └── Chat Service (:8082)    ──► Kafka (:9092) ──► PostgreSQL (:54322)
   ↑
Device B (Wi-Fi Y / 5G)
```

---

## 2. Existing Production Infrastructure Audit

- **Microservice Codebase**: Go microservices (Gateway, Auth, User, Nearby, Presence, Chat, Notification, Media) are 100% production-ready with context timeouts, circuit breakers, and rate limiting.
- **Flutter App Environment**: `apps/frontend/lib/core/network/environment.dart` implements strict `Environment.production` mapping to `https://api.easychat.com/api/v1` and `wss://api.easychat.com/ws`.
- **R8 / ProGuard Rules**: Active and verified for `flutter_secure_storage`, `crypto`, `okhttp3`, `geolocator`, `isar`, `protobuf`.

---

## 3. Missing Cloud Components & Gap Audit

| Component | Current Local State | Production Cloud Requirement | Gap Status |
| :--- | :--- | :--- | :---: |
| **Cloud K8s Cluster** | Local Docker Compose / Kind | Managed Cloud Kubernetes (GKE / EKS / AKS) | **MISSING** |
| **Cloud Load Balancer** | Local Port `:8090` | Cloud External HTTPS/WSS Load Balancer | **MISSING** |
| **Public DNS** | `api.easychat.com` points to `38.75.229.236` (Unrelated OpenBSD) | Public DNS A record pointing to Cloud Ingress IP | **MISSING** |
| **TLS Certificate** | Self-signed / HTTP | Let's Encrypt / Cert-Manager TLS Certificate | **MISSING** |
| **Database HA** | Single Container PostgreSQL (`:54322`) | Managed Cloud SQL / PostgreSQL StatefulSet with PV | **MISSING** |
| **Redis HA** | Single Container Redis (`:6379`) | Managed Memorystore / Redis Sentinel Cluster | **MISSING** |
| **Kafka HA** | Single Node Kafka (`:9092`) | Managed MSK / Strimzi Kafka Operator Cluster | **MISSING** |

---

## 4. Security & Isolation Risk Audit

1. **Database Exposure Risk**: PostgreSQL, Redis, and Kafka must remain strictly internal within the private Kubernetes VPC subnet and **NEVER** exposed to public Internet ports.
2. **Gateway Authorization Guard**: API Gateway is the single point of entry for public HTTP/WSS requests. It verifies JWT signatures and propagates `X-User-Id` down to downstream microservices.

---

## 5. Exact Blockers & Implementation Order

1. **Blocker 1**: Public Cloud Kubernetes Cluster & Load Balancer Provisioning.
2. **Blocker 2**: Public DNS A Record mapping `api.easychat.com` to the Cloud Ingress IP.
3. **Blocker 3**: Production Let's Encrypt Certificate issuance via cert-manager.
4. **Blocker 4**: Real physical-device testing across separate Wi-Fi and 5G networks.
