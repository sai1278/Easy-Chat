import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../chat/presentation/chat_controller.dart';
import '../domain/proximity_user.dart';

final nearbyRepositoryProvider = Provider<NearbyRepository>((ref) {
  final chatRepo = ref.watch(chatRepositoryProvider);
  final dioClient = ref.watch(dioClientProvider);
  return NearbyRepository(
    dioClient: dioClient,
    currentUserId: chatRepo.currentUserId,
  );
});

class NearbyRepository {
  final DioClient _dioClient;
  final String _currentUserId;

  NearbyRepository({
    required DioClient dioClient,
    required String currentUserId,
  })  : _dioClient = dioClient,
        _currentUserId = currentUserId;

  /// Send location heartbeat to backend Nearby service
  Future<void> sendLocationHeartbeat(double latitude, double longitude, {double? accuracy}) async {
    try {
      final payload = <String, dynamic>{
        'user_id': _currentUserId,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      if (accuracy != null && accuracy > 0) {
        payload['accuracy'] = accuracy;
      }
      await _dioClient.dio.post(
        '/nearby/location',
        data: payload,
      );
      dev.log('[NearbyRepo] Sent location heartbeat (acc: $accuracy)', name: 'Nearby');
    } catch (e) {
      dev.log('[NearbyRepo] Location heartbeat error: $e', name: 'Nearby');
    }
  }

  /// Fetch live nearby users from backend Nearby service
  Future<List<ProximityUser>> fetchNearbyUsers({
    required double latitude,
    required double longitude,
    double? accuracy,
    double radiusMeters = 5000,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'lat': latitude,
        'lng': longitude,
        'radius': radiusMeters,
      };
      if (accuracy != null && accuracy > 0) {
        queryParams['accuracy'] = accuracy;
      }
      final response = await _dioClient.dio.get(
        '/nearby/users',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data != null) {
        List<dynamic> rawList = [];
        if (response.data is List) {
          rawList = response.data as List<dynamic>;
        } else if (response.data is Map && (response.data as Map).containsKey('value')) {
          rawList = (response.data as Map)['value'] as List<dynamic>;
        } else if (response.data is Map && (response.data as Map).containsKey('users')) {
          rawList = (response.data as Map)['users'] as List<dynamic>;
        }
        return rawList.map((item) {
          final map = item as Map<String, dynamic>;
          final pseudonym = map['pseudonym'] as String? ?? map['username'] as String? ?? 'Nearby User';
          final displayName = map['display_name'] as String?;
          final nameToUse = (displayName != null && displayName.isNotEmpty) ? displayName : pseudonym;
          final accVal = (map['accuracy_meters'] as num?)?.toDouble() ?? (map['accuracy'] as num?)?.toDouble();
          final distMeters = (map['distance_meters'] as num?)?.toDouble() ?? 50.0;
          final distDisplay = map['distance_display'] as String?;
          final withinRadius = map['within_chat_radius'] as bool? ?? (distMeters <= 1000.0);
          final maxDist = (map['max_chat_distance_meters'] as num?)?.toDouble() ?? 1000.0;
          final locUpdatedStr = map['location_updated_at'] as String?;
          DateTime? locUpdatedAt;
          if (locUpdatedStr != null && locUpdatedStr.isNotEmpty) {
            locUpdatedAt = DateTime.tryParse(locUpdatedStr);
          }

          return ProximityUser(
            userId: map['user_id'] as String? ?? map['id'] as String? ?? '',
            username: nameToUse,
            displayName: displayName,
            avatarUrl: map['avatar_url'] as String?,
            bio: map['bio'] as String?,
            distanceMeters: distMeters,
            distanceDisplay: distDisplay,
            withinChatRadius: withinRadius,
            maxChatDistanceMeters: maxDist,
            locationUpdatedAt: locUpdatedAt,
            isOnline: map['is_online'] as bool? ?? true,
            lastSeen: DateTime.now(),
            latitude: (map['latitude'] as num?)?.toDouble(),
            longitude: (map['longitude'] as num?)?.toDouble(),
            accuracyMeters: accVal,
          );
        }).toList();
      }
    } catch (e) {
      dev.log('[NearbyRepo] Fetch nearby users error: $e', name: 'Nearby');
    }
    return const [];
  }
}
