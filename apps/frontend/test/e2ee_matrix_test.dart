import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nearby_frontend/core/crypto/crypto_service.dart';

class MatrixFakeStorage extends Fake implements FlutterSecureStorage {
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
  }) async => _storage[key];

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
  }) async => _storage.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('E2EE Comprehensive Test Matrix', () {
    late MatrixFakeStorage storageAlice;
    late MatrixFakeStorage storageBob;
    late MatrixFakeStorage storageEve;
    late CryptoService cryptoAlice;
    late CryptoService cryptoBob;
    late CryptoService cryptoEve;

    setUp(() async {
      storageAlice = MatrixFakeStorage();
      storageBob = MatrixFakeStorage();
      storageEve = MatrixFakeStorage();
      cryptoAlice = CryptoService(secureStorage: storageAlice);
      cryptoBob = CryptoService(secureStorage: storageBob);
      cryptoEve = CryptoService(secureStorage: storageEve);

      await cryptoAlice.initKeys();
      await cryptoBob.initKeys();
      await cryptoEve.initKeys();
    });

    Future<Map<String, dynamic>> establishAliceBob(String roomId) async {
      final bAlice = await cryptoAlice.getPublicIdentityBundle();
      final bBob = await cryptoBob.getPublicIdentityBundle();
      final sAlice = await cryptoAlice.getOrCreateSession(
        roomId: roomId,
        peerId: 'bob',
        peerIdentityPubBase64: bBob['identity_key_pub']!,
        peerSignedPrekeyPubBase64: bBob['signed_prekey_pub']!,
        peerSignedPrekeySigBase64: bBob['signed_prekey_sig']!,
        isInitiator: true,
      );
      final sBob = await cryptoBob.getOrCreateSession(
        roomId: roomId,
        peerId: 'alice',
        peerIdentityPubBase64: bAlice['identity_key_pub']!,
        peerSignedPrekeyPubBase64: bAlice['signed_prekey_pub']!,
        peerSignedPrekeySigBase64: bAlice['signed_prekey_sig']!,
        isInitiator: false,
      );
      return {'sAlice': sAlice.rk, 'sBob': sBob.rk};
    }

    // ==========================================
    // 1. TEXT E2EE MATRIX
    // ==========================================
    test('TEXT: encrypt/decrypt standard text', () async {
      final s = await establishAliceBob('room-text-std');
      const pt = '{"type":"text","text":"Hello Bob, normal message"}';
      final enc = await cryptoAlice.encryptMessage(roomId: 'room-text-std', plaintextJson: pt, sessionKey: s['sAlice']);
      expect(utf8.decode(enc).startsWith('E2EE:v2:'), isTrue);
      final dec = await cryptoBob.decryptMessage(roomId: 'room-text-std', rawBytes: enc, sessionKey: s['sBob']);
      expect(dec, equals(pt));
    });

    test('TEXT: empty text payload', () async {
      final s = await establishAliceBob('room-text-empty');
      const pt = '{"type":"text","text":""}';
      final enc = await cryptoAlice.encryptMessage(roomId: 'room-text-empty', plaintextJson: pt, sessionKey: s['sAlice']);
      final dec = await cryptoBob.decryptMessage(roomId: 'room-text-empty', rawBytes: enc, sessionKey: s['sBob']);
      expect(dec, equals(pt));
    });

    test('TEXT: Unicode and multilingual characters', () async {
      final s = await establishAliceBob('room-text-unicode');
      const pt = '{"type":"text","text":"こんにちは / مرحبا / नमस्ते / హలో / Bonjour / Русский"}';
      final enc = await cryptoAlice.encryptMessage(roomId: 'room-text-unicode', plaintextJson: pt, sessionKey: s['sAlice']);
      final dec = await cryptoBob.decryptMessage(roomId: 'room-text-unicode', rawBytes: enc, sessionKey: s['sBob']);
      expect(dec, equals(pt));
    });

    test('TEXT: emojis and composite modifiers', () async {
      final s = await establishAliceBob('room-text-emojis');
      const pt = '{"type":"text","text":"🚀🔥👨‍👩‍👧‍👦🎉🔐🛡️👍🏽✨"}';
      final enc = await cryptoAlice.encryptMessage(roomId: 'room-text-emojis', plaintextJson: pt, sessionKey: s['sAlice']);
      final dec = await cryptoBob.decryptMessage(roomId: 'room-text-emojis', rawBytes: enc, sessionKey: s['sBob']);
      expect(dec, equals(pt));
    });

    test('TEXT: long text payload (10 KB+)', () async {
      final s = await establishAliceBob('room-text-long');
      final longStr = List.filled(500, 'SecurityTesting12345').join(' ');
      final pt = jsonEncode({'type': 'text', 'text': longStr});
      final enc = await cryptoAlice.encryptMessage(roomId: 'room-text-long', plaintextJson: pt, sessionKey: s['sAlice']);
      final dec = await cryptoBob.decryptMessage(roomId: 'room-text-long', rawBytes: enc, sessionKey: s['sBob']);
      expect(dec, equals(pt));
    });

    test('TEXT: malformed ciphertext safely rejected', () async {
      final s = await establishAliceBob('room-text-malformed');
      final malformed1 = utf8.encode('E2EE:v2:not-a-json');
      expect(() => cryptoBob.decryptMessage(roomId: 'room-text-malformed', rawBytes: malformed1, sessionKey: s['sBob']), throwsA(anything));

      final malformed2 = utf8.encode('E2EE:v2:{"v":2,"n":0,"dh":"bad-base64"}');
      expect(() => cryptoBob.decryptMessage(roomId: 'room-text-malformed', rawBytes: malformed2, sessionKey: s['sBob']), throwsA(anything));
    });

    test('TEXT: wrong key rejection', () async {
      final sAB = await establishAliceBob('room-text-key1');
      final bAlice = await cryptoAlice.getPublicIdentityBundle();
      final sEve = await cryptoEve.getOrCreateSession(
        roomId: 'room-text-key1',
        peerId: 'alice',
        peerIdentityPubBase64: bAlice['identity_key_pub']!,
        peerSignedPrekeyPubBase64: bAlice['signed_prekey_pub']!,
        peerSignedPrekeySigBase64: bAlice['signed_prekey_sig']!,
        isInitiator: false,
      );

      final enc = await cryptoAlice.encryptMessage(
        roomId: 'room-text-key1',
        plaintextJson: '{"type":"text","text":"secret for bob only"}',
        sessionKey: sAB['sAlice'],
      );

      // Eve attempts to decrypt Alice's ciphertext intended for Bob
      expect(
        () => cryptoEve.decryptMessage(roomId: 'room-text-key1', rawBytes: enc, sessionKey: sEve.rk),
        throwsA(anything),
      );
    });

    test('TEXT: tampered ciphertext bit-flip rejection', () async {
      final s = await establishAliceBob('room-text-tamper');
      final enc = await cryptoAlice.encryptMessage(
        roomId: 'room-text-tamper',
        plaintextJson: '{"type":"text","text":"authentic"}',
        sessionKey: s['sAlice'],
      );

      final rawStr = utf8.decode(enc).substring('E2EE:v2:'.length);
      final env = jsonDecode(rawStr) as Map<String, dynamic>;
      final ctBytes = base64Decode(env['ct'] as String);
      ctBytes[0] ^= 0x01; // single bit flip
      env['ct'] = base64Encode(ctBytes);
      final tampered = utf8.encode('E2EE:v2:${jsonEncode(env)}');

      expect(
        () => cryptoBob.decryptMessage(roomId: 'room-text-tamper', rawBytes: tampered, sessionKey: s['sBob']),
        throwsA(anything),
      );
    });

    test('TEXT: duplicate / replay message rejection in Double Ratchet', () async {
      final s = await establishAliceBob('room-text-dup');
      const pt = '{"type":"text","text":"single use message"}';
      final enc = await cryptoAlice.encryptMessage(roomId: 'room-text-dup', plaintextJson: pt, sessionKey: s['sAlice']);

      // Decrypt first time: succeeds
      final dec1 = await cryptoBob.decryptMessage(roomId: 'room-text-dup', rawBytes: enc, sessionKey: s['sBob']);
      expect(dec1, equals(pt));

      // Decrypt duplicate replayed frame: Double Ratchet MUST reject replay!
      expect(
        () async => await cryptoBob.decryptMessage(roomId: 'room-text-dup', rawBytes: enc, sessionKey: s['sBob']),
        throwsA(isA<CryptoException>()),
      );
    });

    // ==========================================
    // 2. IMAGE E2EE MATRIX
    // ==========================================
    test('IMAGE: encrypt/decrypt and metadata packaging', () async {
      final rawImage = List<int>.generate(4096, (i) => (i * 17) % 256);
      final enc = await cryptoAlice.encryptAttachment(rawImage);

      expect(enc.ciphertext, isNot(equals(rawImage)));
      expect(enc.mediaKeyBase64, isNotEmpty);
      expect(enc.nonceBase64, isNotEmpty);

      final dec = await cryptoBob.decryptAttachment(
        ciphertextBytes: enc.ciphertext,
        mediaKeyBase64: enc.mediaKeyBase64,
        nonceBase64: enc.nonceBase64,
      );
      expect(dec, equals(rawImage));
    });

    test('IMAGE: corrupted ciphertext fails decryption', () async {
      final rawImage = List<int>.generate(2048, (i) => i % 256);
      final enc = await cryptoAlice.encryptAttachment(rawImage);

      final corrupted = List<int>.from(enc.ciphertext);
      corrupted[50] ^= 0x55;

      expect(
        () => cryptoBob.decryptAttachment(
          ciphertextBytes: corrupted,
          mediaKeyBase64: enc.mediaKeyBase64,
          nonceBase64: enc.nonceBase64,
        ),
        throwsA(anything),
      );
    });

    test('IMAGE: wrong key fails decryption', () async {
      final rawImage = List<int>.generate(1024, (i) => i % 256);
      final enc = await cryptoAlice.encryptAttachment(rawImage);
      final wrongKey = base64Encode(List<int>.filled(32, 0x99));

      expect(
        () => cryptoBob.decryptAttachment(
          ciphertextBytes: enc.ciphertext,
          mediaKeyBase64: wrongKey,
          nonceBase64: enc.nonceBase64,
        ),
        throwsA(anything),
      );
    });

    test('IMAGE: large image payload (2 MB buffer)', () async {
      final largeImage = List<int>.generate(2 * 1024 * 1024, (i) => (i ^ 0x3C) % 256);
      final enc = await cryptoAlice.encryptAttachment(largeImage);
      final dec = await cryptoBob.decryptAttachment(
        ciphertextBytes: enc.ciphertext,
        mediaKeyBase64: enc.mediaKeyBase64,
        nonceBase64: enc.nonceBase64,
      );
      expect(dec.length, equals(largeImage.length));
      expect(dec[0], equals(largeImage[0]));
      expect(dec[dec.length - 1], equals(largeImage[largeImage.length - 1]));
    });

    // ==========================================
    // 3. VOICE E2EE MATRIX
    // ==========================================
    test('VOICE: encrypt/decrypt audio stream simulation', () async {
      final fakeM4a = utf8.encode('ftypM4A ....moov....mdat[audio sample bytes]');
      final enc = await cryptoAlice.encryptAttachment(fakeM4a);

      final dec = await cryptoBob.decryptAttachment(
        ciphertextBytes: enc.ciphertext,
        mediaKeyBase64: enc.mediaKeyBase64,
        nonceBase64: enc.nonceBase64,
      );
      expect(dec, equals(fakeM4a));
    });

    test('VOICE: corrupted voice ciphertext fails decryption', () async {
      final fakeM4a = utf8.encode('audio-bytes-stream');
      final enc = await cryptoAlice.encryptAttachment(fakeM4a);
      final corrupted = List<int>.from(enc.ciphertext);
      corrupted[corrupted.length - 1] ^= 0x0F;

      expect(
        () => cryptoBob.decryptAttachment(
          ciphertextBytes: corrupted,
          mediaKeyBase64: enc.mediaKeyBase64,
          nonceBase64: enc.nonceBase64,
        ),
        throwsA(anything),
      );
    });

    // ==========================================
    // 4. LOCATION E2EE MATRIX
    // ==========================================
    test('LOCATION: encrypt/decrypt location coordinates and timestamp', () async {
      final s = await establishAliceBob('room-loc-std');
      final locPayload = jsonEncode({
        'type': 'location',
        'latitude': 17.440081,
        'longitude': 78.348916,
        'timestamp': DateTime.now().toIso8601String(),
        'accuracy': 12.5,
      });

      final enc = await cryptoAlice.encryptMessage(
        roomId: 'room-loc-std',
        plaintextJson: locPayload,
        sessionKey: s['sAlice'],
      );
      final encString = utf8.decode(enc);
      expect(encString.contains('17.440081'), isFalse); // Server sees ZERO coordinates
      expect(encString.contains('78.348916'), isFalse);

      final dec = await cryptoBob.decryptMessage(
        roomId: 'room-loc-std',
        rawBytes: enc,
        sessionKey: s['sBob'],
      );
      final parsed = jsonDecode(dec) as Map<String, dynamic>;
      expect(parsed['type'], equals('location'));
      expect(parsed['latitude'], equals(17.440081));
      expect(parsed['longitude'], equals(78.348916));
    });

    test('LOCATION: malformed location payload handles safely', () async {
      final s = await establishAliceBob('room-loc-mal');
      const malformedLoc = '{"type":"location","latitude":"invalid","longitude":null}';
      final enc = await cryptoAlice.encryptMessage(
        roomId: 'room-loc-mal',
        plaintextJson: malformedLoc,
        sessionKey: s['sAlice'],
      );
      final dec = await cryptoBob.decryptMessage(
        roomId: 'room-loc-mal',
        rawBytes: enc,
        sessionKey: s['sBob'],
      );
      expect(dec, equals(malformedLoc));
    });
  });
}
