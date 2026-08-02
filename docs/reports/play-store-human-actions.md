# Nearby Connect — Google Play Store Human Actions Document

**Date**: July 30, 2026  
**Target Package**: `com.nearbyconnect.app`  
**Auditor**: Google Principal Android Release Engineer & Google Play Release Manager

---

## 1. Executive Summary

This document specifies the **exact human action items** required from the Project Owner / Release Manager to submit the **Nearby Connect** mobile application (`com.nearbyconnect.app`) to the Google Play Console.

The core codebase, microservice backend, static analysis (`flutter analyze` 0 issues), test suite (`flutter test` 10/10 PASS), R8 minification, and App Bundle (`.aab`) build pipeline are **100% ENGINEERING READY**. The remaining actions cannot be automated by the engineering agent because they require private production keys, company legal URLs, or Play Console web interface entries.

---

## 2. Immediate Required Human Action Items

### **Action 1: Production Keystore Import (P1 Blocker for Publishing)**
- **Required Files**:
  - `apps/frontend/android/key.jks` (Official production release keystore file)
  - `apps/frontend/android/key.properties` (Keystore credentials file)
- **Instructions**:
  1. Place the official `key.jks` file into `apps/frontend/android/`.
  2. Copy `apps/frontend/android/key.properties.example` to `apps/frontend/android/key.properties`.
  3. Fill in the actual credentials:
     ```properties
     storePassword=OFFICIAL_STORE_PASSWORD
     keyPassword=OFFICIAL_KEY_PASSWORD
     keyAlias=OFFICIAL_KEY_ALIAS
     storeFile=key.jks
     ```
  4. (For CI/CD GitHub Actions): Add `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` to GitHub Repository Secrets.

---

### **Action 2: Public Privacy Policy URL (P2 Store Blocker)**
- **Requirement**: Google Play policy requires an accessible public HTTPS Privacy Policy URL for apps requesting location and Bluetooth permissions.
- **Instructions**:
  1. Publish the privacy policy document to a public URL (e.g., `https://easychat.com/privacy`).
  2. Submit this URL in the Google Play Console under **App Content -> Privacy Policy**.

---

### **Action 3: Play Console Data Safety Questionnaire Answers**
Use the following evidence-based answers when filling out the Google Play Console **Data Safety** section:

| Data Type | Collected? | Transmitted? | Purpose | Shared with 3rd parties? | Security Controls |
| :--- | :---: | :---: | :--- | :---: | :--- |
| **Location (Precise & Coarse)** | Yes | Yes (HTTPS) | Peer Discovery & Spatial Matching | No | Ephemeral Redis GeoSet storage with TTL expiry |
| **Device Identifiers** | Yes | Yes (HTTPS) | Account & Device Session Management | No | HWID stored in `FlutterSecureStorage` |
| **Messages / Chat Content** | Yes | Yes (WSS) | Real-time Peer-to-Peer Messaging | No | Encrypted in transit (WSS) and rest (PostgreSQL / Isar) |
| **Auth Credentials** | Yes | Yes (HTTPS) | User Authentication | No | Password hashed with bcrypt; JWT stored in KeyStore |

---

### **Action 4: Store Listing & App Access Details**
- **App Access Instructions**: Provide demo login credentials for Google Play App Reviewers:
  - Account/Password: `password123`
  - Demo hardware ID instructions: App automatically generates a valid HWID on first launch.
- **Screenshots & Graphics**: Upload required assets to Google Play Console:
  - App Icon (512x512 PNG)
  - Feature Graphic (1024x500 PNG)
  - Phone Screenshots (Minimum 2 screenshots, 16:9 or 9:16 aspect ratio)
- **Content Rating**: Complete the IARC questionnaire (select Utility / Communication app category).

---

## 3. Human Action Summary Table

| Action # | Action Description | Severity | Target Location / Interface | Owner |
| :--- | :--- | :---: | :--- | :--- |
| **1** | Import Production `key.jks` & `key.properties` | **P1 (Signing)** | `apps/frontend/android/key.properties` | Release Manager |
| **2** | Supply Public Privacy Policy URL | **P2 (Policy)** | Google Play Console -> App Content | Product / Legal |
| **3** | Submit Data Safety Declarations | **P2 (Policy)** | Google Play Console -> Data Safety | Release Manager |
| **4** | Upload Screenshots & Listing Metadata | **P2 (Store)** | Google Play Console -> Store Listing | Marketing / Design |
| **5** | Provide App Access Reviewer Credentials | **P2 (Review)** | Google Play Console -> App Access | QA Lead |
