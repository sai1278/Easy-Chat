import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/entities/user_entity.dart';
import '../../../core/database/isar_service.dart';
import '../../../core/network/dio_client.dart';
import '../domain/user_profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => throw UnimplementedError());

final userProfileProvider = StateNotifierProvider<ProfileNotifier, AsyncValue<UserProfile>>((ref) {
  final repo = ref.watch(profileRepositoryProvider);
  return ProfileNotifier(repo);
});

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

  Future<bool> updateProfile({
    required String displayName,
    required String avatarUrl,
    required String bio,
  }) async {
    try {
      final updated = await _repository.updateProfile(
        displayName: displayName,
        avatarUrl: avatarUrl,
        bio: bio,
      );
      state = AsyncValue.data(updated);
      return true;
    } catch (err) {
      dev.log('[ProfileNotifier] Failed to update profile: $err', name: 'Profile');
      return false;
    }
  }
}

class ProfileRepository {
  final IsarService isar;
  final DioClient dioClient;

  ProfileRepository({required this.isar, required this.dioClient});

  Future<UserProfile> fetchProfile() async {
    try {
      final response = await dioClient.dio.get('/user/profile');
      if (response.statusCode == 200 && response.data != null) {
        final profile = UserProfile.fromJson(response.data as Map<String, dynamic>);
        await _cacheProfileLocally(profile);
        return profile;
      }
    } catch (e) {
      dev.log('[ProfileRepository] API fetch failed, falling back to local Isar cache: $e', name: 'Profile');
    }

    // Offline fallback to local Isar cache
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
    final response = await dioClient.dio.put(
      '/user/profile',
      data: {
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'bio': bio,
      },
    );

    if (response.statusCode == 200 && response.data != null) {
      final updated = UserProfile.fromJson(response.data as Map<String, dynamic>);
      await _cacheProfileLocally(updated);
      return updated;
    }

    throw Exception('Failed to update profile on backend server');
  }

  Future<void> _cacheProfileLocally(UserProfile profile) async {
    try {
      final userEntity = UserEntity()
        ..userId = profile.id
        ..username = profile.displayName.isNotEmpty ? profile.displayName : profile.username
        ..avatarUrl = profile.avatarUrl
        ..isOnline = true
        ..lastSeenAt = profile.updatedAt
        ..distanceMeters = 0.0;
      await isar.saveUser(userEntity);
    } catch (e) {
      dev.log('[ProfileRepository] Failed to cache profile locally: $e', name: 'Profile');
    }
  }
}
