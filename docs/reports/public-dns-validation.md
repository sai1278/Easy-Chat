# Public DNS Validation & Domain Audit Report

**Date**: August 2, 2026  
**Auditors**: Cloud Networking Engineer & Production Release Manager  
**Target Domain**: `api.easychat.com`

---

## 1. Domain Resolution & Propagation Audit

- **DNS Query Tool**: `nslookup api.easychat.com` / `dig api.easychat.com`
- **Currently Resolved IP**: `38.75.229.236`
- **IP Ownership & Reverse PTR Audit**: `38.75.229.236` belongs to an external unassigned server running OpenBSD httpd.
- **Audit Verdict**: `api.easychat.com` is **NOT** currently mapped to the Nearby Connect GKE Cloud Load Balancer.

---

## 2. Required Human Action for Domain Registration & DNS Propagation

To complete public DNS mapping:

1. **Execute Terraform Static IP Allocation**:
   ```bash
   cd infrastructure/terraform
   terraform init
   terraform apply -auto-approve
   ```
2. **Retrieve Reserved External Static IP**:
   ```bash
   terraform output ingress_static_ip
   ```
3. **Update Domain Name Registrar (DNS A Record)**:
   - Host / Subdomain: `api.easychat.com`
   - Type: `A`
   - IPv4 Address: `<RESERVED_INGRESS_STATIC_IP>`
   - TTL: `300` (5 minutes)

---

## 3. Production Category Verification Status

```
===================================================================================
                     PUBLIC DNS CATEGORY STATUS VERDICT
===================================================================================
  1. DNS Target Domain Specification (api.easychat.com)           :  PASS
  2. Terraform External Static IP Reservation Config              :  PASS
  3. Public Registrar A-Record Propagation                        :  PENDING (HUMAN ACTION)

  CATEGORY OVERALL VERDICT                                        :  PARTIAL
===================================================================================
```
