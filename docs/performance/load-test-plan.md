# Production-Scale Performance & Load Test Plan

**Version:** 1.0.0  
**Lead Architect:** Google Principal Performance Engineer & SRE  
**Target Platform:** Nearby Connect Platform

---

## 1. Executive Summary & Strategy

This document establishes the official performance testing strategy for the Nearby Connect platform. The objective is to validate system latency, throughput, resource utilization, and autoscaling stability under 100, 500, 1000, and 5000 concurrent user load tiers before production deployment.

---

## 2. Target Load Tiers & Profiles

| Tier | Concurrent Users (VUs) | Target RPS | Purpose |
| :---: | :---: | :---: | :--- |
| **Tier 1** | **100** | ~500 RPS | Baseline sanity load & memory leakage check |
| **Tier 2** | **500** | ~2,500 RPS | Moderate production load & database connection pool validation |
| **Tier 3** | **1,000** | ~5,000 RPS | Peak daily traffic volume & HPA autoscaling verification |
| **Tier 4** | **5,000** | ~25,000 RPS | Maximum capacity stress limit & failover validation |

### Special Performance Test Profiles:
1. **Soak Test (24 Hours):** Sustained 1,000 VUs over 24 hours to detect memory leaks, goroutine leaks, and DB connection pool exhaustion.
2. **Spike Test:** Instantaneous traffic jump from 100 VUs to 3,000 VUs within 30 seconds to verify API Gateway rate-limiting and Kafka consumer queue buffer.
3. **Stress Test:** Incremental ramp up beyond 5,000 VUs until system error rate exceeds 1% or P99 latency breaches 1000ms, identifying true breaking points.

---

## 3. Key Performance Indicators (SLIs & SLOs)

| Metric | Target SLO | Warning Threshold | Critical SLA Breach |
| :--- | :---: | :---: | :---: |
| **HTTP P50 Latency** | $< 50\text{ ms}$ | $> 100\text{ ms}$ | $> 250\text{ ms}$ |
| **HTTP P95 Latency** | $< 200\text{ ms}$ | $> 350\text{ ms}$ | $> 500\text{ ms}$ |
| **HTTP P99 Latency** | $< 500\text{ ms}$ | $> 750\text{ ms}$ | $> 1000\text{ ms}$ |
| **HTTP Error Rate** | $< 0.1\%$ | $> 0.5\%$ | $> 1.0\%$ |
| **WebSocket Connection Success** | $> 99.9\%$ | $< 99.5\%$ | $< 99.0\%$ |
| **Kafka Message Processing Lag** | $< 100\text{ ms}$ | $> 500\text{ ms}$ | $> 2000\text{ ms}$ |

---

## 4. Test Topology & Scenario Coverage

1. **Anonymous Auth:** OIDC PKCE code exchange and JWT token issuance.
2. **Presence Heartbeat:** High-frequency heartbeat state updates with adaptive battery duty cycles.
3. **Nearby Discovery:** Uber H3 spatial indexing (`8a2a1072b59ffff`) radius searches.
4. **Instant Messaging:** WebSocket packet multiplexing (`MESSAGE`, `RECEIPT`, `TYPING`).
5. **Media Upload & Download:** Encrypted S3 upload URL resolution & malware stream scanning.

---

## 5. Execution Pre-Requisites

- Kubernetes Cluster deployed with Horizontal Pod Autoscaler (HPA).
- Prometheus & Grafana monitoring stack deployed and receiving telemetry.
- Load generators (k6 or Locust) provisioned on dedicated compute nodes isolated from target application pods.
