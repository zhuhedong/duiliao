/// Dart <-> Python crypto interoperability.
///
/// Every vector here was produced by pycryptodome — the same library the backend
/// uses — via `backend/scripts/gen_crypto_fixtures.py`. That makes these tests an
/// assertion about compatibility with the server, not merely about Dart's
/// internal self-consistency: an AES payload is *encrypted in Python and
/// decrypted in Dart*, so a mismatch in IV length, tag placement or base64
/// alphabet fails here rather than at runtime against a real backend.
///
/// Regenerate with:
///   cd backend && .venv/bin/python scripts/gen_crypto_fixtures.py \
///       ../duiliao_app/assets/fixtures/crypto_vectors.json
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:duiliao_app/core/crypto/duiliao_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

late Map<String, dynamic> vectors;

void main() {
  setUpAll(() {
    final file = File('assets/fixtures/crypto_vectors.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'run backend/scripts/gen_crypto_fixtures.py first',
    );
    vectors = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  group('SHA-256', () {
    test('matches every Python vector', () {
      for (final case_ in vectors['sha256'] as List) {
        final input = case_['input'] as String;
        expect(
          DuiliaoCrypto.sha256Hex(utf8.encode(input)),
          case_['hex'],
          reason: 'sha256 of ${jsonEncode(input)}',
        );
      }
    });

    test('empty string equals the documented constant', () {
      expect(DuiliaoCrypto.sha256Hex(const []), kEmptyBodySha256);
    });

    test('output is lowercase hex with no separators', () {
      final hex = DuiliaoCrypto.sha256Hex(utf8.encode('duiliao'));
      expect(hex.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hex), isTrue);
    });
  });

  group('HMAC-SHA-256', () {
    test('matches every Python vector, including non-ASCII secrets', () {
      for (final case_ in vectors['hmac_sha256'] as List) {
        expect(
          DuiliaoCrypto.hmacSha256Hex(
            case_['secret'] as String,
            case_['message'] as String,
          ),
          case_['hex'],
          reason: 'hmac(${case_['secret']}, ${jsonEncode(case_['message'])})',
        );
      }
    });
  });

  group('canonical signing string', () {
    test('matches Python byte for byte, including the signature', () {
      final secret = vectors['signing_secret'] as String;
      for (final case_ in vectors['signing'] as List) {
        final body = utf8.encode(case_['body_utf8'] as String);
        final canonical = DuiliaoCrypto.canonicalString(
          sessionId: case_['session_id'] as String,
          timestamp: case_['timestamp'] as String,
          nonce: case_['nonce'] as String,
          bodyBytes: body,
        );
        expect(canonical, case_['canonical']);
        expect(
          DuiliaoCrypto.signRequest(
            secret: secret,
            sessionId: case_['session_id'] as String,
            timestamp: case_['timestamp'] as String,
            nonce: case_['nonce'] as String,
            bodyBytes: body,
          ),
          case_['signature'],
        );
      }
    });

    test('is LF separated with four fields and no trailing newline', () {
      final s = DuiliaoCrypto.canonicalString(
        sessionId: 'sid',
        timestamp: '1700000000',
        nonce: 'abcd',
        bodyBytes: const [],
      );
      expect(s.split('\n').length, 4);
      expect(s.endsWith('\n'), isFalse);
      expect(s.contains('\r'), isFalse);
      expect(s, 'sid\n1700000000\nabcd\n$kEmptyBodySha256');
    });
  });

  group('AES-256-GCM', () {
    test('decrypts payloads that Python encrypted', () {
      final crypto = DuiliaoCrypto();
      final key = DuiliaoCrypto.b64Decode(
        (vectors['aes_gcm'] as Map)['key_b64'] as String,
      );
      for (final case_ in (vectors['aes_gcm'] as Map)['cases'] as List) {
        final envelope = EncryptedEnvelope(
          iv: case_['iv'] as String,
          ciphertext: case_['ciphertext'] as String,
        );
        final expected = DuiliaoCrypto.b64Decode(case_['plaintext_b64'] as String);
        expect(
          crypto.aesDecrypt(key, envelope),
          equals(expected),
          reason: 'failed on a ${case_['plaintext_len']}-byte payload',
        );
      }
    });

    test('the tag is appended: blob is exactly 16 bytes longer than plaintext', () {
      for (final case_ in (vectors['aes_gcm'] as Map)['cases'] as List) {
        expect(
          case_['blob_len'] as int,
          (case_['plaintext_len'] as int) + kTagLength,
        );
      }
    });

    test('round trips through Dart', () {
      final crypto = DuiliaoCrypto();
      final key = crypto.generateAesKey();
      final plaintext = utf8.encode('澳门 2026248 特码 28');
      final envelope = crypto.aesEncrypt(key, plaintext);
      expect(crypto.aesDecrypt(key, envelope), equals(plaintext));
    });

    test('Dart output is decryptable by the documented layout', () {
      // Splitting ct||tag by hand and re-joining must be a no-op, which is what
      // the server's aes_decrypt does.
      final crypto = DuiliaoCrypto();
      final key = crypto.generateAesKey();
      final envelope = crypto.aesEncrypt(key, utf8.encode('layout check'));
      final blob = DuiliaoCrypto.b64Decode(envelope.ciphertext);
      final ct = blob.sublist(0, blob.length - kTagLength);
      final tag = blob.sublist(blob.length - kTagLength);
      expect(ct.length + tag.length, blob.length);
      final rejoined = Uint8List.fromList([...ct, ...tag]);
      expect(
        crypto.aesDecrypt(
          key,
          EncryptedEnvelope(
            iv: envelope.iv,
            ciphertext: DuiliaoCrypto.b64Encode(rejoined),
          ),
        ),
        utf8.encode('layout check'),
      );
    });

    test('uses a 12-byte IV', () {
      final crypto = DuiliaoCrypto();
      final envelope = crypto.aesEncrypt(crypto.generateAesKey(), utf8.encode('x'));
      expect(DuiliaoCrypto.b64Decode(envelope.iv).length, kIvLength);
    });

    test('a fresh IV is used for every encryption', () {
      final crypto = DuiliaoCrypto();
      final key = crypto.generateAesKey();
      final ivs = <String>{};
      for (var i = 0; i < 50; i++) {
        ivs.add(crypto.aesEncrypt(key, utf8.encode('same plaintext')).iv);
      }
      expect(ivs.length, 50, reason: 'IV reuse under GCM leaks the key stream');
    });

    test('flipping one ciphertext byte fails authentication', () {
      final crypto = DuiliaoCrypto();
      final key = crypto.generateAesKey();
      final envelope = crypto.aesEncrypt(key, utf8.encode('tamper me'));
      final blob = DuiliaoCrypto.b64Decode(envelope.ciphertext);
      blob[0] ^= 0x01;
      expect(
        () => crypto.aesDecrypt(
          key,
          EncryptedEnvelope(
            iv: envelope.iv,
            ciphertext: DuiliaoCrypto.b64Encode(blob),
          ),
        ),
        throwsA(isA<CryptoFailure>()),
      );
    });

    test('flipping one tag byte fails authentication', () {
      final crypto = DuiliaoCrypto();
      final key = crypto.generateAesKey();
      final envelope = crypto.aesEncrypt(key, utf8.encode('tamper the tag'));
      final blob = DuiliaoCrypto.b64Decode(envelope.ciphertext);
      blob[blob.length - 1] ^= 0x01;
      expect(
        () => crypto.aesDecrypt(
          key,
          EncryptedEnvelope(
            iv: envelope.iv,
            ciphertext: DuiliaoCrypto.b64Encode(blob),
          ),
        ),
        throwsA(isA<CryptoFailure>()),
      );
    });

    test('decrypting with the wrong key fails', () {
      final crypto = DuiliaoCrypto();
      final envelope = crypto.aesEncrypt(crypto.generateAesKey(), utf8.encode('secret'));
      expect(
        () => crypto.aesDecrypt(crypto.generateAesKey(), envelope),
        throwsA(isA<CryptoFailure>()),
      );
    });

    test('a truncated ciphertext is rejected rather than misparsed', () {
      final crypto = DuiliaoCrypto();
      expect(
        () => crypto.aesDecrypt(
          crypto.generateAesKey(),
          EncryptedEnvelope(
            iv: DuiliaoCrypto.b64Encode(Uint8List(kIvLength)),
            ciphertext: DuiliaoCrypto.b64Encode(Uint8List(4)),
          ),
        ),
        throwsA(isA<CryptoFailure>()),
      );
    });

    test('a wrong-length IV is rejected', () {
      final crypto = DuiliaoCrypto();
      expect(
        () => crypto.aesDecrypt(
          crypto.generateAesKey(),
          EncryptedEnvelope(
            iv: DuiliaoCrypto.b64Encode(Uint8List(16)),
            ciphertext: DuiliaoCrypto.b64Encode(Uint8List(32)),
          ),
        ),
        throwsA(isA<CryptoFailure>()),
      );
    });

    test('JSON helpers round trip', () {
      final crypto = DuiliaoCrypto();
      final key = crypto.generateAesKey();
      final payload = {
        'ok': true,
        'period': '2026248',
        'balls': ['18', '26', '09'],
        'nested': {'wuxing': null},
      };
      final envelope = crypto.encryptJson(key, payload);
      expect(crypto.decryptJson(key, envelope), equals(payload));
    });
  });

  group('RSA-OAEP key wrapping', () {
    test('parses the base64 DER SPKI public key', () {
      final spki = (vectors['rsa'] as Map)['public_key_spki_b64'] as String;
      final key = DuiliaoCrypto.parseSpkiPublicKey(spki);
      expect(key.modulus, isNotNull);
      expect(key.exponent, BigInt.from(65537));
      // 2048-bit modulus
      expect(key.modulus!.bitLength, 2048);
    });

    test('rejects PEM, which the endpoint never returns', () {
      expect(
        () => DuiliaoCrypto.parseSpkiPublicKey(
          DuiliaoCrypto.b64Encode(utf8.encode('-----BEGIN PUBLIC KEY-----')),
        ),
        throwsA(isA<CryptoFailure>()),
      );
    });

    test('wrapped key is the modulus size and decrypts back in Dart', () {
      // OAEP is randomised, so the wrapped bytes cannot be compared to Python's.
      // Instead the wrap is undone with the fixture private key, proving the
      // server (which holds that key) would recover the same AES key.
      final rsa = vectors['rsa'] as Map;
      final publicKey =
          DuiliaoCrypto.parseSpkiPublicKey(rsa['public_key_spki_b64'] as String);
      final crypto = DuiliaoCrypto();
      final aesKey = crypto.generateAesKey();

      final wrappedB64 = DuiliaoCrypto.wrapAesKey(publicKey, aesKey);
      final wrapped = DuiliaoCrypto.b64Decode(wrappedB64);
      expect(wrapped.length, rsa['wrapped_byte_length'] as int);

      final privateKey = _parsePkcs1PrivatePem(rsa['private_key_pem'] as String);
      final decoder = OAEPEncoding.withCustomDigest(
        () => SHA256Digest(),
        RSAEngine(),
      )..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
      expect(decoder.process(wrapped), equals(aesKey));
    });

    test('unwraps the sample key Python wrapped, proving OAEP params match', () {
      // This is the decisive check that MGF1 is SHA-256 and the label is empty:
      // a Python-produced OAEP payload only decodes with identical parameters.
      final rsa = vectors['rsa'] as Map;
      final privateKey = _parsePkcs1PrivatePem(rsa['private_key_pem'] as String);
      final decoder = OAEPEncoding.withCustomDigest(
        () => SHA256Digest(),
        RSAEngine(),
      )..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
      final recovered =
          decoder.process(DuiliaoCrypto.b64Decode(rsa['sample_wrapped_key_b64'] as String));
      expect(
        DuiliaoCrypto.b64Encode(recovered),
        rsa['sample_aes_key_b64'],
      );
    });
  });

  group('encoding conventions', () {
    test('base64 is the standard alphabet, not URL-safe', () {
      // Byte 0xfb 0xff produces '+' / '/' under the standard alphabet and
      // '-' / '_' under the URL-safe one.
      final encoded = DuiliaoCrypto.b64Encode([0xfb, 0xff, 0xbf]);
      expect(encoded.contains('-'), isFalse);
      expect(encoded.contains('_'), isFalse);
      expect(encoded, '+/+/');
    });

    test('base64 keeps its padding', () {
      expect(DuiliaoCrypto.b64Encode([0x01]), endsWith('=='));
      expect(DuiliaoCrypto.b64Encode([0x01, 0x02]), endsWith('='));
    });

    test('nonce is 32 lowercase hex characters and never empty', () {
      final crypto = DuiliaoCrypto();
      for (var i = 0; i < 20; i++) {
        final nonce = crypto.randomNonceHex();
        expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(nonce), isTrue);
      }
      // An empty nonce is treated as a replay by the server.
      expect(crypto.randomNonceHex().isNotEmpty, isTrue);
    });

    test('nonces do not repeat', () {
      final crypto = DuiliaoCrypto();
      final seen = <String>{};
      for (var i = 0; i < 500; i++) {
        seen.add(crypto.randomNonceHex());
      }
      expect(seen.length, 500);
    });

    test('generated AES key is 32 bytes', () {
      expect(DuiliaoCrypto().generateAesKey().length, kAesKeyLength);
    });

    test('an injected Random makes output reproducible for tests', () {
      final a = DuiliaoCrypto(random: Random(42)).randomNonceHex();
      final b = DuiliaoCrypto(random: Random(42)).randomNonceHex();
      expect(a, b);
    });
  });

  group('key length validation', () {
    test('rejects a key that is not 16, 24 or 32 bytes', () {
      final crypto = DuiliaoCrypto();
      expect(
        () => crypto.aesEncrypt(Uint8List(20), utf8.encode('x')),
        throwsA(isA<CryptoFailure>()),
      );
    });

    test('accepts all three valid AES key lengths', () {
      final crypto = DuiliaoCrypto();
      for (final length in [16, 24, 32]) {
        final key = crypto.randomBytes(length);
        final envelope = crypto.aesEncrypt(key, utf8.encode('ok'));
        expect(crypto.aesDecrypt(key, envelope), utf8.encode('ok'));
      }
    });
  });
}

/// Parse the PKCS#1 private key PEM the fixture generator emits.
///
/// Test-only: the app never handles a private key.
RSAPrivateKey _parsePkcs1PrivatePem(String pem) {
  final base64Body = pem
      .split('\n')
      .where((line) => !line.startsWith('-----') && line.trim().isNotEmpty)
      .join();
  final der = DuiliaoCrypto.b64Decode(base64Body);
  final seq = ASN1Parser(der).nextObject() as ASN1Sequence;
  // RSAPrivateKey ::= SEQUENCE { version, modulus, publicExponent,
  //   privateExponent, prime1, prime2, ... }
  final modulus = (seq.elements[1] as ASN1Integer).valueAsBigInteger;
  final privateExponent = (seq.elements[3] as ASN1Integer).valueAsBigInteger;
  final p = (seq.elements[4] as ASN1Integer).valueAsBigInteger;
  final q = (seq.elements[5] as ASN1Integer).valueAsBigInteger;
  return RSAPrivateKey(modulus, privateExponent, p, q);
}
