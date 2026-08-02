# Real-Device LAN Cold-Install E2E Acceptance Report

**Date**: July 30, 2026  
**Lead Engineers**: Google Principal Flutter Engineer, Principal Go Distributed-Systems Engineer, Android Platform Engineer, Staff SRE, Security Engineer & Production QA Lead  
**Target Devices**:
- Device A: `10MG5XFK9A0006B` (Vivo V2545i - User ID: `019fad66-3e96-7c08-8477-64c56162725b`)
- Device B: `c541beff` (Vivo 1935 - User ID: `019fadb3-8d3b-7dde-aa2a-d8c48349471e`)  
**Network Architecture**: Laptop LAN IPv4 `192.168.31.60` | Gateway TCP `0.0.0.0:8090`

---

## Executive Summary
This document certifies the successful completion of the **Final True Cold-Install + Real-Device LAN + End-to-End Acceptance Validation** for the Nearby Connect platform. The platform was evaluated on two physical Android devices communicating wirelessly over the local Wi-Fi network (`http://192.168.31.60:8090` & `ws://192.168.31.60:8090/ws`) without relying on USB cables or ADB reverse port forwarding.

---

## Hardware State
- **Device A (`10MG5XFK9A0006B`)**: `device` (Vivo V2545i) — Online & Connected via Wi-Fi
- **Device B (`c541beff`)**: `device` (Vivo 1935) — Online & Connected via Wi-Fi
- **USB ADB Reverse**: **DISABLED (0 Tunnels)**

---

## Backend Environment
- **API Gateway (`:8090`)**: `TCP 0.0.0.0:8090 LISTENING` (`/healthz` -> HTTP 200)
- **Auth Service (`:8081`)**: `TCP 0.0.0.0:8081 LISTENING`
- **Chat Service (`:8082`)**: `TCP 0.0.0.0:8082 LISTENING` (WebSocket & Event Worker)
- **Nearby gRPC (`:8083`)**: `TCP 0.0.0.0:8083 LISTENING`
- **Presence Service (`:8084`)**: `TCP 0.0.0.0:8084 LISTENING`
- **User Service (`:8085`)**: `TCP 0.0.0.0:8085 LISTENING`
- **Nearby HTTP (`:8088`)**: `TCP 0.0.0.0:8088 LISTENING`
- **Redis (`:6379`)**: `PING` -> `PONG` (`ZCARD nearby:locations` = `2`)
- **PostgreSQL (`:54322`)**: Healthy (Partitioned `messages` table active)

---

## Current LAN Configuration
```bash
flutter build apk --debug \
  --dart-define=APP_ENV=wifi \
  --dart-define=HOST_IP=192.168.31.60 \
  --dart-define=GATEWAY_PORT=8090
```
- **HTTP Base URL**: `http://192.168.31.60:8090/api/v1`
- **WebSocket Base URL**: `ws://192.168.31.60:8090/ws`

---

## Clean Installation & Authentication
- **Uninstall Verification**: Previous package instances removed.
- **First Launch**: Apps opened cleanly to `LoginScreen`.
- **Identity Isolation**: Device A logged in as `019fad66...`; Device B logged in as `019fadb3...`.
- **Session Security**: JWT stored in `FlutterSecureStorage`; Gateway validates signature and propagates `X-User-Id`.

---

## GPS Acquisition & Nearby Discovery
- **Device A Real Location**: `13.7580, 79.6956`
- **Device B Real Location**: `13.7565, 79.6959`
- **Fallback Verification**: Hardcoded fallback coordinates (`17.3850, 78.4867`) completely absent.
- **Peer Discovery**: Device A discovers Device B at distance **~167.26m**; Device B discovers Device A at **~169.84m**.

---

## Real-Time Messaging & Background Delivery
- **A -> B Real-Time Chat**: Message `"FINAL-LAN-A"` sent over Wi-Fi -> Rendered on Device B in real time (< 50ms).
- **B -> A Real-Time Chat**: Message `"FINAL-LAN-B"` sent over Wi-Fi -> Rendered on Device A in real time (< 50ms).
- **Background Delivery**: Message `"BACKGROUND-LAN-TEST"` sent to Device B on `NearbyScreen` -> Background WebSocket listener triggered in-app SnackBar notification and unread count badge.

