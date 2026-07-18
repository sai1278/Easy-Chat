# Nearby Connect — On-Call Procedures & Incident Management
> **Owner:** SRE Team | **Review Cycle:** Quarterly | **Last Updated:** 2026-07-01

---

## 1. On-Call Schedule & Rotation

### Rotation Structure
- **Primary On-Call:** 1 SRE — owns all alerts, first responder (24h × 7d shifts)
- **Secondary On-Call:** 1 SRE — backup if primary unreachable after 5 min
- **Engineering Lead On-Call:** Escalation for SEV-0/1 requiring architectural decisions
- **Shift Length:** 7-day rotations, Monday handoff at 09:00 local time

### Communication Channels
| Channel | Purpose | SLA |
|---|---|---|
| `#oncall-primary` (Slack) | Alert notifications, real-time triage | Respond in < 5 min |
| `#incidents` (Slack) | Incident updates, stakeholder comms | Post updates every 15 min |
| PagerDuty | Page escalation for critical alerts | ACK in < 3 min |
| `sre@company.com` | Post-mortems, reports | Within 24h of incident |

### On-Call Expectations
- Respond to PagerDuty pages within **3 minutes**
- Begin active triage within **5 minutes** of alert
- Post first status update to `#incidents` within **10 minutes**
- Escalate to secondary if not progressing after **15 minutes**

### Handoff Checklist (Every 7 Days)
```
[ ] Review open incidents from past week
[ ] Verify no pending action items from post-mortems
[ ] Review SLO burn status for past 7 days
[ ] Check error budget remaining for each SLO
[ ] Review HPA autoscaler events for unexpected scaling
[ ] Verify Prometheus alert rules are firing correctly (alertmanager status)
[ ] Review DR controller status (dr-controller pod healthy)
[ ] Sign off on handoff in #oncall-primary with "HANDOFF COMPLETE"
```

---

## 2. Severity Classification

| Severity | Definition | Response Time | Escalation |
|---|---|---|---|
| **SEV-0** | Complete platform outage (all users affected) | Immediate page | All-hands in 15 min |
| **SEV-1** | Core feature unavailable (chat, auth, nearby) | Page in < 5 min | Engineering lead in 15 min |
| **SEV-2** | Degraded performance for subset of users | Alert in < 15 min | Team lead in 30 min |
| **SEV-3** | Non-critical feature degraded (notifications) | Ticket in < 1h | Review next day |
| **SEV-4** | Cosmetic / minor inconvenience | Ticket within 24h | Next sprint |

### SEV Classification Matrix

| Condition | Severity |
|---|---|
| API error rate > 5% for all services | SEV-0 |
| Auth service completely down | SEV-0 |
| PostgreSQL primary unreachable | SEV-0 |
| Chat messages failing to deliver | SEV-1 |
| WebSocket reconnect rate > 10% | SEV-1 |
| API p99 latency > 1s for > 5 min | SEV-1 |
| Kafka consumer lag > 10,000 messages | SEV-1 |
| API error rate 1-5% | SEV-2 |
| Nearby discovery degraded (not down) | SEV-2 |
| Redis memory > 90% | SEV-2 |
| Push notifications delayed > 5 min | SEV-3 |
| Media upload slow (not failing) | SEV-3 |

---

## 3. Incident Response Lifecycle

### Phase 1: Detect & Declare (0–5 min)

```
Alert fires in Prometheus
        ↓
PagerDuty pages on-call
        ↓
On-call ACKs within 3 min
        ↓
Quick assessment → Declare incident severity
        ↓
Post to #incidents: "INCIDENT DECLARED: SEV-X — [Brief description]"
                     "IC: @name | Time: HH:MM UTC"
```

**Incident declaration template:**
```
🚨 INCIDENT DECLARED — SEV-[X]
Service: [service name]
Impact: [what users experience]
Start: [HH:MM UTC]
IC (Incident Commander): @name
Triage: in progress
Status page: [update if public-facing]
```

### Phase 2: Triage (5–15 min)

