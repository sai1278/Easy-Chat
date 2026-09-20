import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:isar/isar.dart';
import 'package:nearby_frontend/core/crypto/crypto_service.dart';
import 'package:nearby_frontend/core/database/entities/message_entity.dart';
import 'package:nearby_frontend/core/database/entities/user_entity.dart';
import 'package:nearby_frontend/core/database/isar_service.dart';
import 'package:nearby_frontend/core/network/dio_client.dart';
import 'package:nearby_frontend/core/network/websocket_client.dart';
import 'package:nearby_frontend/features/chat/data/chat_repository.dart';
import 'package:nearby_frontend/features/chat/domain/chat_message_payload.dart';

class TrackingSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> writtenKeys = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return writtenKeys[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      writtenKeys.remove(key);
    } else {
      writtenKeys[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writtenKeys.remove(key);
  }
}

class FakeIsarService implements IsarService {
  final Map<String, MessageEntity> messages = {};

  @override
  Isar? get isar => null;

  @override
  Future<void> saveMessage(MessageEntity message) async {
    messages[message.messageId] = message;
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    messages.remove(messageId);
  }

  @override
  Future<bool> isMessageDeleted(String messageId) async => !messages.containsKey(messageId);

  @override
  Future<MessageEntity?> getMessage(String messageId) async => messages[messageId];

  @override
  Stream<List<MessageEntity>> watchMessages(String roomId) => const Stream.empty();

  @override
  Future<void> saveUser(UserEntity user) async {}

  @override
  Future<List<UserEntity>> getUsers() async => [];

  @override
  Future<UserEntity?> getUser(String userId) async => null;
}

class FakeWebSocketClient extends Fake implements WebSocketClient {
  @override
  bool get isConnected => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Zero-Trust Plaintext Persistence Prevention Suite', () {
    late TrackingSecureStorage storageAlice;
    late TrackingSecureStorage storageBob;
    late CryptoService cryptoAlice;
    late CryptoService cryptoBob;
    late FakeIsarService isarAlice;
    late FakeIsarService isarBob;
    late ChatRepository repoAlice;
    late ChatRepository repoBob;

    const roomId = 'room-zero-trust-persistence-audit';
    const aliceId = 'user-alice-001';
    const bobId = 'user-bob-002';

    setUp(() async {
      storageAlice = TrackingSecureStorage();
      storageBob = TrackingSecureStorage();

      cryptoAlice = CryptoService(secureStorage: storageAlice);
      cryptoBob = CryptoService(secureStorage: storageBob);

      await cryptoAlice.initKeys();
      await cryptoBob.initKeys();

      isarAlice = FakeIsarService();
      isarBob = FakeIsarService();

      repoAlice = ChatRepository(
        cryptoService: cryptoAlice,
        isar: isarAlice,
        wsClient: FakeWebSocketClient(),
        secureStorage: storageAlice,
        dioClient: DioClient(),
        currentUserId: aliceId,
      );

      repoBob = ChatRepository(
        cryptoService: cryptoBob,
        isar: isarBob,
        wsClient: FakeWebSocketClient(),
        secureStorage: storageBob,
        dioClient: DioClient(),
        currentUserId: bobId,
      );

      // Exchange initial identity keys
      final bundleAlice = await cryptoAlice.getPublicIdentityBundle();
      final bundleBob = await cryptoBob.getPublicIdentityBundle();

      await cryptoAlice.getOrCreateSession(
        roomId: roomId,
        peerId: bobId,
        peerIdentityPubBase64: bundleBob['identity_key_pub']!,
        peerSignedPrekeyPubBase64: bundleBob['signed_prekey_pub']!,
        peerSignedPrekeySigBase64: bundleBob['signed_prekey_sig']!,
        isInitiator: true,
      );

      await cryptoBob.getOrCreateSession(
        roomId: roomId,
        peerId: aliceId,
        peerIdentityPubBase64: bundleAlice['identity_key_pub']!,
        peerSignedPrekeyPubBase64: bundleAlice['signed_prekey_pub']!,
        peerSignedPrekeySigBase64: bundleAlice['signed_prekey_sig']!,
        isInitiator: false,
      );
    });

    test('Zero plaintext written to persistent storage on message send', () async {
      final payload = ChatMessagePayload.plainText('Confidential mission data 12345');

      await repoAlice.sendMessage(roomId, payload, peerId: bobId);

      // Check all written keys in secure storage
      final plainKeys = storageAlice.writtenKeys.keys.where((k) => k.startsWith('msg_plain_'));
      expect(plainKeys, isEmpty, reason: 'No msg_plain_* keys must be persisted to storage');

      // Verify that no value in storage contains the plaintext
      for (final entry in storageAlice.writtenKeys.entries) {
        expect(
          entry.value.contains('Confidential mission data 12345'),
          isFalse,
          reason: 'Storage key ${entry.key} contains plaintext message data!',
        );
      }

      // Verify Isar database has only the encrypted payload
      expect(isarAlice.messages.length, equals(1));
      final savedMsg = isarAlice.messages.values.first;
      final payloadStr = utf8.decode(savedMsg.encryptedPayload);
      expect(payloadStr.startsWith('E2EE:v2:'), isTrue);
      expect(payloadStr.contains('Confidential mission data 12345'), isFalse);
    });

    test('Zero plaintext written to persistent storage on message decrypt', () async {
      const secretText = 'Secret coordinates: 37.7749,-122.4194';
      final encBytes = await cryptoAlice.encryptMessage(
        roomId: roomId,
        plaintextJson: jsonEncode({'type': 'text', 'text': secretText}),
      );

      final incomingEntity = MessageEntity()
        ..messageId = 'msg-incoming-001'
        ..roomId = roomId
        ..senderId = aliceId
        ..encryptedPayload = encBytes
        ..idempotencyKey = 'idem-001'
        ..createdAt = DateTime.now();

      final decrypted = await repoBob.decryptPayload(incomingEntity, peerId: aliceId);
      expect(decrypted.text, equals(secretText));

      // Assert Bob storage has zero msg_plain_* keys
      final plainKeys = storageBob.writtenKeys.keys.where((k) => k.startsWith('msg_plain_'));
      expect(plainKeys, isEmpty, reason: 'Decrypted message must NOT be written to secure storage');

      // Verify that no storage entry contains the secret text
      for (final entry in storageBob.writtenKeys.entries) {
        expect(
          entry.value.contains(secretText),
          isFalse,
          reason: 'Storage key ${entry.key} contains decrypted plaintext!',
        );
      }
    });

    test('Volatile cache clear wipes plaintext entirely from RAM', () async {
      final payload = ChatMessagePayload.plainText('Ephemeral RAM only token');
      await repoAlice.sendMessage(roomId, payload, peerId: bobId);

      final msgId = isarAlice.messages.keys.first;
      final entity = isarAlice.messages[msgId]!;

      // Before clear: volatile cache returns payload
      final before = await repoAlice.decryptPayload(entity);
      expect(before.text, equals('Ephemeral RAM only token'));

      // Clear volatile cache (simulating logout or session reset)
      repoAlice.clearVolatileCache();

      // After clear: memory is wiped; self-sent message returns placeholder, zero plaintext leak
      final after = await repoAlice.decryptPayload(entity);
      expect(after.text, equals('[Sent message]'));
    });
  });
}
