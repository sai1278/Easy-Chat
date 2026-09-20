import 'package:flutter_test/flutter_test.dart';
import 'package:nearby_frontend/features/profile/domain/user_profile.dart';
import 'package:nearby_frontend/features/nearby/domain/proximity_user.dart';

void main() {
  group('UserProfile Field & Persistence Regression Tests', () {
    test('UserProfile correctly parses username and display_name from API JSON', () {
      final json = {
        'id': 'user-12345',
        'username': 'Sai Test A',
        'display_name': 'Sai Test A Display',
        'avatar_url': 'https://example.com/avatar.png',
        'bio': 'Test bio',
        'updated_at': '2026-09-04T00:00:00Z',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, 'user-12345');
      expect(profile.username, 'Sai Test A');
      expect(profile.displayName, 'Sai Test A Display');
      expect(profile.bio, 'Test bio');
    });

    test('UserProfile handles legacy JSON with pseudonym and empty display_name', () {
      final json = {
        'id': 'user-67890',
        'pseudonym': 'Legacy User Name',
        'avatar_url': '',
        'bio': '',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, 'user-67890');
      expect(profile.username, 'Legacy User Name');
      expect(profile.displayName, 'Legacy User Name');
    });

    test('UserProfile falls back safely if both username and display_name are missing', () {
      final json = {
        'id': 'u-999',
        'avatar_url': '',
        'bio': '',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, 'u-999');
      expect(profile.username, 'User');
      expect(profile.displayName, 'User');
    });

    test('UserProfile toJson serializes username and display_name', () {
      final profile = UserProfile(
        id: 'u-1',
        username: 'Sai Test A',
        displayName: 'Sai Test A Display',
        avatarUrl: 'https://avatar.png',
        bio: 'Hello World',
        updatedAt: DateTime.parse('2026-09-04T08:00:00Z'),
      );

      final json = profile.toJson();

      expect(json['username'], 'Sai Test A');
      expect(json['display_name'], 'Sai Test A Display');
      expect(json['bio'], 'Hello World');
    });
  });

  group('ProximityUser Location & Accuracy Propagation Tests', () {
    test('ProximityUser parses accuracy_meters correctly from repository logic', () {
      final map = {
        'user_id': 'user-b',
        'display_name': 'Sai Test B',
        'distance_meters': 35.5,
        'accuracy_meters': 4.8,
        'is_online': true,
      };

      final displayName = map['display_name'] as String?;
      final pseudonym = map['pseudonym'] as String? ?? map['username'] as String? ?? 'Nearby User';
      final nameToUse = (displayName != null && displayName.isNotEmpty) ? displayName : pseudonym;
      final accVal = (map['accuracy_meters'] as num?)?.toDouble() ?? (map['accuracy'] as num?)?.toDouble();

      final user = ProximityUser(
        userId: map['user_id'] as String? ?? '',
        username: nameToUse,
        displayName: displayName,
        distanceMeters: (map['distance_meters'] as num?)?.toDouble() ?? 50.0,
        isOnline: map['is_online'] as bool? ?? true,
        lastSeen: DateTime.now(),
        accuracyMeters: accVal,
      );

      expect(user.userId, 'user-b');
      expect(user.username, 'Sai Test B');
      expect(user.displayName, 'Sai Test B');
      expect(user.distanceMeters, 35.5);
      expect(user.accuracyMeters, 4.8);
    });

    test('ProximityUser handles null or missing accuracy_meters safely', () {
      final map = {
        'user_id': 'user-c',
        'display_name': 'Sai Test C',
        'distance_meters': 12.0,
        'accuracy_meters': null,
      };

      final accVal = (map['accuracy_meters'] as num?)?.toDouble();
      final user = ProximityUser(
        userId: map['user_id'] as String? ?? '',
        username: map['display_name'] as String? ?? 'Nearby User',
        displayName: map['display_name'] as String?,
        distanceMeters: (map['distance_meters'] as num?)?.toDouble() ?? 50.0,
        isOnline: true,
        lastSeen: DateTime.now(),
        accuracyMeters: accVal,
      );

      expect(user.userId, 'user-c');
      expect(user.displayName, 'Sai Test C');
      expect(user.distanceMeters, 12.0);
      expect(user.accuracyMeters, isNull);
    });

    test('ProximityUser copyWith preserves and updates accuracyMeters', () {
      final user = ProximityUser(
        userId: 'user-d',
        username: 'Sai Test D',
        displayName: 'Sai Test D',
        distanceMeters: 50.0,
        accuracyMeters: 10.0,
        isOnline: true,
        lastSeen: DateTime.now(),
      );

      final updated = user.copyWith(distanceMeters: 25.0, accuracyMeters: 3.5);

      expect(updated.userId, 'user-d');
      expect(updated.displayName, 'Sai Test D');
      expect(updated.distanceMeters, 25.0);
      expect(updated.accuracyMeters, 3.5);
    });
  });
}
