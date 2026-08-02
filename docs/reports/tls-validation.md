# Public TLS & Domain Audit Validation Report

**Date**: August 2, 2026  
**Auditors**: Google Principal Security Engineer & Cloud Networking Engineer  
**Target Domain**: `api.easychat.com`

---

## 1. Domain Resolution & SSL Audit

- **DNS Query (`nslookup api.easychat.com`)**:
  - Resolved IP: `38.75.229.236` (Unassigned third-party OpenBSD httpd server).
- **HTTPS Request (`curl -iv https://api.easychat.com/healthz`)**:
  - Result: **`FAILED`** (`SEC_E_WRONG_PRINCIPAL (0x80090322)` - Target principal name mismatch).
- **Audit Result**: Domain `api.easychat.com` is not yet mapped to the Nearby Connect Cloud Ingress Load Balancer IP.

---

## 2. Category Verification Status Matrix

| Category | Status | Notes |
| :--- | :---: | :--- |
| **Cert-Manager Manifest Configuration** | **PASS** | [`cert-manager.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/kubernetes/production/cert-manager.yaml) configured for Let's Encrypt production ClusterIssuer |
| **NGINX Ingress SSL Policy** | **PASS** | [`ingress.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/kubernetes/production/ingress.yaml) configured with SSL redirect & 3600s timeouts |
| **Live ACME Domain Certification** | **PARTIAL** | Blocked on DNS registrar A-record entry mapping `api.easychat.com` |

---

## 3. Final Handoff Status

### **`Infrastructure Pending Human Action`**
