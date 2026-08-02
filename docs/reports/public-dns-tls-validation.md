# Public DNS & TLS Validation Report

**Date**: August 2, 2026  
**Auditors**: Google Principal Security Engineer & Cloud Networking Engineer  
**Target Domain**: `api.easychat.com`

---

## 1. Current Public DNS Audit

- **Domain Query**: `nslookup api.easychat.com`
- **Resolved IP**: `38.75.229.236`
- **Audit Result**: `38.75.229.236` is an unassigned public IP address pointing to an external OpenBSD httpd server. It is **NOT** mapped to the Nearby Connect Cloud Load Balancer.

---

## 2. Current Public TLS Audit

- **HTTPS Request**: `curl -iv https://api.easychat.com/healthz`
- **TLS Handshake Result**: **FAILED** (`SEC_E_WRONG_PRINCIPAL (0x80090322)` - Target principal name mismatch).
- **Audit Result**: The server at `38.75.229.236` presents an invalid/unrelated SSL certificate.

---

## 3. Human Action Required for Domain Owner

To point `api.easychat.com` to the official Nearby Connect production cloud cluster:

1. **Allocate External Static IP**: Provision an External Static IPv4 address in your cloud provider (e.g. GCP External IP / AWS Elastic IP).
2. **Update DNS A Record**:
   - Domain Name: `api.easychat.com`
   - Record Type: `A`
   - Target Value: `<EXTERNAL_STATIC_IP>`
   - TTL: `300`
3. **Deploy Cert-Manager ClusterIssuer**:
   - Apply [`infrastructure/kubernetes/production/cert-manager.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/kubernetes/production/cert-manager.yaml) to issue a valid Let's Encrypt TLS certificate.
