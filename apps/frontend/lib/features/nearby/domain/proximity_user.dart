import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ProximityUser represents an active nearby user discovered via BLE scanning, GPS location streams, or the backend Nearby service.
class ProximityUser {
  final String userId;
  final String username;
  final double distanceMeters;
  final bool isOnline;
  final DateTime lastSeen;
  final double? latitude;
  final double? longitude;
  final int? rssi;

  const ProximityUser({
    required this.userId,
    required this.username,
    required this.distanceMeters,
    required this.isOnline,
    required this.lastSeen,
    this.latitude,
    this.longitude,
    this.rssi,
  });

  ProximityUser copyWith({
    String? userId,
    String? username,
    double? distanceMeters,
    bool? isOnline,
    DateTime? lastSeen,
    double? latitude,
    double? longitude,
    int? rssi,
  }) {
    return ProximityUser(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      rssi: rssi ?? this.rssi,
    );
  }
}

/// Real dynamic proximity user list provider (empty by default until discovered)
final proximityUsersProvider = StateProvider<List<ProximityUser>>((ref) {
  return const [];
});
