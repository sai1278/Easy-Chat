import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Exception thrown when cryptographic verification or integrity fails.
class CryptoException implements Exception {
  final String message;
  CryptoException(this.message);
  @override
  String toString() => 'CryptoException: $message';
}

/// Exception thrown when peer identity changes unexpectedly (MITM detection).
class IdentityChangedException implements Exception {
  final String message;
  IdentityChangedException(this.message);
  @override
  String toString() => 'IdentityChangedException: $message';
}

/// Encrypted media payload packaging ciphertext and ephemeral symmetric key.
class EncryptedAttachmentResult {
  final List<int> ciphertext;
  final String mediaKeyBase64;
  final String nonceBase64;

  const EncryptedAttachmentResult({
    required this.ciphertext,
    required this.mediaKeyBase64,
    required this.nonceBase64,
  });
}

/// Canonical Double Ratchet Session State per conversation room.
/// Complies with the Double Ratchet Algorithm specification (Perrin & Marlinspike, 2016).
class DoubleRatchetSession {
  final String roomId;
  final String peerId;
  final String peerIdentityPubBase64;

  SimpleKeyPair dhs; // Local X25519 ratchet keypair
  SimplePublicKey? dhr; // Remote X25519 ratchet public key
  SecretKey rk; // 32-byte Root Key
  SecretKey? cks; // 32-byte Sending Chain Key
  SecretKey? ckr; // 32-byte Receiving Chain Key
  int ns; // Message number in current sending chain
  int nr; // Message number in current receiving chain
  int pn; // Length of previous sending chain
  bool dhRatchetNeeded; // Flag indicating DH ratchet step needed before next send
  final Map<String, SecretKey> mkSkipped; // Skipped message keys: "$dhPubBase64:$n" -> SecretKey

  DoubleRatchetSession({
    required this.roomId,
    required this.peerId,
    required this.peerIdentityPubBase64,
    required this.dhs,
    this.dhr,
    required this.rk,
    this.cks,
    this.ckr,
    this.ns = 0,
    this.nr = 0,
    this.pn = 0,
    this.dhRatchetNeeded = false,
    Map<String, SecretKey>? mkSkipped,
  }) : mkSkipped = mkSkipped ?? {};

  /// Serializes session state to JSON string for persistent secure storage.
  Future<String> toJson() async {
    final dhsPrivBytes = await dhs.extractPrivateKeyBytes();
    final dhsPub = await dhs.extractPublicKey();
    final rkBytes = await rk.extractBytes();
    final cksBytes = cks != null ? await cks!.extractBytes() : null;
    final ckrBytes = ckr != null ? await ckr!.extractBytes() : null;
    final dhrBytes = dhr != null ? dhr!.bytes : null;

    final skippedMap = <String, String>{};
    for (final entry in mkSkipped.entries) {
      final kBytes = await entry.value.extractBytes();
      skippedMap[entry.key] = base64Encode(kBytes);
    }

    final data = {
      'room_id': roomId,
      'peer_id': peerId,
      'peer_identity_pub': peerIdentityPubBase64,
      'dhs_priv': base64Encode(dhsPrivBytes),
      'dhs_pub': base64Encode(dhsPub.bytes),
      'dhr_pub': dhrBytes != null ? base64Encode(dhrBytes) : null,
      'rk': base64Encode(rkBytes),
      'cks': cksBytes != null ? base64Encode(cksBytes) : null,
      'ckr': ckrBytes != null ? base64Encode(ckrBytes) : null,
      'ns': ns,
      'nr': nr,
      'pn': pn,
      'dh_ratchet_needed': dhRatchetNeeded,
      'skipped': skippedMap,
    };
    return jsonEncode(data);
  }

