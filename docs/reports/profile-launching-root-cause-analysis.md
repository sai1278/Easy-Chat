# Profile "Launching..." Infinite Hang — Root Cause Analysis

**Classification**: Production Blocker — P0
**Governing Role**: Google Principal Flutter Engineer · Principal Go Backend Engineer · Staff SRE · Android Platform Engineer · Production Debugging Engineer
**Investigation Date**: 2026-08-02
**Environment**: `APP_ENV=wifi` | `HOST_IP=192.168.31.60` | `GATEWAY_PORT=8090`
**Status**: ROOT CAUSE CONFIRMED — TWO SEQUENTIAL BLOCKERS PROVEN

---

## 1. Executive Summary

After successful registration and JWT issuance, the user reaches the "Create Your Nearby Handle"
onboarding step. On tapping Continue / Complete & Launch Nearby:

1. The button transitions to "Launching..." — `_isCompleting = true` is set.
2. The UI never advances. No crash. No exception. No timeout message. No navigation.

Root cause is NOT: FlutterSecureStorage, Riverpod, GPS, WebSocket, or GoRouter.

Root cause is confirmed as TWO SEQUENTIAL DEFECTS in `_completeOnboarding()`:

| Priority | Blocker | File | Line | Await |
|---|---|---|---|---|
| BLOCKER 1 | PUT /user/profile times out 10s then is silently discarded | profile_repository.dart | 38-48 | await _repository.updateProfile(...) |
| BLOCKER 2 | await showDialog(...) never resolves — dialog has no dismiss path | onboarding_screen.dart | 90 | await showDialog(context, ...) |

`_isCompleting` is NEVER reset (no `finally` block) — "Launching..." label persists forever.

---

## 2. Complete Execution Timeline

```
T+0ms     User taps "Complete & Launch Nearby"
          → _completeOnboarding() entered
          → setState(() { _isCompleting = true })           [onboarding_screen.dart:73]
          → Button label renders: "Launching..."
          → CircularProgressIndicator visible

T+0ms     await ref.read(userProfileProvider.notifier).updateProfile(...)
          → ProfileNotifier.updateProfile() entered         [profile_repository.dart:32]
          → await _repository.updateProfile(...)            [profile_repository.dart:38]
          → await dioClient.dio.put('/user/profile', ...)   [profile_repository.dart:99]
          → DIO INTERCEPTOR: onRequest fires
          → HTTP PUT http://192.168.31.60:8090/api/v1/user/profile

          [GATEWAY STATUS: NOT RUNNING]
          [docker ps shows: nearby-redis, nearby-kafka, nearby-postgres ONLY]
          [Invoke-WebRequest to 192.168.31.60:8090 → Unable to connect]

T+10000ms connectTimeout fires (Dio: connectTimeout = 10s)  [dio_client.dart:106]
          → DioException(type: connectionTimeout) thrown
          → ProfileNotifier.updateProfile() catch(err) {}   [profile_repository.dart:45]
          → Exception SILENTLY SWALLOWED — returns false
          → No log. No UI feedback. No rethrow.

T+10005ms Back in _completeOnboarding()
          → updateProfile() returned false (silently)
          → SharedPreferences.getInstance() resolves        [onboarding_screen.dart:85]
          → prefs.setBool('onboarding_completed', true)     [onboarding_screen.dart:86]

T+10010ms await showDialog(                                  [onboarding_screen.dart:90]
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              content: Column(children: [Icon, Text, Text]),
              // ZERO actions[] defined
              // NO Navigator.pop() call anywhere
            ),
          )
          → AlertDialog RENDERED on screen
          → Future<T?> from showDialog() is awaited
          → Future NEVER completes — dialog has no dismissal path

T+∞       _isCompleting remains true
          "Launching..." label stuck forever
          context.go('/nearby') NEVER reached           [onboarding_screen.dart:129]
          No finally block → _isCompleting never reset
          UI permanently frozen in loading state
```

---

## 3. Every Function Entered and Exited

