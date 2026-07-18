# Nearby Connect — SRE Runbooks
> **Operational Reference** | Owner: SRE Team | Review Cycle: Quarterly
> All commands assume `kubectl` context is set to the production cluster.

---

## Table of Contents
1. [High API Latency](#1-high-api-latency)
2. [Pod CrashLoop](#2-pod-crashloop)
3. [WebSocket Mass Disconnect](#3-websocket-mass-disconnect)
4. [Database Connection Pool Saturation](#4-database-connection-pool-saturation)
5. [PostgreSQL Replication Lag](#5-postgresql-replication-lag)
6. [Redis Memory Pressure](#6-redis-memory-pressure)
7. [Kafka Consumer Lag Critical](#7-kafka-consumer-lag-critical)
8. [Kafka Broker Down](#8-kafka-broker-down)
9. [HPA Max Replicas Reached](#9-hpa-max-replicas-reached)
10. [Node Disk Pressure](#10-node-disk-pressure)
11. [SLO Error Budget Exhausted](#11-slo-error-budget-exhausted)
12. [Canary Rollback](#12-canary-rollback)

---

## 1. High API Latency

**Alert:** `APIHighLatency` / `APICriticalLatency`  
**SLO Impact:** API Availability & Latency SLO  
**Estimated MTTD:** 5 min | **Estimated MTTR:** 15–30 min

### Symptoms
- p99 latency > 200ms (warning) or > 500ms (critical)
- Users experiencing slow responses in the mobile app

### Triage Steps (5 min)

```bash
# 1. Identify which service is slow
kubectl top pods -n default --sort-by=cpu

# 2. Check request distribution
# PromQL: histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))

# 3. Check for upstream dependency issues
kubectl logs -l app=gateway-service --tail=100 | grep -E "timeout|error|slow"

# 4. Check DB query latency
# PromQL: histogram_quantile(0.99, sum(rate(db_query_duration_seconds_bucket[5m])) by (le, service))
```

### Remediation

| Cause | Action |
|---|---|
| CPU throttling | Check `kubectl top pods`; if CPU at limit, trigger manual HPA scale: `kubectl scale deployment <svc> --replicas=N` |
| Slow DB queries | Check `pg_stat_activity` for long-running queries; kill with `SELECT pg_terminate_backend(pid)` |
| Redis cache miss | Check `redis_keyspace_hits/misses`; if miss rate high, warm cache or extend TTL |
| Recent deployment | Check canary error rate; rollback if needed (see Runbook 12) |
| Downstream service | Check Istio/Envoy circuit breaker state; check Loki for upstream 5xx |

### Escalation
- **15 min no improvement** → Page engineering lead
- **30 min no improvement** → Initiate incident (SEV-1)

---

## 2. Pod CrashLoop

**Alert:** `PodCrashLooping`  
**SLO Impact:** Availability SLO (reduces capacity)

### Triage Steps (3 min)

```bash
# 1. Identify crashing pod
kubectl get pods -n default | grep -E "CrashLoopBackOff|Error"

# 2. Read crash reason
kubectl describe pod <pod-name> -n default | tail -40

# 3. Read last logs before crash
kubectl logs <pod-name> -n default --previous --tail=100

# 4. Check for OOMKill
kubectl get events -n default --sort-by=.metadata.creationTimestamp | grep -i oom
```

### Remediation

| Cause | Action |
|---|---|
| OOMKill | Increase memory limit in values.yaml; redeploy |
| Panic / nil pointer | Read previous logs; identify code path; rollback deployment |
| Liveness probe fail | Check probe endpoint; verify service is binding to correct port |
| Secret/config missing | `kubectl get secret easychat-secrets -o yaml`; verify all keys present |
| Image pull failure | `kubectl describe pod`; check GHCR credentials and image tag |

```bash
# Emergency: delete crashing pod to force fresh start
kubectl delete pod <pod-name> -n default

# If persistent: rollback deployment
kubectl rollout undo deployment/<service-name> -n default
```

---

## 3. WebSocket Mass Disconnect

**Alert:** `WebSocketMassiveDrop` / `SLOBurnRateCritical_WebSocket`  
**SLO Impact:** WebSocket Availability SLO (99.9% uptime)

### Triage Steps

```bash
# 1. Check gateway pod health
kubectl get pods -l app=gateway-service

# 2. Check recent rollout
kubectl rollout history deployment/gateway-service

# 3. Check TLS cert expiry (common cause of mass drops)
kubectl get secret easychat-tls-cert -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -enddate

# 4. Check network policy changes
kubectl get networkpolicies -n default

# 5. Check Istio/Envoy proxy status
istioctl proxy-status
```

### Remediation

| Cause | Action |
|---|---|
| TLS cert expired | Trigger cert-manager rotation: `kubectl delete secret easychat-tls-cert` (cert-manager recreates) |
| Gateway pod crash | `kubectl rollout undo deployment/gateway-service` |
| Network policy blocking WS | Check `network-policies.yaml`; temporarily remove offending rule |
| Istio sidecar issue | `kubectl rollout restart deployment/gateway-service` |
| Node eviction | Scale up node pool via cloud console; wait for pod rescheduling |

---

## 4. Database Connection Pool Saturation

**Alert:** `DatabaseConnectionPoolSaturation` (pool > 90%)  
**SLO Impact:** API Availability + Latency SLOs

### Triage Steps

```bash
# 1. Check current pool usage per service
# PromQL: sum(db_pool_connections_used) by (service) / sum(db_pool_connections_max) by (service)

# 2. Check Postgres active connections
kubectl exec -it <postgres-pod> -- psql -U postgres -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"

# 3. Check for long-running transactions blocking connections
kubectl exec -it <postgres-pod> -- psql -U postgres -c "SELECT pid, now() - xact_start AS txn_age, query FROM pg_stat_activity WHERE state != 'idle' ORDER BY txn_age DESC LIMIT 20;"
```

### Remediation

```bash
# 1. Kill idle connections stuck in transaction
kubectl exec -it <postgres-pod> -- psql -U postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle in transaction' AND now() - state_change > interval '5 minutes';"

# 2. Temporarily increase PgBouncer pool size (hot-reload)
kubectl exec -it <pgbouncer-pod> -- psql -p 6432 pgbouncer -c "RELOAD;"

# 3. Scale up the service to reduce per-pod connection demand
kubectl scale deployment <service> --replicas=<N+2>
```

---

## 5. PostgreSQL Replication Lag

**Alert:** `PostgreSQLReplicationLagHigh` (lag > 30s)  
**SLO Impact:** RPO SLA (DR readiness)

### Triage Steps

```bash
# 1. Check replication status on primary
kubectl exec -it <postgres-primary-pod> -- psql -U postgres -c \
  "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"

# 2. Check WAL sender process
kubectl exec -it <postgres-primary-pod> -- psql -U postgres -c \
  "SELECT pid, application_name, state FROM pg_stat_replication;"

# 3. Check disk space on replica
kubectl exec -it <postgres-replica-pod> -- df -h /var/lib/postgresql
```

### Remediation

| Cause | Action |
|---|---|
| Network congestion | Check inter-region bandwidth; throttle other bulk operations |
| Replica disk full | Extend PVC or clean WAL archive directory |
| Replica CPU spike | Scale replica node; check concurrent read queries |
| WAL flooding | Reduce `wal_keep_size`; verify archive_command is not blocked |

> **DR Implication:** If lag > 30s, the DR RPO SLA is at risk. Do NOT trigger failover until lag resolves; if lag > 5 min, alert DR team.

---

## 6. Redis Memory Pressure

**Alert:** `RedisMemoryPressureHigh` (memory > 85%) / `RedisEvictionRateSpike`

### Triage Steps

```bash
# 1. Check Redis memory stats
kubectl exec -it <redis-pod> -- redis-cli INFO memory | grep -E "used_memory_human|maxmemory_human|mem_fragmentation_ratio"

# 2. Check eviction counts
kubectl exec -it <redis-pod> -- redis-cli INFO stats | grep evicted

# 3. Find largest keys
kubectl exec -it <redis-pod> -- redis-cli --memkeys --memkeys-samples 200

# 4. Check key TTL distribution (are TTLs set?)
kubectl exec -it <redis-pod> -- redis-cli DEBUG SLEEP 0
kubectl exec -it <redis-pod> -- redis-cli INFO keyspace
```

### Remediation

```bash
# Option A: Flush volatile keys (safe — only keys with TTL)
kubectl exec -it <redis-pod> -- redis-cli --scan --pattern "session:*" | xargs redis-cli DEL

# Option B: Reduce maxmemory-samples for faster eviction (runtime change)
kubectl exec -it <redis-pod> -- redis-cli CONFIG SET maxmemory-samples 3

# Option C: Emergency — temporarily raise maxmemory 10% (confirm with team lead)
kubectl exec -it <redis-pod> -- redis-cli CONFIG SET maxmemory 300mb
```

---

## 7. Kafka Consumer Lag Critical

**Alert:** `KafkaConsumerLagCritical` (lag > 5000)

### Triage Steps

```bash
# 1. Check consumer group offsets
kubectl exec -it <kafka-pod> -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group <consumer-group>

# 2. Check consumer pod health
kubectl get pods -l app=<service-with-kafka-consumer>

# 3. Check partition assignment
kubectl exec -it <kafka-pod> -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group <consumer-group> | grep -v "^$"
```

### Remediation

| Cause | Action |
|---|---|
| Consumer pod crashed | Restart pod; lag will auto-recover |
| Slow consumer processing | Scale consumer deployment horizontally |
| Topic partition imbalance | Run partition rebalance: `kafka-preferred-replica-election.sh` |
| Producer spike | Check producer rate; add backpressure at gateway level |
| Deserialization error | Check consumer logs for schema mismatch; deploy schema fix |

```bash
# Scale consumer to accelerate catch-up
kubectl scale deployment chat-service --replicas=6

# Reset offset to latest (EMERGENCY ONLY — skips messages)
# WARNING: Verify this is acceptable before running
kubectl exec -it <kafka-pod> -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group <group> --topic <topic> --reset-offsets --to-latest --execute
```

---

## 8. Kafka Broker Down

**Alert:** `KafkaBrokerDown` (broker count < 3)

### Triage Steps

```bash
# 1. Check broker pod status
kubectl get pods -l app=kafka -n default

# 2. Check broker connectivity
kubectl exec -it <kafka-pod> -- kafka-broker-api-versions.sh \
  --bootstrap-server kafka:9092

# 3. Check controller status
kubectl exec -it <kafka-pod> -- kafka-metadata-quorum.sh \
  --bootstrap-server kafka:9092 describe
```

### Remediation

```bash
# Force pod restart
kubectl delete pod <kafka-pod-name> -n default

# If persistent failure, check StatefulSet PVC
kubectl get pvc -l app=kafka

# Manual leader election if controller is down
kubectl exec -it <kafka-pod> -- kafka-leader-election.sh \
  --bootstrap-server kafka:9092 \
  --election-type PREFERRED \
  --all-topic-partitions
```

---

## 9. HPA Max Replicas Reached

**Alert:** `HPAMaxReplicasReached`

### Triage Steps

```bash
# 1. Check HPA status
kubectl get hpa -n default

# 2. Identify which service
kubectl describe hpa <service>-hpa -n default

# 3. Check node capacity
kubectl describe nodes | grep -E "Allocatable|Requests"
```

### Remediation

```bash
# Option A: Temporarily raise HPA max (requires YAML update)
kubectl patch hpa <service>-hpa -n default \
  --type merge -p '{"spec":{"maxReplicas":20}}'

# Option B: Scale node pool (cloud console or CLI)
# GCP: gcloud container clusters resize easychat-cluster --num-nodes=8 --zone=us-east1-b
# AWS: aws eks update-nodegroup-config --cluster-name easychat --nodegroup-name workers --scaling-config desiredSize=8,minSize=3,maxSize=20

# Option C: Drain non-critical workloads to free capacity
kubectl cordon <non-critical-node>
```

---

## 10. Node Disk Pressure

**Alert:** `NodeDiskPressure` (disk > 85%)

### Triage Steps

```bash
# 1. Check disk usage on node
kubectl debug node/<node-name> -it --image=busybox -- df -h

# 2. Find large containers
kubectl get pods --field-selector=spec.nodeName=<node-name> -n default

# 3. Check for log accumulation
du -sh /var/log/containers/*
```

### Remediation

```bash
# Clean up container images and stopped containers
kubectl debug node/<node-name> -it --image=busybox -- \
  chroot /host crictl rmi --prune

# Remove unused volumes
kubectl debug node/<node-name> -it --image=busybox -- \
  chroot /host crictl rm $(crictl ps -a -q)

# If persistent: drain and replace node
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
# Then terminate node in cloud console
```

---

## 11. SLO Error Budget Exhausted

**Alert:** `ErrorBudgetExhausted_APIAvailability`  
**Action Required:** Feature freeze + escalation to engineering leadership

### Response Protocol

1. **Immediately freeze all production deployments**
   ```bash
   # Update CI/CD: set DEPLOY_GATE=blocked in GitHub Actions environment
   gh variable set DEPLOY_GATE --body "blocked" --env production
   ```

2. **Send stakeholder notification** within 15 minutes
3. **Convene incident review** within 24 hours
4. **Root cause analysis** and remediation plan within 48 hours
5. **SLO review** — consider relaxing targets or investing in reliability work
6. **Resume deployments** only after 7-day budget recovery monitoring

---

## 12. Canary Rollback

**Alert:** `CanaryErrorRateExceedsThreshold`  
**SLO Impact:** Immediate if not rolled back within 5 min

### Rollback Steps (< 5 min SLA)

```bash
# 1. Remove canary ingress immediately (stops canary traffic)
kubectl delete ingress <service>-canary-ingress -n default

# 2. Verify canary deployment removed
kubectl delete deployment <service>-canary -n default

# 3. Verify primary service is handling all traffic
kubectl get ingress easychat-ingress -n default

# 4. Verify error rate returning to baseline (watch for 2 min)
# PromQL: sum(rate(http_requests_total{status=~"5.."}[2m])) / sum(rate(http_requests_total[2m]))

# 5. Page engineering team with: service affected, error rate, rollback time
```

### Post-Rollback Checklist
- [ ] Error rate returned to < 0.1%
- [ ] p99 latency returned to < 200ms
- [ ] Canary image tagged as `FAILED-<timestamp>` in registry
- [ ] Incident created in incident tracker
- [ ] PR author notified with failure metrics
