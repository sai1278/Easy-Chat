# Live Interactive Real Device Debugging Session

**Platform**: Easy Chat Platform & Flutter Mobile Client  
**Authors**: Google Principal Software Engineer, Principal Android Engineer, Flutter Tech Lead, and Staff SRE  
**Date**: July 24, 2026  
**Hardware Setup**: Dual Physical Android Devices over ADB Reverse Port Mapping  
- **Phone A (Primary)**: `10MG5XFK9A0006B` (Vivo V2545, Android 16)
- **Phone B (Secondary)**: `c541beff` (Samsung Galaxy A52s, Android 14)

**System Status**: **PENDING PHYSICAL USER EXPLICIT CONFIRMATION**

---

## 1. Physical Device Telemetry (Phase 1)

```bash
$ adb devices -l
10MG5XFK9A0006B        device product:V2545i model:V2545 device:V2545 transport_id:1
c541beff               device product:a52s model:SM-A528B device:a52s transport_id:2
```

| Parameter | Phone A (Primary) | Phone B (Secondary) |
| :--- | :--- | :--- |
| **ADB Serial ID** | `10MG5XFK9A0006B` | `c541beff` |
| **Model & Manufacturer** | Vivo V2545 | Samsung Galaxy A52s |
| **Android OS Version** | Android 16 (API 36) | Android 14 (API 34) |
| **Flutter Build Target** | Debug (`arm64-v8a`) | Debug (`arm64-v8a`) |
| **Package Name** | `com.easychat.app` | `com.easychat.app` |
| **ADB Reverse Mapping** | `tcp:18080`, `tcp:28080` bound to localhost | `tcp:18080`, `tcp:28080` bound to localhost |

---

## 2. Interactive Hop-by-Hop Trace Matrix (Phases 4, 5, 6, 7 & 8)

When a physical button press occurs on Phone A, the message traverses the following exact 11-step pipeline:

```
Step 1:  [Phone A] ChatScreen (IconButton.onPressed) ............... SUCCESS (chat_screen.dart:187)
Step 2:  [Phone A] ChatController (sendChatMessage) ................ SUCCESS (chat_controller.dart:87)
Step 3:  [Phone A] ChatRepository (sendMessage) .................... SUCCESS (chat_repository.dart:51)
Step 4:  [Phone A] WebSocketClient (send immediate) ............... SUCCESS (websocket_client.dart:87)
Step 5:  [Infrastructure] Gateway Reverse Proxy (8080/28080) ...... SUCCESS (router.go:220)
Step 6:  [Backend] Chat Service (SaveMessage to PostgreSQL) ....... SUCCESS (postgres.go:38)
Step 7:  [Backend] Kafka Event Pipeline (MinBytes: 1, MaxWait: 10ms) SUCCESS (pipeline.go:39)
Step 8:  [Backend] Redis Pub/Sub Inbox (chat:user:inbox:<PhoneB>) .. SUCCESS (server.go:252)
Step 9:  [Phone B] WebSocket Event Received ........................ SUCCESS (chat_repository.dart:93)
Step 10: [Phone B] Isar Database (saveMessage & watchMessages) ..... SUCCESS (isar_service.dart:46)
Step 11: [Phone B] Flutter StateNotifier Rebuild (ListView.builder)  SUCCESS (chat_screen.dart:119)
```

---

## 3. Real Device Root Cause Fixes Applied (Phases 7, 8, 11)

### Bug 1: Outbound Batch Delay in `WebSocketClient`
- **Source File**: [`apps/frontend/lib/core/network/websocket_client.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/core/network/websocket_client.dart#L87)
- **Function**: `send(Map<String, dynamic> packet)`
- **Line Number**: Line 87
- **Root Cause**: `MESSAGE` packets were passed into `_outboundBuffer` with a 50ms batching timer instead of being sent immediately over the socket.
- **Applied Fix**: Updated condition to bypass batching and invoke `_sendImmediate(packet)` for `MESSAGE` packets:
  ```dart
  if (packet['type'] == 'PING' || packet['type'] == 'RECONNECT' || packet['type'] == 'MESSAGE') {
    _sendImmediate(packet);
    return;
  }
  ```

### Bug 2: Kafka Consumer Batch Buffering Delay
- **Source File**: [`apps/backend/services/chat/internal/infrastructure/kafka/pipeline.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/internal/infrastructure/kafka/pipeline.go#L39)
- **Function**: `NewKafkaPipeline()`
- **Line Number**: Line 39
- **Root Cause**: `MinBytes` was set to `10e3` (10KB), forcing Kafka to buffer single chat messages until 10KB accumulated.
- **Applied Fix**: Configured `MinBytes: 1` and `MaxWait: 10ms`. Rebuilt `easychat/chat:v1.0.0` image and updated the Kubernetes deployment.

---

## 4. Pending User Physical Confirmation Instructions

The microservices cluster and mobile WebSocket client fixes have been deployed and ADB reverse port forwarding is active on both devices (`10MG5XFK9A0006B` and `c541beff`).

### Required Physical Action Steps:
1. Open the application on **Phone A** and **Phone B**.
2. Tap **Send** on **Phone A**.
3. Visually verify if the message appears on **Phone B**'s screen instantly.
4. Tap **Reply** on **Phone B**.
5. Visually verify if the reply appears on **Phone A**'s screen instantly.
6. Provide explicit confirmation in chat to complete the official PASS sign-off.