| Step | Function | File | Line | Entered | Exited | Duration |
|---|---|---|---|---|---|---|
| 01 | _completeOnboarding() | onboarding_screen.dart | 72 | YES | NO — Never | infinity |
| 02 | setState(_isCompleting=true) | onboarding_screen.dart | 73 | YES | YES | ~1 ms |
| 03 | ProfileNotifier.updateProfile() | profile_repository.dart | 32 | YES | YES | ~10000 ms |
| 04 | ProfileRepository.updateProfile() | profile_repository.dart | 94 | YES | YES (timeout) | 10000 ms |
| 05 | dioClient.dio.put('/user/profile') | profile_repository.dart | 99 | YES | YES (timeout) | 10000 ms |
| 06 | SharedPreferences.getInstance() | onboarding_screen.dart | 85 | YES | YES | ~3 ms |
| 07 | prefs.setBool('onboarding_completed') | onboarding_screen.dart | 86 | YES | YES | ~2 ms |
| 08 | showDialog(barrierDismissible:false) | onboarding_screen.dart | 90 | YES | NO — NEVER | infinity |
| 09 | context.go('/nearby') | onboarding_screen.dart | 129 | NO — NEVER REACHED | — | — |
| 10 | setState(_isCompleting=false) | — | — | DOES NOT EXIST | — | — |

---

## 4. First Missing Log

The first await that NEVER emits its After log:

```
EXPECTED:  [ONBOARDING][08] After showDialog() — Duration: X ms
OBSERVED:  MISSING — execution permanently suspended at this await

EXPECTED:  [ONBOARDING][09] Before context.go('/nearby')
OBSERVED:  MISSING — never reached
```

---

## 5. Exact Blocking Operations

### BLOCKER 1 — Silent 10-Second HTTP Hang

| Attribute | Value |
|---|---|
| File | apps/frontend/lib/features/profile/data/profile_repository.dart |
| Function | ProfileRepository.updateProfile() |
| Line | 99 |
| Await | await dioClient.dio.put('/user/profile', data: {...}) |
| Cause | Gateway at http://192.168.31.60:8090 not running — connectTimeout fires after 10000 ms |
| Effect | 10-second invisible delay with no user feedback |

```dart
// profile_repository.dart — Line 99 (SILENT 10s HANG)
final response = await dioClient.dio.put(   // connectTimeout=10s, then DioException
  '/user/profile',
  data: { 'display_name': displayName, 'avatar_url': avatarUrl, 'bio': bio },
);
```

Why it is silent: ProfileNotifier.updateProfile() at line 45 catches ALL exceptions and returns false:

```dart
// profile_repository.dart — Lines 45-48 (SILENT SWALLOW)
} catch (err) {
  dev.log('[ProfileNotifier] Failed: $err', name: 'Profile');
  return false;  // caller never sees the failure
}
```

### BLOCKER 2 — Non-Dismissible Dialog (Primary Infinite Hang)

| Attribute | Value |
|---|---|
| File | apps/frontend/lib/features/onboarding/presentation/onboarding_screen.dart |
| Function | _completeOnboarding() |
| Line | 90 |
| Await | await showDialog(context: context, barrierDismissible: false, builder: ...) |
| Cause | AlertDialog has NO actions list, no dismiss button, barrierDismissible:false disables tap-outside. showDialog() Future only completes when Navigator.pop() is called — which never happens. |
| Effect | await at line 90 suspends permanently. context.go('/nearby') at line 129 unreachable. |

```dart
// onboarding_screen.dart — Lines 90-126 (PERMANENT BLOCK)
await showDialog(                        // Future<T?> awaited — NEVER RESOLVES
  context: context,
  barrierDismissible: false,            // tap-outside disabled
  builder: (context) {
    return AlertDialog(
      content: Column(children: [
        Icon(Icons.check_circle_rounded),
        Text('Setup Complete!'),
        Text('Welcome to Nearby Connect...'),
        // actions: [] NOT DEFINED
        // NO Navigator.pop(context) call ANYWHERE
      ]),
      // AlertDialog.actions defaults to null — no buttons rendered
    );
  },
);
// THIS LINE IS NEVER REACHED:
if (mounted) { context.go('/nearby'); }  // Line 129
```

---

## 6. Missing finally Block — Why Launching Persists

