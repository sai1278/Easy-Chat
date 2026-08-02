# ADR 0016: Automated Multi-Region Disaster Recovery Operator

**ADR Number:** ADR-0016  
**Title:** Automated Multi-Region Disaster Recovery Operator  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
The platform requires business continuity guarantees across catastrophic primary cloud region outages, targeting a Recovery Time Objective (RTO) $\le 5$ minutes and a Recovery Point Objective (RPO) $\le 30$ seconds.

## 2. Problem Statement
Manual failover procedures during multi-region disaster scenarios are prone to human operational error, split-brain scenarios (where both regions accept writes simultaneously), and SLA violations due to slow manual DNS record updates.

## 3. Decision
Develop a custom Kubernetes-native operator daemon (`DRController` in `apps/backend/services/dr-controller`). The operator executes:
* **Leader Election:** K8s `resourcelock.LeaseLock` on `dr-controller-leader` lease in `kube-system` namespace ([`main.go:145-198`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/dr-controller/main.go#L145-L198)).
* **Split-Brain Fencing:** Cryptographic fencing token generation via `crypto/rand` ([`main.go:93-100`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/dr-controller/main.go#L93-L100)).
* **Standby Promotion & Topology Reconfiguration:** Automated PostgreSQL standby promotion, Redis/MirrorMaker 2 topology reconfiguration, and GLB traffic weight shifting ([`main.go:255-301`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/dr-controller/main.go#L255-L301)).
* **SLA Verification:** Measures detection, failover, and recovery timestamps to verify RTO/RPO thresholds ([`main.go:283-296`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/dr-controller/main.go#L283-L296)).

## 4. Evidence
* **DR Controller Main Engine:** [`apps/backend/services/dr-controller/main.go:1-328`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/dr-controller/main.go#L1-L328)
* **DR Policy Custom Resource Definition:** [`infrastructure/dr/crds/disaster-recovery-policy-crd.yaml:1-60`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/dr/crds/disaster-recovery-policy-crd.yaml#L1-L60)
* **Failover Script Automation:** [`infrastructure/dr/automation/failover.sh:1-45`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/dr/automation/failover.sh#L1-L45)

## 5. Alternatives Considered
* **Manual SRE Runbook Failover:** Rejected due to violation of the 5-minute RTO threshold during off-hours incidents.

## 6. Tradeoffs
* Operational complexity of maintaining a custom Kubernetes controller daemon and leader lease locks.

## 7. Consequences
* Automated sub-5-minute failover execution with zero split-brain data corruption.
* Real-time calculation and logging of DR metrics and SLA pass/fail status.

## 8. Risks
* False positive failover triggers during transient cross-region network partitions (mitigated by probe retries and failure threshold counters).

## 9. Future Considerations
* Conduct quarterly automated game-day failover drills against staging environments.
