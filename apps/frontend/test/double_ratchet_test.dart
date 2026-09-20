import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Test Cryptography primitives for Double Ratchet', () async {
    final x25519 = X25519();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
    final hmac = Hmac.sha256();
    final aesGcm = AesGcm.with256bits();

    // 1. Test Key Pair generation and DH
    final aliceKey = await x25519.newKeyPair();
    final bobKey = await x25519.newKeyPair();

    final alicePub = await aliceKey.extractPublicKey();
    final bobPub = await bobKey.extractPublicKey();

    final sharedAlice = await x25519.sharedSecretKey(keyPair: aliceKey, remotePublicKey: bobPub);
    final sharedBob = await x25519.sharedSecretKey(keyPair: bobKey, remotePublicKey: alicePub);

    final sharedBytesAlice = await sharedAlice.extractBytes();
    final sharedBytesBob = await sharedBob.extractBytes();
    expect(sharedBytesAlice, equals(sharedBytesBob));

    // 2. Test KDF_RK: HKDF with 64-byte output
    final dummyRk = SecretKey(List<int>.generate(32, (i) => i));
    final rkOutput = await hkdf.deriveKey(
      secretKey: sharedAlice,
      nonce: await dummyRk.extractBytes(),
      info: utf8.encode('DoubleRatchet-RootKey'),
    );
    final rkOutputBytes = await rkOutput.extractBytes();
    expect(rkOutputBytes.length, 64);

    final newRk = SecretKey(rkOutputBytes.sublist(0, 32));
    final newCk = SecretKey(rkOutputBytes.sublist(32, 64));
    expect((await newRk.extractBytes()).length, 32);
    expect((await newCk.extractBytes()).length, 32);

    // 3. Test KDF_CK: HMAC-SHA256
    final mac1 = await hmac.calculateMac([0x01], secretKey: newCk);
    final mac2 = await hmac.calculateMac([0x02], secretKey: newCk);
    final mk = SecretKey(mac1.bytes);
    final nextCk = SecretKey(mac2.bytes);

    expect(mac1.bytes.length, 32);
    expect(mac2.bytes.length, 32);
    expect(mac1.bytes, isNot(equals(mac2.bytes)));
    expect((await nextCk.extractBytes()).length, 32);

    // 4. Test AES-256-GCM encryption with derived MK
    final nonce = aesGcm.newNonce();
    final secretBox = await aesGcm.encrypt(
      utf8.encode('Test message'),
      secretKey: mk,
      nonce: nonce,
    );

    final decrypted = await aesGcm.decrypt(secretBox, secretKey: mk);
    expect(utf8.decode(decrypted), 'Test message');
  });
}
