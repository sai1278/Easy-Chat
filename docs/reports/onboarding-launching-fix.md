# Onboarding "Launching..." Fix — Engineering Delivery Report

**Classification**: Production Blocker Fix — P0
**Authors**: Google Principal Flutter Engineer · Principal Android Engineer · Staff SRE
**Date**: 2026-08-02
**Status**: VERIFIED — flutter analyze PASS | flutter test 10/10 PASS

---

## 1. Root Cause Summary

Two sequential defects in `_completeOnboarding()` caused the "Launching..." infinite hang:

| # | Blocker | File | Line | Impact |
|---|---|---|---|---|
| 1 | `DioException` silently swallowed in `ProfileNotifier` | `profile_repository.dart` | 45 | 10s invisible hang, UI gets no failure signal |
| 2 | `await showDialog(barrierDismissible:false)` with no dismiss path | `onboarding_screen.dart` | 90 | Permanent `await` suspension, navigation never reached |

Supporting condition: Gateway at `192.168.31.60:8090` not running at time of test.

---

## 2. State Transition Diagram

### SUCCESS FLOW (fixed)

```
User taps Continue
        |
        v
_isCompleting = true  [try block entered]
        |
        v
await updateProfile()  -------[ProfileException]------> catch(ProfileException)
        |                                                       |
[HTTP PUT /user/profile]                               SnackBar shown (error msg)
        |                                                       |
[200 OK returned]                                      finally: _isCompleting = false
        |                                                       |
SharedPreferences.setBool()                            Button re-enabled. Retry available.
        |
        v
SnackBar shown ("Setup complete!")   [NON-BLOCKING, self-dismissing 2s]
        |
        v
await Future.delayed(600ms)          [always resolves]
        |
        v
context.go('/nearby')                [navigation executes]
        |
        v
finally: _isCompleting = false       [guaranteed]
```

### ERROR FLOW (connection timeout)

```
User taps Continue
        |
        v
_isCompleting = true
        |
        v
await updateProfile()
        |
[Dio connectTimeout 10s fires]
        |
[DioException -> ProfileException("Connection timed out...")]
        |
catch(ProfileException e)
        |
SnackBar shown: "Connection timed out. Check network and try again."
SnackBarAction: Retry button shown
        |
finally: _isCompleting = false
        |
Button re-enabled. User can retry.
```

---

## 3. Code Changes

### BLOCKER 1 FIX — profile_repository.dart

**Before:**
```dart
// ProfileNotifier.updateProfile() — SWALLOWED EVERY EXCEPTION
} catch (err) {
  dev.log('[ProfileNotifier] Failed: $err', name: 'Profile');
  return false;  // caller gets false — cannot distinguish from success
}
```

**After:**
```dart
// ProfileNotifier.updateProfile() — RETHROWS typed domain exception
Future<void> updateProfile({...}) async {
  final updated = await _repository.updateProfile(...);
  state = AsyncValue.data(updated);
  // No catch here — ProfileException propagates to the UI layer
}
```

**ProfileRepository._mapDioException() — new:**
```dart
// Every DioException type mapped to human-readable ProfileException
case DioExceptionType.connectionTimeout:
  return const ProfileException('Connection timed out. Please check your network...');
case DioExceptionType.connectionError:
  return const ProfileException('Cannot reach the server...');
case DioExceptionType.badResponse:
  // Per-status-code messages: 401, 403, 404, 409, 500, unknown
```

### BLOCKER 2 FIX — onboarding_screen.dart

**Before:**
```dart
// PERMANENT BLOCK — no dismiss path, no finally, no error surface
Future<void> _completeOnboarding() async {
  setState(() { _isCompleting = true; });
  await updateProfile(...);              // silent on failure
  await SharedPreferences...
  await showDialog(                      // BLOCKS FOREVER
    barrierDismissible: false,
    builder: (_) => AlertDialog(         // no actions, no Navigator.pop()
      content: Column(...),
    ),
  );
  context.go('/nearby');                 // NEVER REACHED
}
// NO finally block — _isCompleting never reset
```

