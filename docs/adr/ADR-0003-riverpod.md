# ADR 0003: Declarative State Management with Flutter Riverpod

**ADR Number:** ADR-0003  
**Title:** Declarative State Management with Flutter Riverpod  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
The Flutter client requires compile-safe dependency injection, asynchronous stream handling, reactive state propagation for WebSocket connectivity, and room-scoped state management.

## 2. Problem Statement
Traditional Flutter `BuildContext`-dependent state mechanisms (e.g. `Provider` or imperative `setState`) suffer from runtime `ProviderNotFoundException` risk, lack parameterized family caching, and complicate mock dependency overrides in unit testing.

## 3. Decision
Standardize on `flutter_riverpod` (v2.x) using `StateNotifierProvider.family` for parameterized state management (`ChatSessionArgs(roomId, peerId)`). Dependency injection is enforced at app startup in [`main.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/main.dart#L51) using `ProviderScope` overrides.

## 4. Evidence
* **Provider Scope Overrides:** [`apps/frontend/lib/main.dart:51-72`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/main.dart#L51-L72)
* **Chat Controller Family Provider:** [`apps/frontend/lib/features/chat/presentation/chat_controller.dart:43-108`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/presentation/chat_controller.dart#L43-L108)

## 5. Alternatives Considered
* **BLoC (Business Logic Component):** Rejected due to high stream boilerplate overhead for simple state transitions.
* **GetX:** Rejected due to global state mutation magic, lack of compile-time safety, and poor testability.

## 6. Tradeoffs
* Learning curve for Riverpod 2.0 family modifier parameter passing.
* Memory management requires explicit disposal of unused family state notifiers.

## 7. Consequences
* Compile-time safety guaranteed for all state dependencies.
* Seamless test isolation via `ProviderScope.overrides`.

## 8. Risks
* StateNotifier lifetime misconfiguration resulting in stale room controller instances.

## 9. Future Considerations
* Migrate to Riverpod 3.0 code generator (`@riverpod` annotations) for automated provider generation.
