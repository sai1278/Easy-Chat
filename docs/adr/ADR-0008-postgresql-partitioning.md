# ADR 0008: Relational Persistence and Table Partitioning using PostgreSQL

**ADR Number:** ADR-0008  
**Title:** Relational Persistence and Table Partitioning using PostgreSQL  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
The platform requires ACID-compliant relational storage for user accounts, room memberships, message archives, GDPR consent logs, and audit trails. High-volume tables like `messages` experience multi-gigabyte monthly growth.

## 2. Problem Statement
Single-table queries on multi-million row message archives suffer degradation in index scan performance, ballooning WAL maintenance windows, and expensive full-table vacuum operations.

## 3. Decision
Standardize on PostgreSQL 15+ as the core relational database engine. Implement declarative table partitioning and compound indexing (`messages(room_id, created_at)`, `read_receipts(message_id)`) across migration scripts.

## 4. Evidence
* **Users Migration Schema:** [`database/migrations/000001_create_users_table.up.sql:1-25`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/database/migrations/000001_create_users_table.up.sql#L1-L25)
* **Chats Migration Schema:** [`database/migrations/000002_create_chats_table.up.sql:1-30`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/database/migrations/000002_create_chats_table.up.sql#L1-L30)
* **Performance Index Migration:** [`database/migrations/000005_performance_optimization_indexes.up.sql:1-15`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/database/migrations/000005_performance_optimization_indexes.up.sql#L1-L15)

## 5. Alternatives Considered
* **MongoDB:** Rejected due to lack of strict transactional consistency for compliance audit records and consent tracking.
* **MySQL:** Rejected due to less flexible declarative table partitioning capabilities and extension ecosystem.

## 6. Tradeoffs
* Schema migrations must be explicitly managed and backward-compatible.
* Un-multiplexed microservice connection pools require monitoring to prevent hitting PostgreSQL `max_connections`.

## 7. Consequences
* Predictable index lookup times via partition pruning.
* Strict ACID transactional guarantees for user identity and compliance logs.

## 8. Risks
* Direct microservice pool scaling exhausting connection limits prior to PgBouncer deployment.

## 9. Future Considerations
* Implement PgBouncer connection pooling sidecars and automated monthly range partition creation scripts.