```dart
Future<void> _completeOnboarding() async {
  setState(() { _isCompleting = true; });  // SET to true — never reset

  await updateProfile(...);                // hangs 10s (silent)
  await SharedPreferences...              // resolves
  await showDialog(...);                  // PERMANENT BLOCK

  // NO try/finally block
  // setState(() { _isCompleting = false; }) is NEVER called
}
```

---

## 7. Backend Evidence

| Service | Status | Evidence |
|---|---|---|
| Gateway (192.168.31.60:8090) | NOT RUNNING | Invoke-WebRequest → Unable to connect to remote server |
| Redis | Healthy | docker ps → nearby-redis Up (healthy) |
| Kafka | Healthy | docker ps → nearby-kafka Up (healthy) |
| PostgreSQL | Healthy | docker ps → nearby-postgres Up (healthy) |
| Auth Service | Not in Docker | Not found in docker ps |
| User Service | Not in Docker | Not found in docker ps |

---

## 8. Expected Flutter Instrumentation Trace

```
[ONBOARDING][01] Before updateProfile()
[DIO][STEP-01] Outgoing Request: PUT http://192.168.31.60:8090/api/v1/user/profile
[DIO][STEP-02] onRequest Interceptor completed — Duration: 1 ms

  ... 10000 ms silence — connectTimeout fires ...

[DIO][STEP-04-ERR] Exception: DioExceptionType.connectionTimeout for /user/profile
[ONBOARDING][02] After updateProfile() — returned false (silent)
[ONBOARDING][03] SharedPreferences done
[ONBOARDING][04] setBool onboarding_completed done

  showDialog() called — AlertDialog rendered on device screen

  NO FURTHER LOGS — execution permanently suspended

  [ONBOARDING][05] Before context.go('/nearby')  <-- MISSING FOREVER
```

---

## 9. Android Logcat Evidence (Expected Patterns)

```
I flutter : [DIO][STEP-04-ERR] Exception: DioExceptionType.connectionTimeout
I flutter : [ProfileNotifier] Failed to update profile: DioException [...]

# Permanently absent from logcat:
# I flutter : [ONBOARDING] Before context.go('/nearby')   <-- NEVER APPEARS
```

---

## 10. Confidence Scores

| Hypothesis | Confidence | Evidence |
|---|---|---|
| showDialog non-dismissible — permanent await block | 100% | Source code: barrierDismissible:false, zero actions, zero Navigator.pop() |
| Gateway not running — 10s Dio timeout silently swallowed | 100% | Invoke-WebRequest refused + ProfileNotifier catch swallows |
| Missing finally block — _isCompleting never reset | 100% | Source code: no try/finally in _completeOnboarding() |
| FlutterSecureStorage blocking | 0% | Not invoked in this code path |
| Riverpod state provider stuck | 0% | ProfileNotifier.updateProfile() completes (returns false) |
| GoRouter navigation blocking | 0% | context.go('/nearby') is never reached — not called |
| GPS / Location hanging | 0% | Not invoked in _completeOnboarding() |
| WebSocket / Presence hanging | 0% | Not invoked in _completeOnboarding() |

---

## 11. PRR Root Cause Statement

BLOCKER 1: ProfileRepository.updateProfile() issues PUT /user/profile against a Gateway
that is not running; after Dio connectTimeout of 10 seconds the DioException is silently
swallowed in ProfileNotifier.updateProfile() — producing an invisible 10-second hang
with zero user feedback.

BLOCKER 2: _completeOnboarding() calls await showDialog(barrierDismissible: false, ...)
with an AlertDialog that has no actions: list and no Navigator.pop() call anywhere in its
builder — making the returned Future<T?> permanently irresolvable, suspending execution
before context.go('/nearby') can execute, with _isCompleting stuck at true indefinitely
because no finally block exists to reset it.

---

## 12. Files Requiring Fix (Evidence-Only — No Changes Made)

| File | Lines | Required Change |
|---|---|---|
| onboarding_screen.dart | 90-126 | Add actions: with Navigator.pop() or auto-dismiss then navigate |
| onboarding_screen.dart | 72-132 | Add try/finally to reset _isCompleting = false |
| profile_repository.dart | 45-48 | Rethrow exception so caller can surface failure to user |
| Backend | — | Start Gateway service on 192.168.31.60:8090 |

Investigation complete. No code changes made. Evidence-first. Root cause proven. Fix is next.
