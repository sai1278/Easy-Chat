# ADR 0002: Cross-Platform Client Development using Flutter & Dart

**ADR Number:** ADR-0002  
**Title:** Cross-Platform Client Development using Flutter & Dart  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
The user-facing mobile application must deliver high-performance real-time chat, animated UI interactions, reactive local state management, and BLE hardware sensor integration across both iOS and Android platforms.

## 2. Problem Statement
Developing separate native codebases (Swift for iOS and Kotlin for Android) doubles engineering overhead, risks feature parity drift, and complicates synchronous WebSocket state handling across platforms.

## 3. Decision
Adopt Flutter (Dart SDK $\ge$ 3.0.0) as the single cross-platform client development framework. The application uses a feature-first directory layout (`features/chat`, `features/nearby`, `features/auth`), compiling ahead-of-time (AOT) to native machine code.

## 4. Evidence
* **Flutter Pubspec Dependencies:** [`apps/frontend/pubspec.yaml:1-35`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/pubspec.yaml#L1-L35)
* **Client App Entry Point:** [`apps/frontend/lib/main.dart:1-155`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/main.dart#L1-L155)
* **Chat Screen Feature UI:** [`apps/frontend/lib/features/chat/presentation/chat_screen.dart:1-120`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/presentation/chat_screen.dart#L1-L120)

## 5. Alternatives Considered
* **React Native:** Rejected due to JavaScript bridge overhead during high-frequency WebSocket state dispatches and dynamic sensor duty-cycling.
* **Native Swift & Kotlin:** Rejected due to doubled resource cost and split codebase maintenance.

## 6. Tradeoffs
* Native platform channel bridging required for low-level BLE hardware scanning (`flutter_reactive_ble`).
* Larger initial application binary size compared to minimal native shells.

## 7. Consequences
* Single codebase delivers 60 FPS UI rendering across iOS and Android.
* Unified reactive state management and offline database synchronization.

## 8. Risks
* Third-party package dependency drift across major Flutter SDK updates.

## 9. Future Considerations
* Target Flutter Web and Desktop builds using existing desktop windowing wrappers.
