# Redis Cluster Operational & Architecture Manual
**Enterprise Redis Infrastructure, Scripting Specs, and Failure Recovery Runbooks**

---

## 1. Architectural Review Decisions

### 1.1. Decision 1: Adaptive H3 Resolution 5 Geospatial Sharding
*   **Evaluation:** The original proposal suggested H3 Resolution 4 (approx. $11,000\text{ km}^2$, edge length ~65km). In mega-metropolitan zones (e.g., Tokyo, London, New York), this resolution is too coarse, causing hundreds of thousands of active profiles to map to a single Redis Sorted Set key. This creates a hot-key performance bottleneck on a single cluster node during peak write times.
*   **Final Decision:** Adopt **Adaptive H3 Resolution 5** (approx. $2,523\text{ km}^2$, edge length ~25km) for the geospatial keyspace sharding prefix.
*   **Engineering Rationale:** 
    *   **Hot-key Mitigation:** Resolution 5 divides metropolitan density into smaller segments, distributing writing operations and memory footprints across the cluster.
    *   **Proximity Boundary Logic:** For a maximum user discovery radius of 200m, searching the client's snapped H3 cell and its 6 immediate neighbors covers all boundary users. Since a Resolution 5 cell has a minimum width of ~30km, the neighbor cells are large enough to ensure no nearby user is ever missed, keeping command executions under O(log N).
    *   **Memory Efficiency:** Individual sharded geospatial sorted sets are kept small, ensuring quick `GEORADIUS` sorting.

### 1.2. Decision 2: Asynchronous Master-Replica Replication
*   **Evaluation:** We evaluated synchronous replication via the `WAIT` command versus asynchronous stream updates.
*   **Final Decision:** Standardize on **Asynchronous Replication** for all transient states.
*   **Engineering Rationale:**
    *   **Latency Constraint:** Enforcing synchronous validation requires waiting for replicas to acknowledge writes before returning execution to the client, which adds network round-trip overhead and violates our latency goal of $<100\text{ms}$.
    *   **Acceptable Trade-off:** Presence heartbeats, typing status indicators, and rate limits are transient. If a primary node fails before syncing to its replica, the loss of a 30-second heartbeat or typing flag does not affect core database integrity. Re-connections automatically restore the state on the new promoted master.

---

## 2. Key Namespace & TTL Policy Specification

| Namespace & Pattern | Redis Type | Default TTL | Eviction Class | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| `nearby:presence:active:{user_id}` | `STRING` | 45 Seconds | Volatile | User presence online heartbeat |
| `nearby:presence:geo:{h3_res5_index}` | `ZSET` | 45 Seconds (member-based) | Volatile | Geospatial matching index |
| `nearby:session:meta:{user_id}` | `HASH` | 24 Hours | Volatile | Cryptographic session details |
| `nearby:chat:typing:{room_id}:{user_id}`| `STRING` | 3 Seconds | Volatile | Active room typing indicator |
| `nearby:rate:sliding:{user_id}:{endpoint}`| `ZSET` | 60 Seconds | Volatile | Rate limiting request logs |
| `nearby:lock:{resource_name}` | `STRING` | 5 Seconds | Volatile | Re-entrant distributed lock key |

*   **Eviction Policy:** Configure `maxmemory-policy` to `volatile-lru`. If memory threshold is reached, Redis will evict expired or temporary keys (like rate limit logs and typing indicators) first, protecting persistent session states.

---

## 3. Geospatial Search & H3 Boundary Matching

Proximity matching is designed to find nearby users within a configured radius (100m, 150m, 200m).

```
                      +-----------------------------+
                      |   Client GPS Coordinate     |
                      +-----------------------------+
                                     |
                                     v
                      +-----------------------------+
                      | Snap to H3 Res 10 (Fuzzing) |
                      +-----------------------------+
                                     |
                                     v
                      +-----------------------------+
                      | Find Coarse H3 Res 5 Cell   |
                      +-----------------------------+
                                     |
                +--------------------+--------------------+
                |                                         |
     (Within Res 5 Boundary)                      (Near Res 5 Border)
                v                                         v
+-------------------------------+         +-------------------------------+
|  Query Single Res 5 Geo Key   |         |  Query Target Res 5 + 6 Neighbor|
|  nearby:presence:geo:{cell}   |         |  Geo Keys in Parallel           |
+-------------------------------+         +-------------------------------+
```

### 3.1. Proximity Match Algorithm
1.  **Coordinate Fuzzing:** The Flutter client retrieves raw coordinates, snaps them to the center of the local Resolution 10 H3 hexagon (resolving exact GPS tracking risks), and sends this fuzzed point to the server.
2.  **Determine Shard Key:** The backend identifies the parent Resolution 5 cell containing the fuzzed coordinate (e.g., `851f`).
3.  **Perform Search:**
    *   If the user's coordinate is far from the Resolution 5 cell borders, execute a single query:
        ```redis
        GEORADIUSBYMEMBER nearby:presence:geo:{851f} <user_id> 200 m WITHDIST
        ```
    *   If the user is within 200m of a cell border, query the target cell and its neighboring cells in parallel, merging the results on the backend server.

---

## 4. Operational Failure Recovery Runbooks

### 4.1. Runbook 1: Node Failure & Replica Promotion
If a primary master node fails, the cluster automatically initiates failover:
1.  **Detect Outage:** Master nodes detect the missing heartbeat and flag the node as `FAIL`.
2.  **Promote Replica:** The remaining master nodes vote to promote the failed master's replica to primary.
3.  **Manual Verification:** Run the cluster CLI command from any node to confirm slot reassignment:
    ```bash
    redis-cli -p 6379 cluster nodes
    ```
    Assert that the promoted replica now shows as `master` and slot allocations are intact.

### 4.2. Runbook 2: Node Rebalancing
When adding new nodes or recovering from a split-brain event, rebalance slot allocations:
1.  **Dry Run Check:**
    ```bash
    redis-cli --cluster rebalance 127.0.0.1:6379 --cluster-use-empty-masters --cluster-simulate
    ```
2.  **Execute Rebalance:**
    ```bash
    redis-cli --cluster rebalance 127.0.0.1:6379 --cluster-use-empty-masters
    ```

---

## 5. Security & Network Isolation Configuration

*   **Network Isolation:** Redis Cluster nodes must reside in an isolated VPC database subnet. All ports (internal port `6379`, cluster bus port `16379`) must be blocked from public egress using firewall rules, allowing incoming connections only from the API Gateway and backend microservice subnets.
*   **TLS Transport Encryption:** Standardize on TLS v1.3 for all client-to-server and node-to-node communications.
*   **Authentication (ACL):** Enforce ACL authentication using the rules configured in `acl.conf`. Do not use the default admin user.
