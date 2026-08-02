# ADR 0004: Offline Local Storage using Isar NoSQL Database

**ADR Number:** ADR-0004  
**Title:** Offline Local Storage using Isar NoSQL Database  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
The mobile client must support offline message composition, local cache queries, fast search indexing, and real-time reactive UI streaming when disconnected from backend WebSocket servers.

## 2. Problem Statement
SQLite (via `sqflite`) requires manual SQL schema migrations, string-based queries, slow JSON payload serialization, and lacks native Dart reactive query watchers.

## 3. Decision
Adopt Isar NoSQL database as the embedded local persistence engine for Flutter. Isar provides zero-cost object serialization, typed query builders, and native reactive stream watchers (`watch(fireImmediately: true)`).

## 4. Evidence
* **Isar Service Initialization:** [`apps/frontend/lib/core/database/isar_service.dart:1-45`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/core/database/isar_service.dart#L1-L45)
* **Message Entity Definition:** [`apps/frontend/lib/core/database/entities/message_entity.dart:1-21`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/core/database/entities/message_entity.dart#L1-L21)
* **Write-Through Persistence:** [`apps/frontend/lib/features/chat/data/chat_repository.dart:69-76`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/data/chat_repository.dart#L69-L76)

## 5. Alternatives Considered
* **SQLite / Sqflite:** Rejected due to SQL string parsing latency and lack of native object mapping.
* **Hive:** Rejected due to limited query filtering capabilities and lack of multi-index support.

## 6. Tradeoffs
* Binary dependency on native C++ Isar core engine (`isar.so`/`isar.dylib`).
* Requires code generation (`build_runner`) for entity schema changes.

## 7. Consequences
* Sub-millisecond local message reads and write-through caching.
* Reactive UI auto-updates upon local database writes.

## 8. Risks
* Native binary compatibility across new Flutter platform targets.

## 9. Future Considerations
* Implement full-text search (FTS) indexing across local message entities.
