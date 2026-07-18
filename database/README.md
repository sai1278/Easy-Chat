# Nearby Connect Database Operations & Architecture Manual
**PostgreSQL Administration, Privacy Controls, and Partition Management**

This directory houses the migrations, configurations, and verification test suites for the Nearby Connect platform database.

---

## 1. Database Migrations & Structure

Migrations are organized sequentially under `migrations/`:
*   `000001_init_schema.up.sql`: Core user, device, and hash partitioning setups.
*   `000002_chat_and_messaging.up.sql`: Chat rooms, messages, presence tracking, and sessions.
*   `000003_jobs_and_auditing.up.sql`: Audit logging, background job queues, and retention procedures.

To apply migrations locally, run:
```bash
./tests/validate_db.sh
```
This boots up a Docker PostgreSQL container, validates the migrations apply, runs behavior test assertions (cascade deletes, partition routing, retention cleaning), executes rollback scripts, and shuts down safely.

---

## 2. Inactive Profile Retention Policy

The profile retention logic is executed by invoking the PL/pgSQL function:
```sql
SELECT purge_inactive_profiles(180);
```
This hard-deletes profiles, push tokens, active sessions, and messages for users whose `updated_at` column is older than the configured threshold (e.g. 180 days).

### 2.1. Dynamic Duration Configuration
The duration parameter (`180` days) must not be hardcoded in application logic. Go microservices read this value from system environmental variables or ConfigMaps:
*   `RETENTION_PURGE_DAYS_THRESHOLD=180`
*   The Go background manager executes a cron scheduler (e.g. daily at 02:00 UTC) that triggers the database execution query with the parsed parameter: `SELECT purge_inactive_profiles($1)`.

---

## 3. Users Table Hash Partition Expansion

The `users` table is initially configured with **16 hash partitions** (`users_p0` to `users_p15`). When user scale outgrows this boundary, the partition count can be expanded to 32 or 64 using a zero-downtime partitioning migration script.

### 3.1. Expansion Walkthrough (e.g. splitting p0 to p0_a and p0_b at modulus 32)
1.  **Create New Target Partitions:**
    Define partitions matching the new modulus (e.g., Modulus 32, Remainder 0 and 16).
2.  **Detach Old Partition:**
    Detach the target partition under modulus 16:
    ```sql
    ALTER TABLE users DETACH PARTITION users_p0;
    ```
3.  **Migrate Existing Data:**
    Move records from `users_p0` into the parent table (Postgres will automatically route them into the new modulus 32 partitions).
4.  **Drop Old Partition:**
    Once data is cleared, drop the empty `users_p0` table.

---

## 4. PostGIS Migration Roadmap

Currently, Nearby Connect utilizes **client-side H3 index grid strings** (Resolution 10) inside the `presence` table to perform proximity matching within Redis memory, ensuring location privacy on the primary database level. If future features require complex polygon overlays, geofenced boundaries, or precise geometry mapping, PostGIS can be activated with zero schema rebuilds.

### 4.1. Transition Checklists
1.  **Install Extension:**
    Add `CREATE EXTENSION postgis;` in a new migration script.
2.  **Add Spatial Columns:**
    Add a geometry coordinate column to `presence`:
    ```sql
    ALTER TABLE presence ADD COLUMN geom GEOMETRY(Point, 4326);
    ```
3.  **Populate Coordinates:**
    Run a migration task that translates existing H3 strings into approximate lat/long point fields to backfill coordinates.
4.  **Create Spatial Indexes:**
    Add a GIST spatial index:
    ```sql
    CREATE INDEX idx_presence_geom ON presence USING GIST (geom);
    ```
5.  **Refactor Queries:**
    Replace string-matching logic with PostGIS distance checks:
    ```sql
    SELECT user_id FROM presence 
    WHERE ST_DWithin(geom, ST_MakePoint(longitude, latitude)::geography, 200);
    ```

---

## 5. System Observability Extensions

For production monitoring, install the following extensions inside `postgresql.conf`:
*   `pg_stat_statements`: Captures execution statistics of all SQL statements executed on the server, tracking execution times, read/write blocks, and call frequencies to trace slow queries.
*   `pg_stat_kcache`: Extends telemetry monitoring to record real-time system CPU and OS-level storage cache reads per query.
