# ADR 0013: Container Orchestration via Kubernetes & Helm

**ADR Number:** ADR-0013  
**Title:** Container Orchestration via Kubernetes & Helm  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
The platform requires cloud-agnostic container orchestration, automated pod scaling, rolling updates, pod disruption budgets, horizontal pod autoscaling, ingress routing, and environment parameterization across development, staging, and production environments.

## 2. Problem Statement
Managing raw static Kubernetes YAML files for 10 microservices across multiple deployment environments leads to manifest duplication, manual configuration drifts, and complex deployment rollback procedures.

## 3. Decision
Standardize on Kubernetes for production container orchestration and Helm v3 for chart templating (`infrastructure/helm/easychat`). Helm parameters configure dynamic pod resource requests, Horizontal Pod Autoscalers (HPA targeting 70% CPU, 80% Memory), Pod Disruption Budgets (PDB), ConfigMaps, and Secret mappings.

## 4. Evidence
* **Helm Chart Template Values:** [`infrastructure/helm/easychat/values.yaml:1-120`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/values.yaml#L1-L120)
* **Production Deployment Manifests:** [`infrastructure/kubernetes/production/deployments.yaml:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/kubernetes/production/deployments.yaml#L1)
* **Production HPA Rules:** [`infrastructure/kubernetes/production/hpa.yaml:1-35`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/kubernetes/production/hpa.yaml#L1-L35)
* **Production PDB Rules:** [`infrastructure/kubernetes/production/pdb.yaml:1-20`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/kubernetes/production/pdb.yaml#L1-L20)

## 5. Alternatives Considered
* **Docker Swarm:** Rejected due to lack of enterprise ecosystem tooling, PDB support, and advanced cloud provider integrations.
* **Raw Kustomize:** Rejected due to limited variable parameterization and complex environment overrides compared to Helm charts.

## 6. Tradeoffs
* Helm template syntax complexity and potential indentation errors in YAML files.
* Requires Kubernetes cluster management infrastructure.

## 7. Consequences
* Single command deployment across environments (`helm upgrade --install`).
* Automated pod scaling and guaranteed availability during node maintenance via PDBs.

## 8. Risks
* Misconfigured secret references in Helm templates causing deployment crashes.

## 9. Future Considerations
* Migrate raw secrets to Kubernetes ExternalSecrets Operator / HashiCorp Vault.
