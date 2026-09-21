/// Emits Dart-produced crypto output as JSON for Python to verify.
///
/// Paired with `backend/scripts/verify_dart_crypto.py`, this closes the loop that
/// the unit tests cannot: those decrypt Python's output in Dart, while this proves
/// the server can decrypt *Dart's* output — the direction that actually matters
/// for requests leaving the device.
///
/// Usage:
///   `dart run tool/emit_crypto_output.dart fixture.json > dart_output.json`
library;

import 'dart:convert';
import 'dart:io';

import 'package:duiliao_app/core/crypto/duiliao_crypto.dart';

void main(List<String> args) {
  final fixturePath =
      args.isNotEmpty ? args.first : 'assets/fixtures/crypto_vectors.json';
  final vectors =
      jsonDecode(File(fixturePath).readAsStringSync()) as Map<String, dynamic>;

  final crypto = DuiliaoCrypto();
  final rsa = vectors['rsa'] as Map;
  final signingSecret = vectors['signing_secret'] as String;

  // 1. Wrap a fresh AES key with the server's public key.
  final publicKey =
      DuiliaoCrypto.parseSpkiPublicKey(rsa['public_key_spki_b64'] as String);
  final aesKey = crypto.generateAesKey();
  final wrappedKey = DuiliaoCrypto.wrapAesKey(publicKey, aesKey);

  // 2. Encrypt several payloads under that key, including non-ASCII and a body
  //    large enough to span multiple AES blocks.
  final payloads = <String>[
    '',
    'hello from dart',
    jsonEncode({'ok': true, 'period': '2026248', 'tema': '28'}),
    '澳门 平特肖 猪猪猪 — 连肖检测',
    'x' * 5000,
  ];
  final encrypted = payloads.map((text) {
    final envelope = crypto.aesEncrypt(aesKey, utf8.encode(text));
    return {
      'expected_plaintext': text,
      'iv': envelope.iv,
      'ciphertext': envelope.ciphertext,
    };
  }).toList();

  // 3. Produce signatures over realistic request bodies.
  final signatures = <Map<String, dynamic>>[];
  for (final body in <List<int>>[
    const <int>[],
    utf8.encode(jsonEncode(crypto.aesEncrypt(aesKey, utf8.encode('{"a":1}')).toJson())),
  ]) {
    const sessionId = 'dart-session-id';
    const timestamp = '1767225600';
    final nonce = crypto.randomNonceHex();
    signatures.add({
      'session_id': sessionId,
      'timestamp': timestamp,
      'nonce': nonce,
      'body_b64': DuiliaoCrypto.b64Encode(body),
      'signature': DuiliaoCrypto.signRequest(
        secret: signingSecret,
        sessionId: sessionId,
        timestamp: timestamp,
        nonce: nonce,
        bodyBytes: body,
      ),
    });
  }

  stdout.write(
    jsonEncode({
      'library': 'pointycastle',
      'wrapped_aes_key_b64': wrappedKey,
      'expected_aes_key_b64': DuiliaoCrypto.b64Encode(aesKey),
      'encrypted': encrypted,
      'signatures': signatures,
      'sha256_empty': DuiliaoCrypto.sha256Hex(const []),
    }),
  );
}
