# Internet E2E Physical Device Acceptance Plan & Protocol

**Date**: August 2, 2026  
**Auditors**: Principal QA Lead & Android Release Engineer  
**Package Namespace**: `com.nearbyconnect.app`  
**Target Hardware**: Physical Vivo Android Devices (`10MG5XFK9A0006B` & `c541beff`)

---

## 1. Physical Device Test Scenarios Matrix

| Test ID | Device A Network | Device B Network | Acceptance Criteria | Target Status |
| :--- | :--- | :--- | :--- | :---: |
| **TEST A** | Wi-Fi Subnet X | Wi-Fi Subnet Y | Bidirectional chat & Nearby GEOSEARCH match | **PENDING CLOUD DEPLOYMENT** |
| **TEST B** | Wi-Fi Subnet X | 4G/5G Mobile Data | Bidirectional chat & Nearby GEOSEARCH match | **PENDING CLOUD DEPLOYMENT** |
| **TEST C** | 4G/5G Mobile Data | 4G/5G Mobile Data | Bidirectional chat & Nearby GEOSEARCH match | **PENDING CLOUD DEPLOYMENT** |
| **TEST D** | Wi-Fi Toggle OFF -> ON | Cellular Data | Automatic heartbeat re-registration & WebSocket reconnect without app data clear | **PENDING CLOUD DEPLOYMENT** |

---

## 2. Verified Local Baseline vs. Pending Internet Gate

- **Same-Wi-Fi Physical Dual-Device Testing**: **100% PASS** on local Wi-Fi LAN (`http://192.168.31.60:8090`).
- **Cross-Wi-Fi / Mobile Data Testing**: Pending cloud cluster deployment and DNS A record update for `api.easychat.com`.
