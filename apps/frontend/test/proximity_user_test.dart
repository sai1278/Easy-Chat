import 'package:flutter_test/flutter_test.dart';
import 'package:nearby_frontend/features/nearby/domain/proximity_user.dart';

void main() {
  group('ProximityUser 1 KM Radius Model Tests', () {
    test('Correctly identifies withinChatRadius = true for <= 1000m', () {
      final user = ProximityUser(
        userId: 'user-123',
        username: 'NearbyFriend',
        distanceMeters: 450.5,
        distanceDisplay: '451 m',
        withinChatRadius: true,
        maxChatDistanceMeters: 1000,
        accuracyMeters: 15.0,
        locationUpdatedAt: DateTime.now().toUtc(),
        isOnline: true,
        lastSeen: DateTime.now().toUtc(),
      );

      expect(user.userId, 'user-123');
      expect(user.username, 'NearbyFriend');
      expect(user.distanceMeters, 450.5);
      expect(user.formattedDistance, '451 m');
      expect(user.withinChatRadius, true);
      expect(user.maxChatDistanceMeters, 1000);
      expect(user.isLocationStale, false);
      expect(user.isPoorAccuracy, false);
    });

    test('Correctly identifies withinChatRadius = false for > 1000m', () {
      final user = ProximityUser(
        userId: 'user-456',
        username: 'FarAwayFriend',
        distanceMeters: 1250.0,
        distanceDisplay: '1.25 km',
        withinChatRadius: false,
        maxChatDistanceMeters: 1000,
        accuracyMeters: 20.0,
        locationUpdatedAt: DateTime.now().toUtc(),
        isOnline: true,
        lastSeen: DateTime.now().toUtc(),
      );

      expect(user.userId, 'user-456');
      expect(user.distanceMeters, 1250.0);
      expect(user.formattedDistance, '1.25 km');
      expect(user.withinChatRadius, false);
    });

    test('Detects stale location (> 60s)', () {
      final staleTime = DateTime.now().toUtc().subtract(const Duration(seconds: 75));
      final user = ProximityUser(
        userId: 'user-789',
        username: 'StaleFriend',
        distanceMeters: 300.0,
        withinChatRadius: true,
        locationUpdatedAt: staleTime,
        isOnline: true,
        lastSeen: DateTime.now().toUtc(),
      );

      expect(user.isLocationStale, true);
    });

    test('Detects poor accuracy (> 50m)', () {
      final user = ProximityUser(
        userId: 'user-acc',
        username: 'InaccurateFriend',
        distanceMeters: 200.0,
        accuracyMeters: 75.0,
        withinChatRadius: true,
        isOnline: true,
        lastSeen: DateTime.now().toUtc(),
      );

      expect(user.isPoorAccuracy, true);
    });
  });
}