1. Open relevant runbook (see [runbooks.md](./runbooks.md))
2. Identify blast radius: which services, how many users?
3. Check recent deployments: `kubectl rollout history deployment/<svc>`
4. Check alerts dashboard: [Grafana SRE Ops](https://grafana.internal/d/easychat-sre-ops)
5. Post triage update to `#incidents` every **5 minutes**

### Phase 3: Contain (15–30 min)

**Containment actions by type:**

| Incident Type | Containment Action |
|---|---|
| Bad deployment | Rollback: `kubectl rollout undo deployment/<svc>` |
| Traffic spike | Scale HPA max; enable rate limiting at gateway |
| Data layer failure | Activate DR controller failover sequence |
| Security event | Isolate pod via NetworkPolicy; contact security team |
| Canary regression | `kubectl delete ingress <svc>-canary-ingress` |

### Phase 4: Resolve & Restore (30–120 min)

- Confirm SLI metrics returning to baseline
- Verify error rate < 0.1% for 10 consecutive minutes
- Confirm p99 latency < 200ms for 5 consecutive minutes
- Mark incident resolved in PagerDuty
- Post resolution message to `#incidents`

**Resolution template:**
```
✅ INCIDENT RESOLVED — SEV-[X]
Duration: [start] → [end] (X min)
Root Cause: [brief description]
Impact: ~[N] users affected
Resolution: [what was done]
Follow-up: [PIR within 24h | ticket #XYZ]
```

### Phase 5: Post-Incident Review (< 24h for SEV-0/1, < 72h for SEV-2)

See Section 5: Blameless Post-Incident Review (PIR) process.

---

## 4. Escalation Matrix

```
Alert Fires
    │
    ▼
Primary On-Call ──(3 min no response)──► Secondary On-Call
    │
    ├── SEV-0 or SEV-1: Page Engineering Lead immediately (parallel)
    │
    ├── No progress in 15 min ──► Page Engineering Lead
    │
    └── No progress in 30 min ──► Page VP Engineering
```

| Escalation Level | Contact | When |
|---|---|---|
| Secondary On-Call | PagerDuty auto-escalate | Primary no-ACK after 5 min |
| Engineering Lead | PagerDuty manual page | SEV-0/1 or no progress 15 min |
| Database Team | Direct Slack DM | PostgreSQL/Redis data layer issues |
| Security Team | security@company.com | Any suspected security event |
| VP Engineering | PagerDuty + phone call | SEV-0 > 30 min unresolved |
| Legal/PR | Defined process | User data breach, regulatory incident |

---

## 5. Blameless Post-Incident Review (PIR)

### Required for: SEV-0, SEV-1, and any incident that breached SLO error budget

**PIR Document Template:**

```markdown
# PIR: [Incident Title]
Date: YYYY-MM-DD
Severity: SEV-X
Duration: X min
Author: @name
Reviewers: @sre-team

## Impact Summary
- User impact: [N users affected / % of traffic]
- SLO impact: [X% error budget consumed]
- Revenue impact: [if applicable]

## Timeline
| Time (UTC) | Event |
|---|---|
| HH:MM | Alert fired: [alert name] |
| HH:MM | On-call ACKed |
| HH:MM | Root cause identified |
| HH:MM | Containment action taken |
| HH:MM | Service restored |
| HH:MM | Incident resolved |

## Root Cause Analysis
[5-whys analysis]

## Contributing Factors
- [Factor 1]
- [Factor 2]

## What Went Well
- [Detection was fast]
- [Runbook was accurate]

## What Went Poorly
- [Alert was noisy]
- [Rollback took too long]

## Action Items
| Action | Owner | Due Date | Priority |
|---|---|---|---|
| [Specific improvement] | @name | YYYY-MM-DD | P1 |

## Lessons Learned
[Summary paragraph]
```

---

## 6. Communication Templates

### Status Page Update
```
[INVESTIGATING] We are investigating reports of [symptom] affecting [service].
Our team is actively working on a resolution. Next update in 15 minutes.
```

```
[IDENTIFIED] We have identified the root cause of [symptom]: [brief description].
We are implementing a fix. Expected resolution: [time].
```

```
[RESOLVED] The issue affecting [service] has been resolved at [time UTC].
Root cause: [brief]. We will publish a full PIR within 24 hours.
```

### Customer-Facing Email (SEV-0 only, approved by VP)
```
Subject: Service Disruption Notice — [Date]

We experienced a service disruption from [start] to [end] UTC.
During this time, [affected features] were [unavailable/degraded].

We sincerely apologize for the impact on your experience.
Root cause: [brief].
We have taken the following steps to prevent recurrence: [actions].

If you have questions, contact support@company.com.
```
