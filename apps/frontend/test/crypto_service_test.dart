import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nearby_frontend/core/crypto/crypto_service.dart';

class FakeFlutterSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _storage = {};

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
    return _storage[key];
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
      _storage.remove(key);
    } else {
      _storage[key] = value;
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
    _storage.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CryptoService E2EE Protocol Tests', () {
    late FakeFlutterSecureStorage storageAlice;
    late FakeFlutterSecureStorage storageBob;
    late CryptoService cryptoAlice;
    late CryptoService cryptoBob;

    setUp(() {
      storageAlice = FakeFlutterSecureStorage();
      storageBob = FakeFlutterSecureStorage();
      cryptoAlice = CryptoService(secureStorage: storageAlice);
      cryptoBob = CryptoService(secureStorage: storageBob);
    });

    test('Key Generation creates valid Ed25519 and X25519 keys in storage', () async {
      await cryptoAlice.initKeys();

      final bundle = await cryptoAlice.getPublicIdentityBundle();
      expect(bundle['identity_key_pub'], isNotEmpty);
      expect(bundle['signed_prekey_pub'], isNotEmpty);
      expect(bundle['signed_prekey_sig'], isNotEmpty);

      final idBytes = base64Decode(bundle['identity_key_pub']!);
      expect(idBytes.length, 32);

      final prekeyBytes = base64Decode(bundle['signed_prekey_pub']!);
      expect(prekeyBytes.length, 32);
    });

    test('X25519 Authenticated Key Agreement derives session master key for Alice and Bob', () async {
      await cryptoAlice.initKeys();
      await cryptoBob.initKeys();

      final bundleAlice = await cryptoAlice.getPublicIdentityBundle();
      final bundleBob = await cryptoBob.getPublicIdentityBundle();

      const roomId = 'test-room-uuid-1234';

      final sessionKeyAlice = await cryptoAlice.getOrCreateSessionKey(
        roomId: roomId,
        peerId: 'user-bob',
        peerIdentityPubBase64: bundleBob['identity_key_pub']!,
        peerSignedPrekeyPubBase64: bundleBob['signed_prekey_pub']!,
        peerSignedPrekeySigBase64: bundleBob['signed_prekey_sig']!,
      );

      final sessionKeyBob = await cryptoBob.getOrCreateSessionKey(
        roomId: roomId,
        peerId: 'user-alice',
        peerIdentityPubBase64: bundleAlice['identity_key_pub']!,
        peerSignedPrekeyPubBase64: bundleAlice['signed_prekey_pub']!,
        peerSignedPrekeySigBase64: bundleAlice['signed_prekey_sig']!,
      );

      final bytesAlice = await sessionKeyAlice.extractBytes();
      final bytesBob = await sessionKeyBob.extractBytes();

      expect(bytesAlice.length, 32);
      expect(bytesBob.length, 32);
    });

    test('Bidirectional E2EE message encryption, transmission, and decryption', () async {
      await cryptoAlice.initKeys();
      await cryptoBob.initKeys();

      final bundleAlice = await cryptoAlice.getPublicIdentityBundle();
      final bundleBob = await cryptoBob.getPublicIdentityBundle();
      const roomId = 'test-room-bidirectional';

      await cryptoAlice.getOrCreateSession(
        roomId: roomId,
        peerId: 'user-bob',
        peerIdentityPubBase64: bundleBob['identity_key_pub']!,
        peerSignedPrekeyPubBase64: bundleBob['signed_prekey_pub']!,
        peerSignedPrekeySigBase64: bundleBob['signed_prekey_sig']!,
        isInitiator: true,
      );

      await cryptoBob.getOrCreateSession(
        roomId: roomId,
        peerId: 'user-alice',
        peerIdentityPubBase64: bundleAlice['identity_key_pub']!,
        peerSignedPrekeyPubBase64: bundleAlice['signed_prekey_pub']!,
        peerSignedPrekeySigBase64: bundleAlice['signed_prekey_sig']!,
        isInitiator: false,
      );

      const plaintext = '{"type":"text","text":"Hello Alice, this is 100% genuine E2EE!"}';

      // 1. Alice encrypts
      final encryptedBytes = await cryptoAlice.encryptMessage(
        roomId: roomId,
        plaintextJson: plaintext,
      );

      final encryptedString = utf8.decode(encryptedBytes);
      expect(encryptedString.startsWith('E2EE:v2:'), isTrue);
      expect(encryptedString.contains('Hello Alice'), isFalse);

      // 2. Bob decrypts
      final decrypted = await cryptoBob.decryptMessage(
        roomId: roomId,
        rawBytes: encryptedBytes,
      );

      expect(decrypted, equals(plaintext));
    });

    test('Tampered ciphertext fails authentication (MAC verification rejection)', () async {
      await cryptoAlice.initKeys();
      await cryptoBob.initKeys();

      final bundleAlice = await cryptoAlice.getPublicIdentityBundle();
      final bundleBob = await cryptoBob.getPublicIdentityBundle();
      const roomId = 'test-room-tamper';

      await cryptoAlice.getOrCreateSession(
        roomId: roomId,
        peerId: 'user-bob',
        peerIdentityPubBase64: bundleBob['identity_key_pub']!,
        peerSignedPrekeyPubBase64: bundleBob['signed_prekey_pub']!,
        peerSignedPrekeySigBase64: bundleBob['signed_prekey_sig']!,
        isInitiator: true,
      );

      await cryptoBob.getOrCreateSession(
        roomId: roomId,
        peerId: 'user-alice',
        peerIdentityPubBase64: bundleAlice['identity_key_pub']!,
        peerSignedPrekeyPubBase64: bundleAlice['signed_prekey_pub']!,
        peerSignedPrekeySigBase64: bundleAlice['signed_prekey_sig']!,
        isInitiator: false,
      );

      final encryptedBytes = await cryptoAlice.encryptMessage(
        roomId: roomId,
        plaintextJson: '{"type":"text","text":"original"}',
      );

      // Tamper with envelope ciphertext
      final envelopeJson = utf8.decode(encryptedBytes).substring('E2EE:v2:'.length);
      final envelope = jsonDecode(envelopeJson) as Map<String, dynamic>;
      final ctBytes = base64Decode(envelope['ct'] as String);
      ctBytes[0] ^= 0xFF; // flip bits
      envelope['ct'] = base64Encode(ctBytes);

      final tamperedBytes = utf8.encode('E2EE:v2:${jsonEncode(envelope)}');

      // Bob attempts to decrypt tampered ciphertext: MUST fail authentication
      expect(
        () async => await cryptoBob.decryptMessage(
          roomId: roomId,
          rawBytes: tamperedBytes,
        ),
        throwsA(isA<CryptoException>()),
      );
    });

    test('Attachment Encryption & Decryption (Image and Voice Notes)', () async {
      final rawImageBytes = List<int>.generate(1024, (i) => i % 256);

      // Encrypt attachment on sender device
      final encResult = await cryptoAlice.encryptAttachment(rawImageBytes);
      expect(encResult.ciphertext, isNot(equals(rawImageBytes)));
      expect(encResult.mediaKeyBase64, isNotEmpty);
      expect(encResult.nonceBase64, isNotEmpty);

      // Decrypt attachment on receiver device
      final decryptedBytes = await cryptoBob.decryptAttachment(
        ciphertextBytes: encResult.ciphertext,
        mediaKeyBase64: encResult.mediaKeyBase64,
        nonceBase64: encResult.nonceBase64,
      );

      expect(decryptedBytes, equals(rawImageBytes));
    });

    test('Tampered Attachment fails decryption', () async {
      final rawVoiceBytes = utf8.encode('audio-m4a-sample-bytes-stream');

      final encResult = await cryptoAlice.encryptAttachment(rawVoiceBytes);
      final tamperedCiphertext = List<int>.from(encResult.ciphertext);
      tamperedCiphertext[10] ^= 0xAA;

      expect(
        () async => await cryptoBob.decryptAttachment(
          ciphertextBytes: tamperedCiphertext,
          mediaKeyBase64: encResult.mediaKeyBase64,
          nonceBase64: encResult.nonceBase64,
        ),
        throwsA(isA<CryptoException>()),
      );
    });

    test('Prohibits automatic plaintext fallback on unencrypted input', () async {
      await cryptoBob.initKeys();

      const legacyJson = '{"type":"text","text":"Attempting plain text message"}';
      final legacyBytes = utf8.encode(legacyJson);

      // Decrypting unencrypted raw bytes MUST fail with CryptoException (NO PLAINTEXT FALLBACK)
      expect(
        () async => await cryptoBob.decryptMessage(
          roomId: 'test-room',
          rawBytes: legacyBytes,
        ),
        throwsA(isA<CryptoException>()),
      );
    });
  });
}
