# Nearby Connect — Error Budget Policy & SLO Framework
> **Owner:** SRE + Product Engineering | **Review Cycle:** Monthly

---

## 1. SLO Inventory

| SLO ID | Service | SLI Type | Target | Window | Error Budget |
|---|---|---|---|---|---|
| `SLO-01` | All APIs | Request availability (non-5xx) | **99.9%** | 30 days | 43.2 min/month |
| `SLO-02` | All APIs | p99 latency < 200ms | **99%** | 30 days | 7.2 hr/month |
| `SLO-03` | Gateway/Chat | WebSocket session uptime | **99.9%** | 7 days | 10.1 min/week |
| `SLO-04` | Auth/User/Chat/Nearby | DB query p99 < 50ms | **99%** | 30 days | 7.2 hr/month |
| `SLO-05` | Presence/Chat | Redis operation p99.9 < 10ms | **99.9%** | 24 hours | 1.44 min/day |
| `SLO-06` | Chat/Notification | Kafka consumer lag < 500 msgs | **95%** | 1 hour | 3 min/hour |

---

## 2. Error Budget Calculation

### Formula
```
Error Budget = (1 - SLO Target) × Window Duration
```

### Budget Table

| SLO | Target | Window | Allowed Downtime/Errors |
|---|---|---|---|
| SLO-01 API Availability | 99.9% | 30 days | 43.2 minutes |
| SLO-02 API Latency | 99% | 30 days | 7.2 hours |
| SLO-03 WebSocket | 99.9% | 7 days | 10.1 minutes |
| SLO-04 DB Latency | 99% | 30 days | 7.2 hours |
| SLO-05 Redis Latency | 99.9% | 24 hours | 86.4 seconds |
| SLO-06 Kafka Lag | 95% | 1 hour | 3 minutes |

---

## 3. Error Budget Tracking

### PromQL: Remaining Budget (SLO-01)
```promql
# Remaining error budget as % of total budget
(
  (0.001 - (
    sum(rate(http_requests_total{status=~"5.."}[30d]))
    /
    sum(rate(http_requests_total[30d]))
  )) / 0.001
) * 100
```

### PromQL: Burn Rate (SLO-01, 1h window)
```promql
# Multiples of budget being consumed
(
  sum(rate(http_requests_total{status=~"5.."}[1h]))
  /
  sum(rate(http_requests_total[1h]))
) / 0.001
```

### Budget Burn Rate Interpretation
| Burn Rate | Meaning | Budget Exhaustion |
|---|---|---|
| 1× | Exactly on target | At end of 30-day window |
| 2× | Twice as fast | 15 days |
| 6× | 6× consumption | 5 days |
| 14.4× | Consuming 2% in 1h | ~2 hours |
| 36× | Consuming 5% in 1h | ~50 minutes |

---

## 4. Error Budget Policy

### When Budget is > 50% Remaining
- ✅ Normal deployment cadence permitted
- ✅ Experiments and risky changes permitted
- ✅ Canary deployments proceed normally
- ✅ Infrastructure maintenance windows can proceed

### When Budget is 25–50% Remaining
- ⚠️ Increase deployment review rigor
- ⚠️ Require canary monitoring period > 30 min before full rollout
- ⚠️ No same-day rollback of infrastructure changes
- ⚠️ SRE must approve any schema migrations

### When Budget is 10–25% Remaining
- 🔴 Engineering lead must approve all production deployments
- 🔴 Canary traffic limited to 5% for first 2 hours
- 🔴 All planned maintenance windows postponed
- 🔴 Weekly error budget review in engineering all-hands

### When Budget is < 10% Remaining (Budget Warning)
- 🚨 **FEATURE FREEZE** — No new feature deployments
- 🚨 Only reliability fixes and hotfixes to production
- 🚨 Immediate SRE + engineering lead meeting
- 🚨 Reliability investment sprint begins next planning cycle

### When Budget is 0% (Budget Exhausted)
- ❌ **DEPLOYMENT FREEZE** — Zero deployments until recovery
- ❌ All engineering effort redirected to reliability
- ❌ Root cause analysis mandatory within 48 hours
- ❌ VP Engineering notified with recovery plan
- ❌ Deployments resume only after 7-day budget recovery with < 1× burn rate

---

## 5. Error Budget Review Cadence

| Frequency | Forum | Participants | Output |
|---|---|---|---|
| **Daily** | Async Slack report in #slo-status | SRE team | Budget % remaining + trend |
| **Weekly** | SRE Weekly Sync | SRE + engineering leads | Budget review + action items |
| **Monthly** | SLO Review Meeting | SRE + Product + Engineering | SLO target review, budget reset |
| **Quarterly** | SLO Audit | All engineering + management | SLO target adjustment decisions |

---

## 6. SLO Target Adjustment Process

SLO targets should be reviewed when:
1. Budget is consistently > 95% remaining (SLO is too loose; tighten it)
2. Budget is consistently < 20% remaining (SLO may be too strict; investigate before loosening)
3. Significant architecture change (e.g., new data layer, major refactor)

**Adjustment process:**
1. SRE proposes new target with data justification (4-week trend analysis)
2. Product reviews user impact implications
3. Engineering reviews implementation feasibility
4. Management approves revised SLO
5. New targets deployed to Prometheus recording rules and alert thresholds

---

## 7. SLI Equations (Prometheus PromQL)

### SLO-01: API Availability
```promql
# Good events
sum(rate(http_requests_total{status!~"5.."}[window]))

# Total events  
sum(rate(http_requests_total[window]))

# SLI = good / total
```

### SLO-02: API Latency
```promql
# Good events (requests < 200ms)
sum(rate(http_request_duration_seconds_bucket{le="0.2"}[window]))

# Total events
sum(rate(http_request_duration_seconds_count[window]))
```

### SLO-03: WebSocket Availability
```promql
# Good events (sessions that did not fail)
sum(rate(websocket_total_sessions[window])) - sum(rate(websocket_failures_total[window]))

# Total events
sum(rate(websocket_total_sessions[window]))
```

### SLO-04: DB Query Latency
```promql
# Good events (queries < 50ms)
sum(rate(db_query_duration_seconds_bucket{le="0.05"}[window])) by (service)

# Total events
sum(rate(db_query_duration_seconds_count[window])) by (service)
```