  /// Deserializes session state from JSON string.
  static Future<DoubleRatchetSession> fromJson(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    final dhsPriv = base64Decode(data['dhs_priv'] as String);
    final dhsPub = base64Decode(data['dhs_pub'] as String);
    final dhsKeyPair = SimpleKeyPairData(
      dhsPriv,
      publicKey: SimplePublicKey(dhsPub, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    SimplePublicKey? dhrPub;
    if (data['dhr_pub'] != null) {
      dhrPub = SimplePublicKey(
        base64Decode(data['dhr_pub'] as String),
        type: KeyPairType.x25519,
      );
    }

    final rk = SecretKey(base64Decode(data['rk'] as String));
    final cks = data['cks'] != null ? SecretKey(base64Decode(data['cks'] as String)) : null;
    final ckr = data['ckr'] != null ? SecretKey(base64Decode(data['ckr'] as String)) : null;

    final skipped = <String, SecretKey>{};
    if (data['skipped'] != null) {
      final sMap = data['skipped'] as Map<String, dynamic>;
      for (final entry in sMap.entries) {
        skipped[entry.key] = SecretKey(base64Decode(entry.value as String));
      }
    }

    return DoubleRatchetSession(
      roomId: data['room_id'] as String,
      peerId: data['peer_id'] as String,
      peerIdentityPubBase64: data['peer_identity_pub'] as String,
      dhs: dhsKeyPair,
      dhr: dhrPub,
      rk: rk,
      cks: cks,
      ckr: ckr,
      ns: data['ns'] as int? ?? 0,
      nr: data['nr'] as int? ?? 0,
      pn: data['pn'] as int? ?? 0,
      dhRatchetNeeded: data['dh_ratchet_needed'] as bool? ?? false,
      mkSkipped: skipped,
    );
  }
}

/// Production-Grade E2EE Service implementing the Double Ratchet Algorithm.
/// Cryptographic Foundation:
/// 1. Asymmetric DH Ratchet: Curve25519 (X25519)
/// 2. Identity Verification: Ed25519
/// 3. Root KDF Chain: HKDF-SHA256 (64-byte expansion: 32 bytes RK, 32 bytes CK)
/// 4. Symmetric Chain Ratchet: HMAC-SHA256 (0x01 for MessageKey, 0x02 for ChainKey)
/// 5. Authenticated AEAD: AES-256-GCM (12-byte IV, 16-byte MAC)
/// 6. Long-Term Key Protection: Hardware Keystore / EncryptedSharedPreferences
class CryptoService {
  final FlutterSecureStorage _secureStorage;
  final Ed25519 _ed25519 = Ed25519();
  final X25519 _x25519 = X25519();
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Hkdf _hkdf64 = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
  final Hkdf _hkdf32 = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final Hmac _hmacSha256 = Hmac.sha256();

  // Active in-memory sessions keyed by roomId
  final Map<String, DoubleRatchetSession> _sessions = {};

  // Maximum number of skipped message keys tracked per session (DoS prevention)
  static const int maxSkippedKeys = 1000;

  CryptoService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  // ===========================================================================
  // KEY MANAGEMENT & ONBOARDING
  // ===========================================================================

  /// Ensures long-term Ed25519 identity key and signed X25519 prekey exist on device.
  Future<void> initKeys() async {
    final existingId = await _secureStorage.read(key: 'e2ee_identity_private_key');
    if (existingId != null && existingId.isNotEmpty) {
      return;
    }

    // 1. Generate Ed25519 Identity Keypair
    final identityKeyPair = await _ed25519.newKeyPair();
    final identityPrivBytes = await identityKeyPair.extractPrivateKeyBytes();
    final identityPub = await identityKeyPair.extractPublicKey();

    await _secureStorage.write(
      key: 'e2ee_identity_private_key',
      value: base64Encode(identityPrivBytes),
    );
    await _secureStorage.write(
      key: 'e2ee_identity_public_key',
      value: base64Encode(identityPub.bytes),
    );

    // 2. Generate X25519 Signed Prekey
    final prekeyPair = await _x25519.newKeyPair();
    final prekeyPrivBytes = await prekeyPair.extractPrivateKeyBytes();
    final prekeyPub = await prekeyPair.extractPublicKey();

    // 3. Sign Prekey using Identity Key
    final signature = await _ed25519.sign(
      prekeyPub.bytes,
      keyPair: identityKeyPair,
    );

    await _secureStorage.write(
      key: 'e2ee_prekey_private_key',
      value: base64Encode(prekeyPrivBytes),
    );
    await _secureStorage.write(
      key: 'e2ee_prekey_public_key',
      value: base64Encode(prekeyPub.bytes),
    );
    await _secureStorage.write(
      key: 'e2ee_prekey_signature',
      value: base64Encode(signature.bytes),
    );
  }

  /// Returns the public bundle to publish to the server for peer key agreement.
  Future<Map<String, String>> getPublicIdentityBundle() async {
    await initKeys();
    final idPub = await _secureStorage.read(key: 'e2ee_identity_public_key') ?? '';
    final prekeyPub = await _secureStorage.read(key: 'e2ee_prekey_public_key') ?? '';
    final prekeySig = await _secureStorage.read(key: 'e2ee_prekey_signature') ?? '';

    return {
      'identity_key_pub': idPub,
      'signed_prekey_pub': prekeyPub,
      'signed_prekey_sig': prekeySig,
    };
  }

  /// Computes deterministic safety number (fingerprint) for out-of-band verification.
  Future<String> computeSafetyNumber(String myIdentityPubBase64, String peerIdentityPubBase64) async {
    final list = [myIdentityPubBase64, peerIdentityPubBase64]..sort();
    final combined = utf8.encode(list.join(':'));
    final hash = await Sha256().hash(combined);
    final hex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return hex.substring(0, 30).toUpperCase();
  }

  // ===========================================================================
  // DOUBLE RATCHET KDF PRIMITIVES
  // ===========================================================================

  /// KDF_RK: Takes Root Key (rk) and DH shared secret (dhOut), derives next Root Key and Chain Key.
  Future<(SecretKey newRk, SecretKey newCk)> _kdfRk(SecretKey rk, SecretKey dhOut) async {
    final derived = await _hkdf64.deriveKey(
      secretKey: dhOut,
      nonce: await rk.extractBytes(),
      info: utf8.encode('DoubleRatchet-RootKey-Derivation'),
    );
    final bytes = await derived.extractBytes();
    final newRk = SecretKey(bytes.sublist(0, 32));
    final newCk = SecretKey(bytes.sublist(32, 64));
    return (newRk, newCk);
  }

  /// KDF_CK: Symmetric Chain Ratchet using HMAC-SHA256.
  /// Generates next Chain Key and single-use Message Key.
  Future<(SecretKey nextCk, SecretKey messageKey)> _kdfCk(SecretKey ck) async {
    final macMk = await _hmacSha256.calculateMac([0x01], secretKey: ck);
    final macNextCk = await _hmacSha256.calculateMac([0x02], secretKey: ck);
    return (SecretKey(macNextCk.bytes), SecretKey(macMk.bytes));
  }

  // ===========================================================================
  // SESSION INITIALIZATION & MANAGEMENT
  // ===========================================================================

  /// Establishes or retrieves the active Double Ratchet session for a given room and peer.
  /// Verifies peer's prekey signature to prevent man-in-the-middle key substitution.
  Future<DoubleRatchetSession> getOrCreateSession({
    required String roomId,
    required String peerId,
    required String peerIdentityPubBase64,
    required String peerSignedPrekeyPubBase64,
    required String peerSignedPrekeySigBase64,
    bool isInitiator = true,
  }) async {
    if (_sessions.containsKey(roomId)) {
      final session = _sessions[roomId]!;
      if (session.peerIdentityPubBase64 != peerIdentityPubBase64) {
        throw IdentityChangedException(
          'Peer identity key changed for room $roomId. Previous: ${session.peerIdentityPubBase64}, New: $peerIdentityPubBase64',
        );
      }
      return session;
    }

    // Attempt restoring session from persistent secure storage
    final persisted = await _secureStorage.read(key: 'e2ee_session_$roomId');
    if (persisted != null && persisted.isNotEmpty) {
      final session = await DoubleRatchetSession.fromJson(persisted);
      if (session.peerIdentityPubBase64 != peerIdentityPubBase64) {
        throw IdentityChangedException(
          'Peer identity key changed for room $roomId. Potential MITM attack detected!',
        );
      }
      _sessions[roomId] = session;
      return session;
    }

    // 1. Authenticate peer identity and verify signed prekey signature
    final peerIdentityPub = SimplePublicKey(
      base64Decode(peerIdentityPubBase64),
      type: KeyPairType.ed25519,
    );
    final peerPrekeyBytes = base64Decode(peerSignedPrekeyPubBase64);
    final peerSigBytes = base64Decode(peerSignedPrekeySigBase64);

    final isValidSignature = await _ed25519.verify(
      peerPrekeyBytes,
      signature: Signature(peerSigBytes, publicKey: peerIdentityPub),
    );

    if (!isValidSignature) {
      throw CryptoException('Peer signed prekey signature verification FAILED! Untrusted peer identity.');
    }

    // 2. Read local long-term private prekey
    await initKeys();
    final myPrekeyPrivStr = await _secureStorage.read(key: 'e2ee_prekey_private_key');
    final myPrekeyPubStr = await _secureStorage.read(key: 'e2ee_prekey_public_key');

    final myPrekeyKeyPair = SimpleKeyPairData(
      base64Decode(myPrekeyPrivStr!),
      publicKey: SimplePublicKey(base64Decode(myPrekeyPubStr!), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    final peerPrekeyPub = SimplePublicKey(peerPrekeyBytes, type: KeyPairType.x25519);

    // 3. Authenticated Initial Key Agreement: ECDH(myPrekey, peerPrekey)
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myPrekeyKeyPair,
      remotePublicKey: peerPrekeyPub,
    );

    // Initial 32-byte Root Key derived from X25519 shared secret
    final initialRk = await _hkdf32.deriveKey(
      secretKey: sharedSecret,
      info: utf8.encode('EasyChat-DoubleRatchet-Root-$roomId'),
      nonce: utf8.encode(roomId),
    );

    DoubleRatchetSession session;

    if (isInitiator) {
      // Alice (initiator): Generate fresh ephemeral ratchet keypair DHs
      final dhs = await _x25519.newKeyPair();
      final dhr = peerPrekeyPub;

      // First DH ratchet step: DH(dhs, dhr) -> derive sending chain
      final dhOut = await _x25519.sharedSecretKey(keyPair: dhs, remotePublicKey: dhr);
      final (newRk, cks) = await _kdfRk(initialRk, dhOut);

      session = DoubleRatchetSession(
        roomId: roomId,
        peerId: peerId,
        peerIdentityPubBase64: peerIdentityPubBase64,
        dhs: dhs,
        dhr: dhr,
        rk: newRk,
        cks: cks,
        ckr: null,
      );
    } else {
      // Bob (responder): Local DHs begins as local signed prekey
      session = DoubleRatchetSession(
        roomId: roomId,
        peerId: peerId,
        peerIdentityPubBase64: peerIdentityPubBase64,
        dhs: myPrekeyKeyPair,
        dhr: null,
        rk: initialRk,
        cks: null,
        ckr: null,
      );
    }

    _sessions[roomId] = session;
    await _saveSession(session);
    return session;
  }

  /// Backward-compatible wrapper returning active session key if required.
  Future<SecretKey> getOrCreateSessionKey({
    required String roomId,
    required String peerId,
    required String peerIdentityPubBase64,
    required String peerSignedPrekeyPubBase64,
    String? peerSignedPrekeySigBase64,
  }) async {
    final session = await getOrCreateSession(
      roomId: roomId,
      peerId: peerId,
      peerIdentityPubBase64: peerIdentityPubBase64,
      peerSignedPrekeyPubBase64: peerSignedPrekeyPubBase64,
      peerSignedPrekeySigBase64: peerSignedPrekeySigBase64 ?? '',
    );
    return session.rk;
  }

  Future<void> _saveSession(DoubleRatchetSession session) async {
    try {
      final jsonStr = await session.toJson();
      await _secureStorage.write(key: 'e2ee_session_${session.roomId}', value: jsonStr);
    } catch (_) {}
  }

  // ===========================================================================
  // DOUBLE RATCHET MESSAGE ENCRYPTION & DECRYPTION
  // ===========================================================================

  /// Encrypts plaintext JSON string using the Double Ratchet algorithm.
  /// Advances sending chain and outputs versioned E2EE:v2 envelope with DH ratchet public key.
  Future<List<int>> encryptMessage({
    required String roomId,
    required String plaintextJson,
    SecretKey? sessionKey, // optional legacy parameter for backward compat
  }) async {
    var session = _sessions[roomId];
    if (session == null) {
      final persisted = await _secureStorage.read(key: 'e2ee_session_$roomId');
      if (persisted != null && persisted.isNotEmpty) {
        session = await DoubleRatchetSession.fromJson(persisted);
        _sessions[roomId] = session;
      }
    }

    if (session == null) {
      throw CryptoException('Cannot encrypt: No active Double Ratchet session for room $roomId');
    }

    // If communication changed direction, or sending chain uninitialized:
    // Execute Asymmetric DH Ratchet Step 2 (generate new local keypair and derive fresh sending chain)
    if (session.dhRatchetNeeded || session.cks == null) {
      if (session.dhr == null) {
        throw CryptoException('Cannot encrypt: Remote DH ratchet public key unknown');
      }
      final newDhs = await _x25519.newKeyPair();
      final dhOut = await _x25519.sharedSecretKey(keyPair: newDhs, remotePublicKey: session.dhr!);
      final (newRk, newCks) = await _kdfRk(session.rk, dhOut);

      session.dhs = newDhs;
      session.rk = newRk;
      session.cks = newCks;
      session.pn = session.ns;
      session.ns = 0;
      session.dhRatchetNeeded = false;
    }

    // 1. Advance Sending Chain: (nextCks, mk) = KDF_CK(cks)
    final (nextCks, messageKey) = await _kdfCk(session.cks!);
    session.cks = nextCks;
    final currentN = session.ns;
    session.ns++;

    // 2. Prepare Header
    final dhsPub = await session.dhs.extractPublicKey();
    final dhPubBase64 = base64Encode(dhsPub.bytes);

    // 3. Encrypt payload with AES-256-GCM using single-use messageKey
    final nonce = _aesGcm.newNonce();
    final plainBytes = utf8.encode(plaintextJson);

    final secretBox = await _aesGcm.encrypt(
      plainBytes,
      secretKey: messageKey,
      nonce: nonce,
    );

    // 4. Package into versioned E2EE:v2: envelope
    final envelope = {
      'v': 2,
      'dh': dhPubBase64,
      'pn': session.pn,
      'n': currentN,
      'iv': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
      'ct': base64Encode(secretBox.cipherText),
    };

    await _saveSession(session);

    return utf8.encode('E2EE:v2:' + jsonEncode(envelope));
  }

  /// Decrypts an authenticated E2EE envelope using the Double Ratchet algorithm.
  /// Performs asymmetric DH ratchet step when remote ratchet key rotates.
  /// Handles out-of-order and skipped messages securely.
  /// NO AUTOMATIC PLAINTEXT FALLBACK: Malformed or unauthenticated data throws CryptoException.
  Future<String> decryptMessage({
    required String roomId,
    required List<int> rawBytes,
    SecretKey? sessionKey, // optional legacy parameter
  }) async {
    final rawString = utf8.decode(rawBytes, allowMalformed: false);

    // Strict validation: Reject unencrypted data immediately
    if (!rawString.startsWith('E2EE:v2:') && !rawString.startsWith('E2EE:v1:')) {
      throw CryptoException('Message rejection: Missing authenticated E2EE envelope. Plaintext prohibited.');
    }

    // Handle legacy v1 envelope if encountered
    if (rawString.startsWith('E2EE:v1:')) {
      return _decryptV1Legacy(roomId: roomId, rawString: rawString, sessionKey: sessionKey);
    }

    final envelopeJson = rawString.substring('E2EE:v2:'.length);
    Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(envelopeJson) as Map<String, dynamic>;
    } catch (_) {
      throw CryptoException('Message rejection: Malformed E2EE envelope JSON.');
    }

    final remoteDhPubBase64 = envelope['dh'] as String?;
    final pn = envelope['pn'] as int?;
    final n = envelope['n'] as int?;
    final ivStr = envelope['iv'] as String?;
    final macStr = envelope['mac'] as String?;
    final ctStr = envelope['ct'] as String?;

    if (remoteDhPubBase64 == null || pn == null || n == null || ivStr == null || macStr == null || ctStr == null) {
      throw CryptoException('Message rejection: Incomplete E2EE:v2 envelope attributes.');
    }

    var session = _sessions[roomId];
    if (session == null) {
      final persisted = await _secureStorage.read(key: 'e2ee_session_$roomId');
      if (persisted != null && persisted.isNotEmpty) {
        session = await DoubleRatchetSession.fromJson(persisted);
        _sessions[roomId] = session;
      }
    }

    if (session == null) {
      throw CryptoException('Cannot decrypt: No active Double Ratchet session for room $roomId');
    }

    final nonceBytes = base64Decode(ivStr);
    final macBytes = base64Decode(macStr);
    final cipherTextBytes = base64Decode(ctStr);

    final secretBox = SecretBox(
      cipherTextBytes,
      nonce: nonceBytes,
      mac: Mac(macBytes),
    );

    // STEP A: Check if key was previously skipped for out-of-order delivery
    final skippedKeyId = '$remoteDhPubBase64:$n';
    if (session.mkSkipped.containsKey(skippedKeyId)) {
      final mk = session.mkSkipped.remove(skippedKeyId)!;
      try {
        final decryptedBytes = await _aesGcm.decrypt(secretBox, secretKey: mk);
        await _saveSession(session);
        return utf8.decode(decryptedBytes);
      } catch (_) {
        throw CryptoException('Message decryption failed: MAC verification failure on skipped key.');
      }
    }

    // STEP B: Check if remote sent a new DH ratchet public key (Asymmetric Ratchet Transition!)
    final remoteDhPubBytes = base64Decode(remoteDhPubBase64);

    // Defensive check: Outgoing messages use local dhs; attempting to ratchet on self-sent
    // messages corrupts the state machine and violates Signal Double Ratchet protocol.
    final selfDhPub = await session.dhs.extractPublicKey();
    if (_bytesEqual(selfDhPub.bytes, remoteDhPubBytes)) {
      throw CryptoException('Self-sent message cannot be decrypted via Double Ratchet receiving chain.');
    }

    final currentDhrBytes = session.dhr != null ? session.dhr!.bytes : null;

    final isNewDhRatchet = currentDhrBytes == null || !_bytesEqual(currentDhrBytes, remoteDhPubBytes);

    if (isNewDhRatchet) {
      // 1. Skip any unreceived messages in the previous receiving chain up to pn
      if (session.dhr != null && session.ckr != null) {
        await _skipMessageKeys(session, session.dhr!, pn);
      }

      // 2. Asymmetric DH Ratchet Step 1: Advance receiving chain with remote's new ratchet key
      final newDhr = SimplePublicKey(remoteDhPubBytes, type: KeyPairType.x25519);
      final dhOut1 = await _x25519.sharedSecretKey(keyPair: session.dhs, remotePublicKey: newDhr);
      final (rk1, ckr1) = await _kdfRk(session.rk, dhOut1);

      session.rk = rk1;
      session.ckr = ckr1;
      session.dhr = newDhr;
      session.nr = 0;
      session.dhRatchetNeeded = true; // Signal that next local send must perform DH ratchet step
    }

    // STEP C: Skip any unreceived messages in the current receiving chain up to message number n
    if (session.ckr == null) {
      throw CryptoException('Message decryption failed: Receiving chain uninitialized.');
    }
    await _skipMessageKeys(session, session.dhr!, n);

    // STEP D: Advance receiving chain for message n: (nextCkr, mk) = KDF_CK(ckr)
    if (session.nr != n) {
      throw CryptoException('Replayed or duplicate message rejected (nr=${session.nr}, n=$n)');
    }

    final (nextCkr, mk) = await _kdfCk(session.ckr!);
    session.ckr = nextCkr;
    session.nr++;

    // STEP E: Decrypt payload with AES-256-GCM
    try {
      final decryptedBytes = await _aesGcm.decrypt(secretBox, secretKey: mk);
      await _saveSession(session);
      return utf8.decode(decryptedBytes);
    } catch (_) {
      throw CryptoException('Message decryption failed: AEAD authentication check failed. Ciphertext or tag tampered.');
    }
  }

  /// Advances receiving chain and stores skipped message keys for out-of-order delivery.
  Future<void> _skipMessageKeys(DoubleRatchetSession session, SimplePublicKey dhr, int until) async {
    if (session.ckr == null) return;
    if (session.nr + maxSkippedKeys < until) {
      throw CryptoException('Excessive skipped messages (${until - session.nr}); rejecting potential DoS flood.');
    }

    final dhrBase64 = base64Encode(dhr.bytes);
    while (session.nr < until) {
      final (nextCkr, mk) = await _kdfCk(session.ckr!);
      session.ckr = nextCkr;

      // Cap map size to prevent unbounded memory growth
      if (session.mkSkipped.length >= maxSkippedKeys) {
        session.mkSkipped.remove(session.mkSkipped.keys.first);
      }
      session.mkSkipped['$dhrBase64:${session.nr}'] = mk;
      session.nr++;
    }
  }

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Handles legacy v1 envelopes strictly without plaintext fallback.
  Future<String> _decryptV1Legacy({
    required String roomId,
    required String rawString,
    SecretKey? sessionKey,
  }) async {
    if (sessionKey == null) {
      final session = _sessions[roomId];
      if (session != null) {
        sessionKey = session.rk;
      } else {
        throw CryptoException('Legacy v1 decryption failed: Missing session key.');
      }
    }

    final envelopeJson = rawString.substring('E2EE:v1:'.length);
    final envelope = jsonDecode(envelopeJson) as Map<String, dynamic>;

    final counter = envelope['c'] as int;
    final nonceBytes = base64Decode(envelope['n'] as String);
    final macBytes = base64Decode(envelope['t'] as String);
    final cipherTextBytes = base64Decode(envelope['ct'] as String);

    final messageKey = await _hkdf32.deriveKey(
      secretKey: sessionKey,
      info: utf8.encode('MessageKey-$counter'),
      nonce: utf8.encode('Nonce-$roomId-$counter'),
    );

    final secretBox = SecretBox(
      cipherTextBytes,
      nonce: nonceBytes,
      mac: Mac(macBytes),
    );

    try {
      final decryptedBytes = await _aesGcm.decrypt(secretBox, secretKey: messageKey);
      return utf8.decode(decryptedBytes);
    } catch (_) {
      throw CryptoException('Legacy v1 decryption failed: Authentication tag mismatch.');
    }
  }

  // ===========================================================================
  // ATTACHMENT ENCRYPTION & DECRYPTION (SINGLE-USE AES-256-GCM)
  // ===========================================================================

  /// Encrypts raw attachment bytes (image / voice) using a fresh single-use 256-bit symmetric key.
  /// The server only receives and stores opaque ciphertext.
  Future<EncryptedAttachmentResult> encryptAttachment(List<int> rawBytes) async {
    final secretKey = await _aesGcm.newSecretKey();
    final nonce = _aesGcm.newNonce();

    final secretBox = await _aesGcm.encrypt(
      rawBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    // Concatenate ciphertext + authentication tag for clean upload blob
    final combinedCiphertext = secretBox.concatenation();

    final keyBytes = await secretKey.extractBytes();
    return EncryptedAttachmentResult(
      ciphertext: combinedCiphertext,
      mediaKeyBase64: base64Encode(keyBytes),
      nonceBase64: base64Encode(nonce),
    );
  }

  /// Decrypts downloaded attachment ciphertext bytes using the media key and nonce
  /// distributed inside the E2EE chat message payload.
  Future<List<int>> decryptAttachment({
    required List<int> ciphertextBytes,
    required String mediaKeyBase64,
    required String nonceBase64,
  }) async {
    final keyBytes = base64Decode(mediaKeyBase64);
    final secretKey = SecretKey(keyBytes);
    final nonceBytes = base64Decode(nonceBase64);

    final secretBox = SecretBox.fromConcatenation(
      ciphertextBytes,
      nonceLength: nonceBytes.length,
      macLength: 16,
    );

    try {
      return await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );
    } catch (_) {
      throw CryptoException('Attachment decryption failed: Authentication tag check failed.');
    }
  }

  /// Internal diagnostic accessor to audit ratchet state for verification tests.
  DoubleRatchetSession? getSession(String roomId) => _sessions[roomId];
}
