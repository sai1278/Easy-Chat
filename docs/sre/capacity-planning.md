# Nearby Connect — Capacity Planning Framework
> **Owner:** SRE | **Review Cycle:** Monthly (or when traffic grows > 20%)

---

## 1. Service Capacity Model

### Traffic & Scaling Parameters

| Service | Current RPS (p50) | Peak RPS (p99) | Saturation Point | HPA Max |
|---|---|---|---|---|
| gateway-service | 500 rps | 2,000 rps | ~3,000 rps/pod | 12 |
| auth-service | 200 rps | 800 rps | ~1,500 rps/pod | 6 |
| chat-service | 1,000 rps/msgs | 5,000 rps/msgs | ~2,000/pod | 15 |
| nearby-service | 300 rps | 1,200 rps | ~1,000 rps/pod | 10 |
| presence-service | 800 rps | 3,000 rps | ~2,500 rps/pod | 6 |
| user-service | 150 rps | 600 rps | ~2,000 rps/pod | 5 |
| media-service | 50 rps | 200 rps | ~100 rps/pod | 8 |
| notification-service | 200 rps | 1,000 rps | ~3,000 rps/pod | 4 |

### Capacity Headroom Policy
- **Normal operation:** Sustain < 60% of saturation point at p50 traffic
- **Peak readiness:** HPA must have ≥ 30% unused max replicas before peak periods
- **Node pool:** Maintain 20% unallocated node capacity at all times

---

## 2. Growth Projections

### Traffic Trend Analysis (PromQL)
```promql
# 30-day request rate trend
predict_linear(
  sum(rate(http_requests_total[1h]))[30d:1h],
  86400 * 30
)
```

### Capacity Triggers (Review Required When)
| Metric | Threshold | Action |
|---|---|---|
| Monthly request growth | > 20% | Recalculate HPA maxReplicas |
| Daily active users | > 100k | Review Kafka partition count |
| Concurrent WebSocket sessions | > 50k | Review gateway memory limits |
| DB size growth | > 50 GB/month | Plan storage expansion + partition strategy |
| Redis memory hit > 70% sustained | 7 days | Upsize Redis tier |
| Node pool CPU p90 > 70% | 3 days | Add node pool capacity |

---

## 3. Database Capacity Planning

### PostgreSQL

| Metric | Current | 6-Month Forecast | Action Threshold |
|---|---|---|---|
| Database size | ~10 GB | ~60 GB | >80 GB → review partitioning |
| Connections (peak) | ~40 | ~120 | >80% of max_connections → add PgBouncer pool |
| WAL generation rate | ~500 MB/day | ~3 GB/day | >5 GB/day → review archival frequency |
| Index bloat | < 10% | Monitor monthly | > 30% → REINDEX CONCURRENTLY |

**Partitioning Trigger:** Partition `messages` table by `created_at` month when row count exceeds 50M.

```sql
-- Check table size
SELECT
  schemaname, tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
  pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS data_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

### Redis

| Metric | Current | Action Threshold |
|---|---|---|
| Memory used | ~180 MB | > 210 MB (85% of 256 MB limit) → upsize |
| Key count | ~500k | > 2M → review key design / TTL policy |
| Connected clients | ~200 | > 1,000 → add Redis Cluster shards |
| Eviction rate | ~0 | > 10/s sustained → emergency upsize |

---

## 4. Kafka Capacity Planning

### Current State

| Resource | Current | Threshold for Action |
|---|---|---|
| Brokers per region | 3 | < 3 → scale up immediately |
| Partitions (chat-messages) | 6 | > 50k msgs/s → increase to 12 |
| Topic retention | 7d / 10 GB | Disk > 80% → reduce retention |
| Consumer throughput | ~5k msgs/s | > 80% consumer capacity → scale consumers |

### Partition Sizing Formula
```
Desired Partitions = ceil(Target Throughput MB/s ÷ Per-Partition Throughput MB/s)

# Per-partition throughput ≈ 10 MB/s (Kafka guidance)
# chat-messages target: 100 MB/s → 10 partitions minimum
```

---

## 5. Kubernetes Node Pool Capacity

### Node Pool Configuration

| Pool | Instance Type | Min | Max | Purpose |
|---|---|---|---|---|
| `on-demand` | e2-standard-4 (4 vCPU, 16GB) | 2 | 6 | Gateway, critical services |
| `spot` | e2-standard-4 | 2 | 20 | Stateless workloads |
| `memory` | e2-highmem-4 (4 vCPU, 32GB) | 1 | 4 | Redis, Kafka |

### Node Utilisation Targets
- **CPU:** 50–70% average utilisation
- **Memory:** 60–80% average utilisation
- **Alert if:** CPU or memory sustained > 85% for 15 min → scale node pool

### Node Pool Scaling Commands
```bash
# GCP — scale spot pool
gcloud container clusters resize easychat-cluster \
  --node-pool spot \
  --num-nodes 10 \
  --region us-east1

# AWS — scale via ASG
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name easychat-spot-asg \
  --desired-capacity 10
```

---

## 6. Capacity Review Process

### Monthly Capacity Review Agenda
1. Review past 30 days of traffic growth (compare to forecast)
2. Review HPA scaling events (how often did services hit max?)
3. Review node pool utilisation trend
4. Review database growth (size, query volume, index health)
5. Review Kafka lag trends and partition saturation
6. Update 6-month forecast
7. Identify procurement needs (reserved instances, node pool changes)
8. Document decisions and owners

### Pre-Peak Event Preparation (Product Launches, Campaigns)
1. **T-7 days:** Traffic forecast review with product team
2. **T-3 days:** Pre-scale node pool to peak capacity
3. **T-1 day:** Raise HPA maxReplicas 50% above normal peak
4. **T-0:** SRE monitoring war room active
5. **T+2h:** Post-event capacity review, scale back excess
