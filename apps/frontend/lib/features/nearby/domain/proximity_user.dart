import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ProximityUser represents an active nearby user discovered via BLE scanning, GPS location streams, or the backend Nearby service.
class ProximityUser {
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final List<String>? interests;
  final double distanceMeters;
  final String? distanceDisplay;
  final bool withinChatRadius;
  final double maxChatDistanceMeters;
  final DateTime? locationUpdatedAt;
  final bool isOnline;
  final DateTime lastSeen;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final int? rssi;

  const ProximityUser({
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.bio,
    this.interests,
    required this.distanceMeters,
    this.distanceDisplay,
    this.withinChatRadius = true,
    this.maxChatDistanceMeters = 1000.0,
    this.locationUpdatedAt,
    required this.isOnline,
    required this.lastSeen,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.rssi,
  });

  String get formattedDistance {
    if (distanceDisplay != null && distanceDisplay!.isNotEmpty) {
      return distanceDisplay!;
    }
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(2)} km';
  }

  bool get isLocationStale {
    if (locationUpdatedAt == null) return false;
    return DateTime.now().toUtc().difference(locationUpdatedAt!).inSeconds > 60;
  }

  bool get isPoorAccuracy {
    return accuracyMeters != null && accuracyMeters! > 50.0;
  }

  bool get canInitiateChat {
    return withinChatRadius && !isLocationStale;
  }

  ProximityUser copyWith({
    String? userId,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? bio,
    List<String>? interests,
    double? distanceMeters,
    String? distanceDisplay,
    bool? withinChatRadius,
    double? maxChatDistanceMeters,
    DateTime? locationUpdatedAt,
    bool? isOnline,
    DateTime? lastSeen,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    int? rssi,
  }) {
    return ProximityUser(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      interests: interests ?? this.interests,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      distanceDisplay: distanceDisplay ?? this.distanceDisplay,
      withinChatRadius: withinChatRadius ?? this.withinChatRadius,
      maxChatDistanceMeters: maxChatDistanceMeters ?? this.maxChatDistanceMeters,
      locationUpdatedAt: locationUpdatedAt ?? this.locationUpdatedAt,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      rssi: rssi ?? this.rssi,
    );
  }
}

/// Real dynamic proximity user list provider (empty by default until discovered)
final proximityUsersProvider = StateProvider<List<ProximityUser>>((ref) {
  return const [];
});
