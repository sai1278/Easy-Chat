# ADR 0009: Proximity Matching using Uber H3 Hexagonal Spatial Indexing

**ADR Number:** ADR-0009  
**Title:** Proximity Matching using Uber H3 Hexagonal Spatial Indexing  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
The Nearby Service must compute real-time geographical proximity between mobile devices without exposing exact latitude/longitude coordinates to third-party clients.

## 2. Problem Statement
Raw GPS distance calculations (Haversine formula over PostgreSQL PostGIS) on every client location update introduce heavy $O(N^2)$ CPU computation and breach privacy requirements by exposing granular coordinates.

## 3. Decision
Adopt Uber H3 Discrete Global Grid System (Hexagonal Hierarchical Spatial Index). Location updates are quantized server-side into H3 spatial cells (Resolution 8/9). Proximity queries look up users sharing matching cell IDs or k-ring neighbor cells in Redis.

## 4. Evidence
* **Redis H3 Spatial Query Engine:** [`apps/backend/services/nearby/internal/infrastructure/cache/redis.go:45`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/nearby/internal/infrastructure/cache/redis.go#L45)
* **Presence H3 Location Endpoint:** [`apps/backend/services/presence/cmd/presence/main.go:87`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/presence/cmd/presence/main.go#L87)

## 5. Alternatives Considered
* **Geohash (Bounding Box):** Rejected due to edge distortion and non-uniform neighbor distances at cell boundaries.
* **PostGIS Point Buffer Queries:** Rejected due to excessive database IOPS under high-frequency device mobility updates.

## 6. Tradeoffs
* Hexagonal quantization introduces spatial approximation error bounded by cell radius (~460m at Res 8).

## 7. Consequences
* $O(1)$ constant time proximity lookups using Redis sets (`SINTER` / `SUNION`).
* Built-in user location privacy by masking raw GPS coordinates into cell hashes.

## 8. Risks
* Boundary conditions where two nearby users sit in adjacent non-queried k-ring cells.

## 9. Future Considerations
* Dynamic H3 resolution scaling based on urban vs rural user density.
