# Zero-Trust Infrastructure Hardening Guide
**Kubernetes Network Policies, Container Sandboxing, Key Rotations, and Threat Mitigations**
**Author:** Principal Infrastructure Security Architect

---

## 1. Secrets Management Architecture

To adhere to Zero Trust principles, Nearby Connect forbids passing raw cryptographic credentials (database passwords, RSA private keys, KMS access tokens) via plain Kubernetes container environment variables. 
*   **Vulnerability:** Env variables are visible to standard users via `kubectl describe pod` commands, are leaked in process memory dumps, and are printed to debug logs during stack crashes.
*   **Hardening Strategy:**
    1.  **Storage:** Active production secrets are stored in **Google Cloud Secret Manager**.
    2.  **Projection:** We deploy the **External Secrets Operator (ESO)** in the Kubernetes cluster.
    3.  **Mounting:** Secrets are projected into the target pods as local files using **secrets store CSI volumes**:
        ```yaml
        volumeMounts:
          - name: secrets-volume
            mountPath: "/var/run/secrets/nearby.com"
            readOnly: true
        ```
    4.  **Ingestion:** The Auth Service reads the RSA private signing key from the local path `/var/run/secrets/nearby.com/rsa-private.pem` directly into RAM, keeping environment variables clean.

---

## 2. Runtime Security & Sandboxing

All deployments in the `gateway`, `auth`, `redis`, and `signaling` namespaces must enforce runtime sandboxing.

### 2.1. Kernel Capability Dropping
Pods drop all standard Linux kernel capabilities. Processes do not require administrative capabilities (like `CAP_NET_ADMIN` or `CAP_SYS_ADMIN`):
```yaml
securityContext:
  capabilities:
    drop:
      - ALL
```

### 2.2. Seccomp Profiles
Processes are restricted from invoking dangerous system calls (like `ptrace` or `sys_chroot`). Pods must run with the **RuntimeDefault** seccomp profile, which blocks around 100 system calls not needed by typical application container events.

---

## 3. Traffic Flow Enforcement (Textual Request Path)

The request path ensures that no public connection can bypass routing checkpoints to communicate directly with backend stores:

```
[ User Device ] ──(WSS / HTTPS Port 443)──► [ Load Balancer / Ingress Controller ]
                                                      │
                                                      ▼
[ WebSocket Gateway ] ◄──(mTLS NetworkPolicy)─────────┘
        │
        ├─(mTLS Port 8080)─► [ Auth Service ] ──(HTTPS)──► [ GCP KMS HSM ]
        │
        ├─(mTLS Port 6379)─► [ Redis Cluster ] (No Egress permitted)
        │
        └─(mTLS Port 9000)─► [ WebRTC Signaling Service ]
```

---

## 4. Threat & Failure Analysis

### 4.1. Pod Compromise Attempt (Gateway Pod Breach)
*   **Attack Vector:** An attacker finds a remote code execution (RCE) vulnerability in the WebSocket server.
*   **Infrastructure Mitigations:**
    *   **Distroless Base:** The container contains no shell (`/bin/sh`, `/bin/bash`) and no package manager (`apk`, `apt`), preventing the download or execution of scripts.
    *   **Read-Only Root Filesystem:** The root disk is read-only. The attacker cannot write persistent shell payloads or tools.
    *   **Network Isolation:** Network policies block the pod from executing egress connections to the internet or lateral connections to other databases, rendering command-and-control backchannels inoperable.

### 4.2. Egress Abuse (Exfiltration of Data)
*   **Attack Vector:** Compromised auth service pod attempts to extract database contents and post them to an external server.
*   **Mitigation:** The egress policy blocks the auth service from establishing connections outside the cluster, except strictly to the KMS endpoint IP ranges on port 443. All other external traffic is dropped at the network interface layer.

---

## 5. Security Telemetry & Audit Hooks

*   **Denied Connection Events:** Configure the Kubernetes CNI plugin (e.g. Cilium, Calico) to output policy violation alerts:
    `network_policy_violations_total{namespace="redis", direction="ingress"}`
*   **Audit Logging:** Set up Kubernetes audit logging rules targeting modifications to NetworkPolicies and secrets volume mounts:
    `alert_rule: K8sAuditSecretAccessByUnauthorizedPod (Severity: P0)`

---

## 6. SRE Infrastructure Hardening PRR Checklist

- [ ] **Distroless Container:** Validate Go binaries compile with `CGO_ENABLED=0` and run on `distroless:nonroot`.
- [ ] **Read-Only Root File System:** Confirm `readOnlyRootFilesystem: true` is set on gateway and auth deployments.
- [ ] **Capabilities Drop:** Assert that `capabilities: drop: - ALL` is present in deployment YAML specs.
- [ ] **Secrets Integration:** Verify that credentials are read from files under `/var/run/secrets/` and not from environment strings.
- [ ] **Default Deny Policies:** Confirm default-deny network policy templates are applied to all custom namespaces.
