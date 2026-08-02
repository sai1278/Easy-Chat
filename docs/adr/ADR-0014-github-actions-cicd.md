# ADR 0014: Continuous Integration & Deployment via GitHub Actions

**ADR Number:** ADR-0014  
**Title:** Continuous Integration & Deployment via GitHub Actions  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
The monorepo requires automated code linting, unit testing, security static analysis, container image building, vulnerability scanning, image signing, supply chain SBOM generation, and progressive deployment with automatic rollback capabilities.

## 2. Problem Statement
Manual builds and deployments introduce human error, un-scanned container image vulnerabilities, lack of deployment provenance, and slow recovery times when buggy releases enter staging or production environments.

## 3. Decision
Adopt GitHub Actions as the CI/CD pipeline engine. Workflows are organized into reusable workflows (`reusable-go.yml`, `reusable-docker.yml`), executing:
* **CI Validation:** Go linting, Gosec static analysis, unit testing, Trivy vulnerability scanning (`.github/workflows/ci.yml`).
* **Supply Chain Security:** Cosign container image signing and SPDX/CycloneDX SBOM generation (`.github/workflows/reusable-docker.yml`).
* **CD Progressive Rollout:** Environment promotion (`development` $\rightarrow$ `qa` $\rightarrow$ `staging` Blue/Green $\rightarrow$ `production` 10% Canary with automated Prometheus metric verification and auto-rollback) (`.github/workflows/cd.yml`).

## 4. Evidence
* **CI Workflow Pipeline:** [`.github/workflows/ci.yml:1-93`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/.github/workflows/ci.yml#L1-L93)
* **CD Progressive Deployment:** [`.github/workflows/cd.yml:1-213`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/.github/workflows/cd.yml#L1-L213)
* **Reusable Docker Build & Sign:** [`.github/workflows/reusable-docker.yml:1-95`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/.github/workflows/reusable-docker.yml#L1-L95)

## 5. Alternatives Considered
* **Jenkins:** Rejected due to operational maintenance overhead, dedicated server hosting costs, and lack of native GitHub repository trigger integration.
* **GitLab CI:** Rejected to maintain single-platform alignment with GitHub source control hosting.

## 6. Tradeoffs
* Runner execution time consumption during matrix testing across multiple microservices.
* Inline shell scripts for Prometheus canary verification require careful maintenance.

## 7. Consequences
* Guaranteed security scanning and cryptographic signing for all container images.
* Automated release rollback upon SLA failure during canary deployments.

## 8. Risks
* Fragile inline JSON metric parsing in shell steps (mitigated via `jq` refactoring task).

## 9. Future Considerations
* Integrate Flagger or Argo Rollouts CRD controllers for declarative canary traffic shifting.
