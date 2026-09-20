import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/entities/user_entity.dart';
import '../../../core/database/isar_service.dart';
import '../../../core/network/dio_client.dart';
import '../domain/user_profile.dart';

// ---------------------------------------------------------------------------
// Domain exception — strongly typed, UI-displayable
// ---------------------------------------------------------------------------

/// A typed exception surfaced by all profile operations.
/// Every failure path produces a [ProfileException] with a human-readable
/// [message] that the UI can display directly to the user.
class ProfileException implements Exception {
  final String message;
  final int? statusCode;

  const ProfileException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final dioClient = ref.watch(dioClientProvider);
  return ProfileRepository(
    isar: ref.watch(isarServiceProvider),
    dioClient: dioClient,
  );
});

final userProfileProvider =
    StateNotifierProvider<ProfileNotifier, AsyncValue<UserProfile>>((ref) {
  final repo = ref.watch(profileRepositoryProvider);
  return ProfileNotifier(repo);
});

// Dummy/Fallback provider for Isar if needed, can be overridden in main.dart
final isarServiceProvider = Provider<IsarService>((ref) => throw UnimplementedError());

// ---------------------------------------------------------------------------
// ProfileNotifier — rethrows typed domain exceptions (BLOCKER 1 FIX)
// ---------------------------------------------------------------------------

class ProfileNotifier extends StateNotifier<AsyncValue<UserProfile>> {
  final ProfileRepository _repository;

  ProfileNotifier(this._repository) : super(const AsyncValue.loading()) {
    loadProfile();
  }

  Future<void> loadProfile() async {
    state = const AsyncValue.loading();
    try {
      final profile = await _repository.fetchProfile();
      state = AsyncValue.data(profile);
    } catch (err, st) {
      state = AsyncValue.error(err, st);
    }
  }

  Future<void> updateProfile({
    required String displayName,
    required String avatarUrl,
    required String bio,
  }) async {
    final updated = await _repository.updateProfile(
      displayName: displayName,
      avatarUrl: avatarUrl,
      bio: bio,
    );
    state = AsyncValue.data(updated);
  }
}

// ---------------------------------------------------------------------------
// ProfileRepository — maps every failure to a typed ProfileException
// ---------------------------------------------------------------------------

class ProfileRepository {
  final IsarService isar;
  final DioClient dioClient;

  ProfileRepository({required this.isar, required this.dioClient});

  Future<void> _auditAuthHeader(String operation) async {
    final token = dioClient.cachedToken;
    final baseUrl = dioClient.dio.options.baseUrl;
    final jwtLen = token?.length ?? 0;
    dev.log(
      '[ProfileRepository][$operation] BaseURL: $baseUrl | Token length: $jwtLen | HasToken: ${jwtLen > 0}',
      name: 'AuthTrace',
    );
  }

  Future<UserProfile> fetchProfile() async {
    await _auditAuthHeader('FETCH');
    try {
      final response = await dioClient.dio.get('/user/profile');
      if (response.statusCode == 200 && response.data != null) {
        final profile =
            UserProfile.fromJson(response.data as Map<String, dynamic>);
        await _cacheProfileLocally(profile);
        return profile;
      }
    } catch (e) {
      dev.log(
        '[ProfileRepository] API fetch failed, falling back to local Isar cache: $e',
        name: 'Profile',
      );
    }

    // Offline fallback: Isar local cache
    final localUsers = await isar.getUsers();
    if (localUsers.isNotEmpty) {
      final cached = localUsers.first;
      return UserProfile(
        id: cached.userId,
        username: cached.username,
        displayName: cached.username,
        avatarUrl: cached.avatarUrl,
        bio: 'Offline cached profile',
        updatedAt: cached.lastSeenAt,
      );
    }

    return UserProfile(
      id: 'local_user',
      username: 'User',
      displayName: 'Nearby User',
      avatarUrl: '',
      bio: 'Proximity Chat User',
      updatedAt: DateTime.now(),
    );
  }

  Future<UserProfile> updateProfile({
    required String displayName,
    required String avatarUrl,
    required String bio,
  }) async {
    await _auditAuthHeader('UPDATE');
    try {
      final response = await dioClient.dio.put(
        '/user/profile',
        data: {
          'display_name': displayName,
          'username': displayName,
          'avatar_url': avatarUrl,
          'bio': bio,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final updated =
            UserProfile.fromJson(response.data as Map<String, dynamic>);
        await _cacheProfileLocally(updated);
        return updated;
      }

      throw ProfileException(
        'Profile update failed: unexpected status ${response.statusCode}',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      throw _mapDioException(e);
    } catch (e) {
      if (e is ProfileException) rethrow;
      dev.log('[ProfileRepository] Unexpected error during updateProfile: $e',
          name: 'Profile');
      throw ProfileException('An unexpected error occurred: $e');
    }
  }

  /// Maps a [DioException] to a human-readable [ProfileException].
  /// Covers: timeout, connection refused, 401, 403, 404, 409, 500, unknown.
  ProfileException _mapDioException(DioException e) {
    dev.log(
      '[ProfileRepository] DioException: type=${e.type} status=${e.response?.statusCode} msg=${e.message}',
      name: 'Profile',
    );

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ProfileException(
          'Connection timed out. Please check your network and try again.',
        );
      case DioExceptionType.connectionError:
        return const ProfileException(
          'Cannot reach the server. Verify the backend is running and your network connection.',
        );
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        final serverMsg = _extractServerMessage(e.response?.data);
        switch (status) {
          case 401:
            return ProfileException(
              serverMsg ?? 'Session expired. Please log in again.',
              statusCode: 401,
            );
          case 403:
            return ProfileException(
              serverMsg ?? 'You do not have permission to update this profile.',
              statusCode: 403,
            );
          case 404:
            return ProfileException(
              serverMsg ?? 'Profile not found on the server.',
              statusCode: 404,
            );
          case 409:
            return ProfileException(
              serverMsg ?? 'Profile update conflict. Please retry.',
              statusCode: 409,
            );
          case 500:
            return ProfileException(
              serverMsg ?? 'Server error. Please try again later.',
              statusCode: 500,
            );
          default:
            return ProfileException(
              serverMsg ?? 'Profile update failed (HTTP $status).',
              statusCode: status,
            );
        }
      default:
        return ProfileException(
          e.message ?? 'An unknown network error occurred.',
        );
    }
  }

  String? _extractServerMessage(dynamic data) {
    if (data is Map) {
      return (data['error'] ?? data['message'] ?? data['detail']) as String?;
    }
    if (data is String && data.isNotEmpty) return data;
    return null;
  }

  Future<void> _cacheProfileLocally(UserProfile profile) async {
    try {
      final userEntity = UserEntity()
        ..userId = profile.id
        ..username =
            profile.displayName.isNotEmpty ? profile.displayName : profile.username
        ..avatarUrl = profile.avatarUrl
        ..isOnline = true
        ..lastSeenAt = profile.updatedAt
        ..distanceMeters = 0.0;
      await isar.saveUser(userEntity);
    } catch (e) {
      dev.log('[ProfileRepository] Failed to cache profile locally: $e',
          name: 'Profile');
    }
  }
}
