import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nearby_frontend/core/crypto/crypto_service.dart';

class InMemorySecureStorage extends Fake implements FlutterSecureStorage {
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

  group('Google-Grade Double Ratchet Cryptographic Hardening Suite', () {
    late InMemorySecureStorage storageAlice;
    late InMemorySecureStorage storageBob;
    late CryptoService cryptoAlice;
    late CryptoService cryptoBob;

    setUp(() async {
      storageAlice = InMemorySecureStorage();
      storageBob = InMemorySecureStorage();
      cryptoAlice = CryptoService(secureStorage: storageAlice);
      cryptoBob = CryptoService(secureStorage: storageBob);

      await cryptoAlice.initKeys();
      await cryptoBob.initKeys();
    });

    // =========================================================================
    // PHASE 3: DOUBLE RATCHET SOURCE & BEHAVIOR AUDIT
    // =========================================================================
    test('PHASE 3: Asymmetric DH ratchet steps on conversation turns', () async {
      const roomId = 'audit-room-turns-1';
      final bundleAlice = await cryptoAlice.getPublicIdentityBundle();
      final bundleBob = await cryptoBob.getPublicIdentityBundle();

      // 1. Initial Setup: Alice (initiator) establishes Double Ratchet session
      final sessionAlice = await cryptoAlice.getOrCreateSession(
        roomId: roomId,
        peerId: 'user-bob',
        peerIdentityPubBase64: bundleBob['identity_key_pub']!,
        peerSignedPrekeyPubBase64: bundleBob['signed_prekey_pub']!,
        peerSignedPrekeySigBase64: bundleBob['signed_prekey_sig']!,
        isInitiator: true,
      );

      final sessionBob = await cryptoBob.getOrCreateSession(
        roomId: roomId,
        peerId: 'user-alice',
        peerIdentityPubBase64: bundleAlice['identity_key_pub']!,
        peerSignedPrekeyPubBase64: bundleAlice['signed_prekey_pub']!,
        peerSignedPrekeySigBase64: bundleAlice['signed_prekey_sig']!,
        isInitiator: false,
      );

      final initialRkAlice = await sessionAlice.rk.extractBytes();

      // Alice sends Message 1
      final m1 = await cryptoAlice.encryptMessage(
        roomId: roomId,
        plaintextJson: '{"type":"text","text":"Alice M1"}',
      );
      expect(sessionAlice.ns, 1, reason: 'Alice sending chain must advance to 1');

      // Alice sends Message 2
      final m2 = await cryptoAlice.encryptMessage(
        roomId: roomId,
        plaintextJson: '{"type":"text","text":"Alice M2"}',
      );
      expect(sessionAlice.ns, 2, reason: 'Alice sending chain must advance to 2');

      // Verify Root Key has NOT changed yet (same sending chain)
      final rkAliceAfterM2 = await sessionAlice.rk.extractBytes();
      expect(rkAliceAfterM2, equals(initialRkAlice), reason: 'Symmetric chain advances without changing Root Key');

      // Bob receives Message 1 and Message 2
      final decBobM1 = await cryptoBob.decryptMessage(roomId: roomId, rawBytes: m1);
      expect(decBobM1, '{"type":"text","text":"Alice M1"}');
      expect(sessionBob.nr, 1, reason: 'Bob receiving chain must advance to 1');

      final decBobM2 = await cryptoBob.decryptMessage(roomId: roomId, rawBytes: m2);
      expect(decBobM2, '{"type":"text","text":"Alice M2"}');
      expect(sessionBob.nr, 2, reason: 'Bob receiving chain must advance to 2');

      // TURN SWITCH: Bob sends Reply to Alice
      // Must execute an asymmetric DH Ratchet step!
      final rkBobBeforeReply = await sessionBob.rk.extractBytes();
      final replyBob = await cryptoBob.encryptMessage(
        roomId: roomId,
        plaintextJson: '{"type":"text","text":"Bob Reply 1"}',
      );

      // Verify Bob's Root Key CHANGED due to DH Ratchet!
      final rkBobAfterReply = await sessionBob.rk.extractBytes();
      expect(rkBobAfterReply, isNot(equals(rkBobBeforeReply)), reason: 'DH Ratchet MUST change Root Key on direction change');
      expect(sessionBob.ns, 1, reason: 'Bob sending chain initialized and advanced to 1');

      // Alice receives Bob's Reply
      final rkAliceBeforeReply = await sessionAlice.rk.extractBytes();
      final decAliceReply = await cryptoAlice.decryptMessage(roomId: roomId, rawBytes: replyBob);
      expect(decAliceReply, '{"type":"text","text":"Bob Reply 1"}');

      // Verify Alice's Root Key CHANGED after processing Bob's new DH key!
      final rkAliceAfterReply = await sessionAlice.rk.extractBytes();
      expect(rkAliceAfterReply, isNot(equals(rkAliceBeforeReply)), reason: 'Alice Root Key MUST change upon receiving new DH public key');
      expect(sessionAlice.dhRatchetNeeded, isTrue, reason: 'Alice flagged for DH ratchet step on next send');

      // Next Turn: Alice sends Message 3 to Bob (triggers Alice DH sending ratchet step)
      final m3 = await cryptoAlice.encryptMessage(
        roomId: roomId,
        plaintextJson: '{"type":"text","text":"Alice M3"}',
      );
      expect(sessionAlice.ns, 1, reason: 'Alice sending chain advanced for M3');
      expect(sessionAlice.pn, 2, reason: 'Alice recorded previous chain length as 2');

      final decBobM3 = await cryptoBob.decryptMessage(roomId: roomId, rawBytes: m3);
      expect(decBobM3, '{"type":"text","text":"Alice M3"}');
    });

    // =========================================================================
    // PHASE 4: FORWARD SECRECY TEST
    // =========================================================================
    test('PHASE 4: Forward Secrecy guarantees past message keys cannot be derived from current state', () async {
      const roomId = 'audit-room-forward-secrecy';
      final bundleAlice = await cryptoAlice.getPublicIdentityBundle();
      final bundleBob = await cryptoBob.getPublicIdentityBundle();

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

      // Send 3 sequential messages
      final c1 = await cryptoAlice.encryptMessage(roomId: roomId, plaintextJson: 'Secret 1');
      final c2 = await cryptoAlice.encryptMessage(roomId: roomId, plaintextJson: 'Secret 2');
      final c3 = await cryptoAlice.encryptMessage(roomId: roomId, plaintextJson: 'Secret 3');

      // Bob decrypts all 3
      await cryptoBob.decryptMessage(roomId: roomId, rawBytes: c1);
      await cryptoBob.decryptMessage(roomId: roomId, rawBytes: c2);
      await cryptoBob.decryptMessage(roomId: roomId, rawBytes: c3);

      final sessionBob = cryptoBob.getSession(roomId)!;

      // Verify previous message keys are completely deleted
      expect(sessionBob.mkSkipped.isEmpty, isTrue, reason: 'Delivered message keys must be purged immediately');
      expect(sessionBob.nr, 3);

      // Verify that attempting to decrypt c1 again with the current receiving chain fails (replay protection)
      expect(
        () async => await cryptoBob.decryptMessage(roomId: roomId, rawBytes: c1),
        throwsA(isA<CryptoException>()),
        reason: 'Replayed past message must fail authentication and cannot be decrypted again',
      );
    });

    // =========================================================================
    // PHASE 5: POST-COMPROMISE SECURITY (SELF-HEALING RATCHET)
    // =========================================================================
    test('PHASE 5: DH ratchet transition establishes unpredictable state after direction change', () async {
      const roomId = 'audit-room-post-compromise';
      final bundleAlice = await cryptoAlice.getPublicIdentityBundle();
      final bundleBob = await cryptoBob.getPublicIdentityBundle();

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

      // Alice sends message
      final aMsg = await cryptoAlice.encryptMessage(roomId: roomId, plaintextJson: 'Alice pre-compromise');
      await cryptoBob.decryptMessage(roomId: roomId, rawBytes: aMsg);

      // Attacker clones/compromises current state of Bob at this moment
      final compromisedRk = await cryptoBob.getSession(roomId)!.rk.extractBytes();

      // Bob sends reply to Alice (fresh DH ratchet)
      final bMsg = await cryptoBob.encryptMessage(roomId: roomId, plaintextJson: 'Bob self-healing response');
      await cryptoAlice.decryptMessage(roomId: roomId, rawBytes: bMsg);

      // Alice sends post-compromise message
      final postCompromiseMsg = await cryptoAlice.encryptMessage(roomId: roomId, plaintextJson: 'Alice post-compromise secret');

      // Bob decrypts post-compromise message cleanly
      final decrypted = await cryptoBob.decryptMessage(roomId: roomId, rawBytes: postCompromiseMsg);
      expect(decrypted, 'Alice post-compromise secret');

      // The new Root Keys of both parties are completely derived from fresh ephemeral X25519 DH
      final healedRkBob = await cryptoBob.getSession(roomId)!.rk.extractBytes();
      final healedRkAlice = await cryptoAlice.getSession(roomId)!.rk.extractBytes();

      expect(healedRkBob, isNot(equals(compromisedRk)), reason: 'Compromised key state cannot match post-ratchet root key');
      expect(healedRkAlice, equals(healedRkBob), reason: 'Both parties synchronize to identical healed root key');
    });

    // =========================================================================
    // PHASE 6: OUT-OF-ORDER MESSAGE & REPLAY HANDLING
    // =========================================================================
    test('PHASE 6: Out-of-order delivery (M1, M3, M2) decrypts correctly and rejects replays', () async {
      const roomId = 'audit-room-ooo-delivery';
      final bundleAlice = await cryptoAlice.getPublicIdentityBundle();
      final bundleBob = await cryptoBob.getPublicIdentityBundle();

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

      // Alice sends M1, M2, M3
      final m1 = await cryptoAlice.encryptMessage(roomId: roomId, plaintextJson: 'Message 1');
      final m2 = await cryptoAlice.encryptMessage(roomId: roomId, plaintextJson: 'Message 2');
      final m3 = await cryptoAlice.encryptMessage(roomId: roomId, plaintextJson: 'Message 3');

      // Network delivers out-of-order: M1 -> M3 -> M2
      final d1 = await cryptoBob.decryptMessage(roomId: roomId, rawBytes: m1);
      expect(d1, 'Message 1');

      // Deliver M3 before M2: Bob must skip M2 and store its key in mkSkipped
      final d3 = await cryptoBob.decryptMessage(roomId: roomId, rawBytes: m3);
      expect(d3, 'Message 3');
      expect(cryptoBob.getSession(roomId)!.mkSkipped.length, 1, reason: 'M2 message key must be saved in mkSkipped');

      // Deliver M2: Bob must retrieve key from mkSkipped and decrypt
      final d2 = await cryptoBob.decryptMessage(roomId: roomId, rawBytes: m2);
      expect(d2, 'Message 2');
      expect(cryptoBob.getSession(roomId)!.mkSkipped.isEmpty, true, reason: 'Used skipped key must be evicted immediately');

      // Replay M3: Must be rejected
      expect(
        () async => await cryptoBob.decryptMessage(roomId: roomId, rawBytes: m3),
        throwsA(isA<CryptoException>()),
      );

      // Replay M2: Must be rejected
      expect(
        () async => await cryptoBob.decryptMessage(roomId: roomId, rawBytes: m2),
        throwsA(isA<CryptoException>()),
      );
    });

    // =========================================================================
    // PHASE 7: MULTI-DEVICE / SESSION PERSISTENCE & RESTART
    // =========================================================================
    test('PHASE 7: Session state persists across cold app restarts and handles identity replacement', () async {
      const roomId = 'audit-room-restart-persistence';
      final bundleAlice = await cryptoAlice.getPublicIdentityBundle();
      final bundleBob = await cryptoBob.getPublicIdentityBundle();

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

      final m1 = await cryptoAlice.encryptMessage(roomId: roomId, plaintextJson: 'Pre-restart message');
      await cryptoBob.decryptMessage(roomId: roomId, rawBytes: m1);

      // SIMULATE COLD RESTART: Create new CryptoService instances with the same persistent storage
      final restartedAlice = CryptoService(secureStorage: storageAlice);
      final restartedBob = CryptoService(secureStorage: storageBob);

      // Alice sends message after cold restart
      final m2 = await restartedAlice.encryptMessage(roomId: roomId, plaintextJson: 'Post-restart message from Alice');
      final d2 = await restartedBob.decryptMessage(roomId: roomId, rawBytes: m2);
      expect(d2, 'Post-restart message from Alice');

      // Test Identity Replacement: An attacker or fresh install of Bob presents a different identity key
      final fakeIdentity = base64Encode(List<int>.generate(32, (i) => 0xFF - i));
      expect(
        () async => await restartedAlice.getOrCreateSession(
          roomId: roomId,
          peerId: 'user-bob',
          peerIdentityPubBase64: fakeIdentity,
          peerSignedPrekeyPubBase64: bundleBob['signed_prekey_pub']!,
          peerSignedPrekeySigBase64: bundleBob['signed_prekey_sig']!,
        ),
        throwsA(isA<IdentityChangedException>()),
        reason: 'Untrusted identity key replacement must throw IdentityChangedException',
      );
    });

    // =========================================================================
    // PHASE 8: KEY AUTHENTICATION & MITM PREVENTION
    // =========================================================================
    test('PHASE 8: Key authentication blocks forged prekey without valid signature', () async {
      const roomId = 'audit-room-mitm-defense';
      final bundleAlice = await cryptoAlice.getPublicIdentityBundle();
      final bundleBob = await cryptoBob.getPublicIdentityBundle();

      // Attacker swaps Bob's prekey with attacker's prekey but cannot forge Bob's Ed25519 signature
      final attackerPrekey = base64Encode(List<int>.generate(32, (i) => 0x99));

      expect(
        () async => await cryptoAlice.getOrCreateSession(
          roomId: roomId,
          peerId: 'user-bob',
          peerIdentityPubBase64: bundleBob['identity_key_pub']!,
          peerSignedPrekeyPubBase64: attackerPrekey,
          peerSignedPrekeySigBase64: bundleBob['signed_prekey_sig']!, // signature over original prekey
          isInitiator: true,
        ),
        throwsA(isA<CryptoException>()),
        reason: 'Forged prekey must fail Ed25519 signature verification',
      );

      // Verify Safety Number derivation is deterministic
      final safetyNum1 = await cryptoAlice.computeSafetyNumber(bundleAlice['identity_key_pub']!, bundleBob['identity_key_pub']!);
      final safetyNum2 = await cryptoBob.computeSafetyNumber(bundleBob['identity_key_pub']!, bundleAlice['identity_key_pub']!);
      expect(safetyNum1, equals(safetyNum2));
      expect(safetyNum1.length, 30);
    });

    // =========================================================================
    // PHASE 29 & 30: CRYPTOGRAPHIC NEGATIVE TESTS & NO PLAINTEXT FALLBACK
    // =========================================================================
    test('PHASE 29 & 30: Cryptographic negative matrix verifies secure failure with ZERO plaintext fallback', () async {
      const roomId = 'audit-room-negative-matrix';
      final bundleAlice = await cryptoAlice.getPublicIdentityBundle();
      final bundleBob = await cryptoBob.getPublicIdentityBundle();

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

      final validEncrypted = await cryptoAlice.encryptMessage(
        roomId: roomId,
        plaintextJson: 'Secret Negative Payload',
      );

      // 1. Raw Plaintext input MUST fail (NO automatic fallback to plaintext!)
      final rawPlaintext = utf8.encode('{"type":"text","text":"I am plaintext"}');
      expect(
        () async => await cryptoBob.decryptMessage(roomId: roomId, rawBytes: rawPlaintext),
        throwsA(isA<CryptoException>()),
        reason: 'CRITICAL: Raw plaintext must NOT be accepted or returned',
      );

      // 2. Tampered Ciphertext bytes MUST fail MAC verification
      final envJsonStr = utf8.decode(validEncrypted).substring('E2EE:v2:'.length);
      final env = jsonDecode(envJsonStr) as Map<String, dynamic>;
      final ctBytes = base64Decode(env['ct'] as String);
      ctBytes[0] ^= 0x01; // flip bit
      env['ct'] = base64Encode(ctBytes);
      final tamperedCiphertext = utf8.encode('E2EE:v2:' + jsonEncode(env));

      expect(
        () async => await cryptoBob.decryptMessage(roomId: roomId, rawBytes: tamperedCiphertext),
        throwsA(isA<CryptoException>()),
      );

      // 3. Modified Nonce/IV MUST fail MAC verification
      env['ct'] = base64Encode(base64Decode(env['ct'] as String)..setAll(0, [ctBytes[0] ^ 0x01])); // restore
      final ivBytes = base64Decode(env['iv'] as String);
      ivBytes[0] ^= 0x01;
      env['iv'] = base64Encode(ivBytes);
      final tamperedNonce = utf8.encode('E2EE:v2:' + jsonEncode(env));

      expect(
        () async => await cryptoBob.decryptMessage(roomId: roomId, rawBytes: tamperedNonce),
        throwsA(isA<CryptoException>()),
      );

      // 4. Modified MAC tag MUST fail verification
      final macBytes = base64Decode(env['mac'] as String);
      macBytes[0] ^= 0xFF;
      env['mac'] = base64Encode(macBytes);
      final tamperedMac = utf8.encode('E2EE:v2:' + jsonEncode(env));

      expect(
        () async => await cryptoBob.decryptMessage(roomId: roomId, rawBytes: tamperedMac),
        throwsA(isA<CryptoException>()),
      );

      // 5. Malformed envelope JSON MUST fail cleanly without crashing
      expect(
        () async => await cryptoBob.decryptMessage(roomId: roomId, rawBytes: utf8.encode('E2EE:v2:{bad-json}')),
        throwsA(isA<CryptoException>()),
      );

      // 6. Truncated envelope MUST fail cleanly
      expect(
        () async => await cryptoBob.decryptMessage(roomId: roomId, rawBytes: utf8.encode('E2EE:v2:{"v":2}')),
        throwsA(isA<CryptoException>()),
      );
    });

    // =========================================================================
    // ALL FOUR MESSAGE TYPES E2EE (TEXT, IMAGE, VOICE, LOCATION)
    // =========================================================================
    test('PHASE 9 & 10: Genuine E2EE verification across TEXT, IMAGE, VOICE, LOCATION', () async {
      const roomId = 'audit-room-all-types';
      final bundleAlice = await cryptoAlice.getPublicIdentityBundle();
      final bundleBob = await cryptoBob.getPublicIdentityBundle();

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

      // 1. TEXT
      final textJson = '{"type":"text","text":"Hello Bob, Double Ratchet works!"}';
      final encText = await cryptoAlice.encryptMessage(roomId: roomId, plaintextJson: textJson);
      expect(utf8.decode(encText).startsWith('E2EE:v2:'), isTrue);
      expect(utf8.decode(encText).contains('Hello Bob'), isFalse);
      final decText = await cryptoBob.decryptMessage(roomId: roomId, rawBytes: encText);
      expect(decText, equals(textJson));

      // 2. IMAGE ATTACHMENT
      final rawImage = List<int>.generate(2048, (i) => (i * 17) % 256);
      final encImageAttachment = await cryptoAlice.encryptAttachment(rawImage);
      final imageJson = jsonEncode({
        'type': 'image',
        'media_url': 'http://192.168.1.2:8090/media/download/uuid-img-123',
        'media_key': encImageAttachment.mediaKeyBase64,
        'nonce': encImageAttachment.nonceBase64,
      });
      final encImageMsg = await cryptoAlice.encryptMessage(roomId: roomId, plaintextJson: imageJson);
      final decImageMsg = await cryptoBob.decryptMessage(roomId: roomId, rawBytes: encImageMsg);
      final parsedImg = jsonDecode(decImageMsg) as Map<String, dynamic>;
      final decImage = await cryptoBob.decryptAttachment(
        ciphertextBytes: encImageAttachment.ciphertext,
        mediaKeyBase64: parsedImg['media_key'] as String,
        nonceBase64: parsedImg['nonce'] as String,
      );
      expect(decImage, equals(rawImage));

      // 3. VOICE ATTACHMENT
      final rawVoice = utf8.encode('m4a-audio-binary-stream-google-qualification');
      final encVoiceAttachment = await cryptoAlice.encryptAttachment(rawVoice);
      final voiceJson = jsonEncode({
        'type': 'voice',
        'media_url': 'http://192.168.1.2:8090/media/download/uuid-voice-456',
        'media_key': encVoiceAttachment.mediaKeyBase64,
        'nonce': encVoiceAttachment.nonceBase64,
        'duration_seconds': 5,
      });
      final encVoiceMsg = await cryptoAlice.encryptMessage(roomId: roomId, plaintextJson: voiceJson);
      final decVoiceMsg = await cryptoBob.decryptMessage(roomId: roomId, rawBytes: encVoiceMsg);
      final parsedVoice = jsonDecode(decVoiceMsg) as Map<String, dynamic>;
      final decVoice = await cryptoBob.decryptAttachment(
        ciphertextBytes: encVoiceAttachment.ciphertext,
        mediaKeyBase64: parsedVoice['media_key'] as String,
        nonceBase64: parsedVoice['nonce'] as String,
      );
      expect(decVoice, equals(rawVoice));

      // 4. LOCATION PAYLOAD
      final locJson = jsonEncode({
        'type': 'location',
        'latitude': 13.0827,
        'longitude': 80.2707,
        'accuracy': 15.0,
      });
      final encLocMsg = await cryptoAlice.encryptMessage(roomId: roomId, plaintextJson: locJson);
      expect(utf8.decode(encLocMsg).contains('13.0827'), isFalse);
      expect(utf8.decode(encLocMsg).contains('80.2707'), isFalse);
      final decLocMsg = await cryptoBob.decryptMessage(roomId: roomId, rawBytes: encLocMsg);
      expect(decLocMsg, equals(locJson));
    });
  });
}