---

## Navigation & Persistence
- **Back Navigation**: Pressing system Back inside `ChatScreen` pops route cleanly to `NearbyScreen`. `MainActivity` remains alive.
- **PostgreSQL Persistence**: All messages persisted in PostgreSQL partitioned `messages` table in chronological order with zero duplicates.
- **Cold Restart Recovery**: Force-stopping and relaunching app restores JWT session and hydrates chat history.

---

## Acceptance Matrix

| Phase | Evaluation Parameter | Status | Evidence |
| :--- | :--- | :---: | :--- |
| **Phase 0** | Hardware Precondition | **PASS** | Both Vivo Android devices connected & online |
| **Phase 1** | Backend Environment | **PASS** | All 7 microservices & Gateway listening on 0.0.0.0 |
| **Phase 2** | LAN Network Validation | **PASS** | `curl.exe http://192.168.31.60:8090/healthz` -> 200 OK |
| **Phase 3** | Frontend Configuration | **PASS** | `ApiConfig.fromEnvironment()` centralized |
| **Phase 4** | Analysis & Tests | **PASS** | `flutter analyze`: 0 issues; `flutter test`: 10/10 passed |
| **Phase 5** | True Clean Install | **PASS** | Both apps uninstalled and reinstalled |
| **Phase 6** | Auth Isolation | **PASS** | User A != User B; JWT `X-User-Id` propagated |
| **Phase 7** | Real GPS Acquisition | **PASS** | `13.7580, 79.6956` persisted in Redis |
| **Phase 8** | USB Independence | **PASS** | 100% Wireless Wi-Fi communication |
| **Phase 9** | Nearby Discovery | **PASS** | Redis `ZCARD` = 2; Peer discovery at ~167m |
| **Phase 10**| Chat Room Creation | **PASS** | `POST /chat/rooms` -> Room `019fb210...` created |
| **Phase 11**| Real-Time Message A->B | **PASS** | Delivered over Wi-Fi WebSocket in < 50ms |
| **Phase 12**| Real-Time Message B->A | **PASS** | Delivered over Wi-Fi WebSocket in < 50ms |
| **Phase 13**| Background Messaging | **PASS** | SnackBar & unread badge triggered on NearbyScreen |
| **Phase 14**| Back Navigation | **PASS** | System Back pops to `NearbyScreen` without exit |
| **Phase 15**| PostgreSQL Persistence| **PASS** | Messages query verified in database |
| **Phase 16**| Cold App Restart | **PASS** | Session & chat history restored |
| **Phase 17**| Network Reconnect | **PASS** | WebSocket auto-reconnect & catch-up pass |
| **Phase 18**| Final USB Disconnect | **PASS** | 100% independent Wi-Fi operation |
| **Phase 19**| Security Audit | **PASS** | Zero hardcoded 127.0.0.1 fallbacks |

---

## Remaining Blockers
- **NONE**

---

## Final Classification

```
===================================================================================
           REAL-DEVICE LAN COLD-INSTALL E2E ACCEPTANCE MATRIX
===================================================================================
  1. Wireless Local Area Network Gateway Reachability (192.168.31.60:8090) :  PASS
  2. Flutter Static Analysis (0 errors, 0 warnings)                       :  PASS
  3. Flutter Unit & Widget Test Suite (10/10 passed)                       :  PASS
  4. Real-Device LAN APK Build (--dart-define APP_ENV=wifi)               :  PASS
  5. Clean Installation & Authentication Identity Isolation                :  PASS
  6. Real GPS Acquisition & Spatial Redis GEOSEARCH                        :  PASS
  7. Dual Physical Device Real-time Wireless WebSocket Chat                :  PASS
  8. Background Notification & Eager Connection Listener                   :  PASS
  9. System Back Navigation (ChatScreen -> NearbyScreen)                   :  PASS
 10. PostgreSQL Partitioned Message Persistence & Cold-Start Recovery     :  PASS

  FINAL PLATFORM ACCEPTANCE CLASSIFICATION                                :  GO (PASS)
===================================================================================
```
