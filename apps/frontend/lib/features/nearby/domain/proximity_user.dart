import 'package:flutter_riverpod/flutter_riverpod.dart';

// ProximityUser models a scanned nearby device user (fixes HIGH-15).
class ProximityUser {
  final String userId;
  final String username;
  final double distanceMeters;
  final bool isOnline;
  final DateTime lastSeen;

  const ProximityUser({
    required this.userId,
    required this.username,
    required this.distanceMeters,
    required this.isOnline,
    required this.lastSeen,
  });
}

// State provider to simulate scanning and proximity lists (fixes HIGH-16).
// In production, this can be updated dynamically by BLE / GPS scanners.
final proximityUsersProvider = StateProvider<List<ProximityUser>>((ref) {
  return [
    ProximityUser(
      userId: 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
      username: 'Alice (Within 100m)',
      distanceMeters: 45.0,
      isOnline: true,
      lastSeen: DateTime.now(),
    ),
    ProximityUser(
      userId: 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22',
      username: 'Bob (Within 200m)',
      distanceMeters: 120.0,
      isOnline: true,
      lastSeen: DateTime.now().subtract(const Duration(minutes: 2)),
    ),
    ProximityUser(
      userId: 'c0eebc99-9c0b-4ef8-bb6d-6bb9bd380a33',
      username: 'Charlie (Offline)',
      distanceMeters: 180.0,
      isOnline: false,
      lastSeen: DateTime.now().subtract(const Duration(hours: 1)),
    ),
  ];
});
