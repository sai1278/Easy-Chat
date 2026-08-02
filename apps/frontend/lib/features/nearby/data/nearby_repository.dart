import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../chat/presentation/chat_controller.dart';
import '../domain/proximity_user.dart';

final nearbyRepositoryProvider = Provider<NearbyRepository>((ref) {
  final chatRepo = ref.watch(chatRepositoryProvider);
  return NearbyRepository(
    dioClient: DioClient(),
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
  Future<void> sendLocationHeartbeat(double latitude, double longitude) async {
    try {
      await _dioClient.dio.post(
        '/nearby/location',
        data: {
          'user_id': _currentUserId,
          'latitude': latitude,
          'longitude': longitude,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      );
      dev.log('[NearbyRepo] Sent location heartbeat ($latitude, $longitude)', name: 'Nearby');
    } catch (e) {
      dev.log('[NearbyRepo] Location heartbeat error: $e', name: 'Nearby');
    }
  }

  /// Fetch live nearby users from backend Nearby service
  Future<List<ProximityUser>> fetchNearbyUsers({
    required double latitude,
    required double longitude,
    double radiusMeters = 5000,
  }) async {
    try {
      final response = await _dioClient.dio.get(
        '/nearby/users',
        queryParameters: {
          'lat': latitude,
          'lng': longitude,
          'radius': radiusMeters,
        },
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
          return ProximityUser(
            userId: map['user_id'] as String? ?? map['id'] as String? ?? '',
            username: map['pseudonym'] as String? ?? map['username'] as String? ?? 'Nearby User',
            distanceMeters: (map['distance_meters'] as num?)?.toDouble() ?? 50.0,
            isOnline: map['is_online'] as bool? ?? true,
            lastSeen: DateTime.now(),
            latitude: (map['latitude'] as num?)?.toDouble(),
            longitude: (map['longitude'] as num?)?.toDouble(),
          );
        }).toList();
      }
    } catch (e) {
      dev.log('[NearbyRepo] Fetch nearby users error: $e', name: 'Nearby');
    }
    return const [];
  }
}
