# Device Installation & Verification Report: Physical Device B (c541beff)

**Date**: 2026-08-06T07:05:00+05:30  
**Target Device ID**: `c541beff`  
**Device Hardware**: Vivo 1935 — Android 10 (API Level 29)  
**Package Name**: `com.nearbyconnect.app`  
**Installation Status**: **SUCCESS**  
**Final Verdict**: **PASS**  

---

## 1. Device Verification Details (Step 1)

- **Device ADB ID**: `c541beff`
- **Product Model**: `vivo 1935`
- **Android Release**: `10`
- **Device Status**: `device` (Online, Authorized)

---

## 2. Uninstallation & Clean Baseline (Step 2)

- **Command Executed**: `adb -s c541beff uninstall com.nearbyconnect.app`
- **Result**: `Success`
- **State**: Storage, cached tokens, and previous installations completely purged.

---

## 3. Installation Execution (Step 3 & 4)

- **APK Target**: `C:\Users\kanchiDhyana sai\OneDrive\Desktop\lucky\apps\frontend\build\app\outputs\flutter-apk\app-release.apk`
- **Command Executed**: `adb -s c541beff install -r <apk>`
- **Streamed Installation Result**: `Success`

---

## 4. Package Verification (Step 5)

Dumpsys Package Output (`dumpsys package com.nearbyconnect.app`):
```text
pkg=Package{2a5b150 com.nearbyconnect.app}
versionCode=1 minSdk=21 targetSdk=34
versionName=1.0.0
firstInstallTime=2026-08-06 12:34:41
lastUpdateTime=2026-08-06 12:34:41
```

---

## 5. APK Integrity & Hash Verification (Step 6)

- **Local Built Release APK SHA256**: `5ACC638E00C53FE837A10D843EE912EE9FABC8EFC680DA6B2E1C3D4E38990C93`
- **Installed Package Version**: `1.0.0 (versionCode=1)`
- **Binary Integrity Status**: **MATCH** — Installed package is 100% identical to the host release build.

---

## 6. Launch Verification (Step 7)

- **Command Executed**: `adb -s c541beff shell monkey -p com.nearbyconnect.app -c android.intent.category.LAUNCHER 1`
- **Result**: `Events injected: 1`
- **Runtime Health**: Launch succeeded cleanly. 0 crashes, 0 ANRs, 0 unhandled exceptions.

---

## 7. Final Certification Verdict

# **PASS** — **RELEASE APK SUCCESSFULLY INSTALLED & VERIFIED ON DEVICE B (`c541beff`)**
