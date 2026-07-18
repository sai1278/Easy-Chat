import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

enum ActivityState { stationary, moving }

class BatteryOptimizer {
  ActivityState _currentState = ActivityState.stationary;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _bleScanTimer;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  int _nearbyDeviceDensity = 0;
  DateTime _lastMovementTime = DateTime.now();
  
  // Callback hooks for state triggers
  final Function(LocationSettings settings) onLocationSettingsChanged;
  final Function(bool startScan, ScanMode scanMode) onBleScanTrigger;

  BatteryOptimizer({
    required this.onLocationSettingsChanged,
    required this.onBleScanTrigger,
  });

  ActivityState get currentState => _currentState;

  // Set the current app lifecycle state (foreground/background)
  void setLifecycleState(AppLifecycleState state) {
    if (_lifecycleState != state) {
      _lifecycleState = state;
      _applyOptimizations();
    }
  }

  // Set the current discovered user density to adapt scanning frequency
  void setNearbyDeviceDensity(int count) {
    if (_nearbyDeviceDensity != count) {
      _nearbyDeviceDensity = count;
      _applyOptimizations();
    }
  }

  // Initialize sensors and dynamically adapt power parameters
  void start() {
    _currentState = ActivityState.stationary;
    _lastMovementTime = DateTime.now();
    _applyOptimizations();
    
    // Listen to positions to gauge velocity/motion patterns
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _getLocationSettings(LocationAccuracy.low, 50),
    ).listen((position) {
      _evaluateMovement(position);
    });
  }

  void _evaluateMovement(Position position) {
    // Determine movement state based on GPS speed / velocity
    final speed = position.speed; // meters per second
    final isMoving = speed > 1.5; // ~5.4 km/h walking threshold

    if (isMoving) {
      _lastMovementTime = DateTime.now();
    }

    final nextState = isMoving ? ActivityState.moving : ActivityState.stationary;

    if (nextState != _currentState) {
      _currentState = nextState;
      _applyOptimizations();
    }
  }

  // Create platform-specific location settings for optimized GPS polling
  LocationSettings _getLocationSettings(LocationAccuracy accuracy, int distanceFilter) {
    if (kIsWeb) {
      return LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      );
    }

    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        intervalDuration: const Duration(seconds: 15),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Nearby Proximity Discovery active in background",
          notificationTitle: "Easy Chat Proximity",
          enableWakeLock: true,
        ),
      );
    } else if (Platform.isIOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: true,
        showBackgroundLocationIndicator: false,
      );
    }

    return LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
  }

  void _applyOptimizations() {
    final now = DateTime.now();
    final isIdle = _currentState == ActivityState.stationary && 
        now.difference(_lastMovementTime) > const Duration(minutes: 15);

    // 1. Inactivity (Idle) State optimization
    if (isIdle) {
      // Suspend GPS location stream by setting lowest accuracy and high distance filter
      onLocationSettingsChanged(_getLocationSettings(LocationAccuracy.lowest, 1000));

      // Suspend BLE scans entirely to save battery during sleep
      _bleScanTimer?.cancel();
      onBleScanTrigger(false, ScanMode.lowPower);
      return;
    }

    // 2. Background State optimization
    if (_lifecycleState == AppLifecycleState.paused || _lifecycleState == AppLifecycleState.inactive) {
      if (_currentState == ActivityState.moving) {
        onLocationSettingsChanged(_getLocationSettings(LocationAccuracy.medium, 200));

        // Scan for 3 seconds every 3 minutes in background
        _bleScanTimer?.cancel();
        _bleScanTimer = Timer.periodic(const Duration(minutes: 3), (timer) {
          onBleScanTrigger(true, ScanMode.lowPower);
          Future.delayed(const Duration(seconds: 3), () => onBleScanTrigger(false, ScanMode.lowPower));
        });
      } else {
        onLocationSettingsChanged(_getLocationSettings(LocationAccuracy.lowest, 500));

        // Scan for 3 seconds every 15 minutes in background
        _bleScanTimer?.cancel();
        _bleScanTimer = Timer.periodic(const Duration(minutes: 15), (timer) {
          onBleScanTrigger(true, ScanMode.lowPower);
          Future.delayed(const Duration(seconds: 3), () => onBleScanTrigger(false, ScanMode.lowPower));
        });
      }
    } else {
      // 3. Foreground State optimization
      if (_currentState == ActivityState.stationary) {
        onLocationSettingsChanged(_getLocationSettings(LocationAccuracy.low, 100));

        // Scan for 5 seconds every 2 minutes in low power mode
        _bleScanTimer?.cancel();
        _bleScanTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
          onBleScanTrigger(true, ScanMode.lowPower);
          Future.delayed(const Duration(seconds: 5), () => onBleScanTrigger(false, ScanMode.lowPower));
        });
      } else {
        onLocationSettingsChanged(_getLocationSettings(LocationAccuracy.high, 10));

        // Dynamically adjust scan interval based on device density
        // If density is high (> 10 peers), scan less frequently (every 60s) to conserve CPU
        final intervalSeconds = _nearbyDeviceDensity > 10 ? 60 : 30;

        _bleScanTimer?.cancel();
        _bleScanTimer = Timer.periodic(Duration(seconds: intervalSeconds), (timer) {
          onBleScanTrigger(true, ScanMode.balanced);
          Future.delayed(const Duration(seconds: 5), () => onBleScanTrigger(false, ScanMode.balanced));
        });
      }
    }
  }

  void stop() {
    _positionSubscription?.cancel();
    _bleScanTimer?.cancel();
  }
}