**After:**
```dart
// NON-BLOCKING, guaranteed to always resolve
Future<void> _completeOnboarding() async {
  if (_isCompleting) return;             // double-tap guard
  setState(() => _isCompleting = true);

  try {
    await updateProfile(...);            // throws ProfileException on any failure
    await SharedPreferences...
    ScaffoldMessenger.of(context).showSnackBar(/* non-blocking success */);
    await Future.delayed(Duration(milliseconds: 600));  // always resolves
    if (mounted) context.go('/nearby'); // always reached on success

  } on ProfileException catch (e) {
    // Human-readable error + Retry button shown
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(e.message),
      action: SnackBarAction(label: 'Retry', onPressed: _completeOnboarding),
    ));
  } catch (e, stack) {
    // Unexpected exception surfaced, not swallowed
    ScaffoldMessenger.of(context).showSnackBar(...);
  } finally {
    // GUARANTEED: always executes, always resets loading state
    if (mounted) setState(() => _isCompleting = false);
  }
}
```

### Cascading Fix — profile_screen.dart

**Before:**
```dart
final success = await notifier.updateProfile(...);  // bool return expected
Text(success ? 'Updated!' : 'Failed...')            // void expression used as bool
```

**After:**
```dart
try {
  await notifier.updateProfile(...);                // void, throws on failure
  // show success SnackBar
} on ProfileException catch (e) {
  // show typed error SnackBar
} catch (e) {
  // show generic error SnackBar
}
```

---

## 4. Error Handling Coverage

| Condition | Before | After |
|---|---|---|
| Connection timeout (10s) | Silent — UI stuck forever | SnackBar: "Connection timed out. Check network and retry." |
| Connection refused (gateway down) | Silent — UI stuck forever | SnackBar: "Cannot reach the server. Verify backend is running." |
| HTTP 401 Unauthorized | Not surfaced | SnackBar: "Session expired. Please log in again." |
| HTTP 403 Forbidden | Not surfaced | SnackBar: "You do not have permission to update this profile." |
| HTTP 404 Not Found | Not surfaced | SnackBar: "Profile not found on the server." |
| HTTP 409 Conflict | Not surfaced | SnackBar: "Profile update conflict. Please retry." |
| HTTP 500 Server Error | Not surfaced | SnackBar: "Server error. Please try again later." |
| Unexpected exception | Swallowed | SnackBar: "Unexpected error: {description}" |
| Success | Dialog blocks forever | SnackBar success + navigation to /nearby |

---

## 5. Verification Checklist

| Requirement | Verified | Evidence |
|---|---|---|
| Loading always disappears | YES | `finally { setState(() => _isCompleting = false); }` — no path bypasses this |
| No infinite dialogs | YES | `showDialog()` removed entirely from `_completeOnboarding()` |
| Navigation always occurs after success | YES | `context.go('/nearby')` reached after `Future.delayed(600ms)` which always resolves |
| Error messages shown | YES | `ProfileException.message` surfaced via SnackBar in all catch branches |
| `finally` always executes | YES | `try/catch/finally` wraps entire async body |
| No swallowed exceptions | YES | `ProfileNotifier` no longer catches — `ProfileRepository._mapDioException()` maps all Dio types |
| `flutter analyze` PASS | YES | `No issues found! (ran in 7.3s)` |
| `flutter test` PASS | YES | `+10: All tests passed!` |
| Double-tap guard | YES | `if (_isCompleting) return;` at method entry |
| Retry available on failure | YES | `SnackBarAction(label: Retry, onPressed: _completeOnboarding)` |

---

## 6. Files Modified

| File | Change |
|---|---|
| `lib/features/profile/data/profile_repository.dart` | Added `ProfileException` domain type. `ProfileNotifier.updateProfile()` changed to `Future<void>` — rethrows. `ProfileRepository.updateProfile()` wraps all `DioException` types in `_mapDioException()`. |
| `lib/features/onboarding/presentation/onboarding_screen.dart` | `_completeOnboarding()` rewritten with `try/catch/finally`, non-blocking SnackBar, `Future.delayed(600ms)`, guaranteed navigation and loading reset. |
| `lib/features/profile/presentation/profile_screen.dart` | `_saveProfile()` updated to use `try/catch` since `updateProfile()` is now `Future<void>`. |

---

## 7. PRR Sign-Off

- flutter analyze: PASS — No issues found
- flutter test: PASS — 10/10 tests passed
- No infinite blocking awaits remain
- No exceptions swallowed without UI surface
- Loading state has guaranteed reset via finally
- Navigation is reachable on every success path
- Error recovery (Retry) is available on every failure path
