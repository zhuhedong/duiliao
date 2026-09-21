/// An in-process stand-in for the Duiliao backend, for ApiClient tests.
///
/// It reproduces the parts of the real server's behaviour that the client has to
/// cope with, using the same crypto primitives:
///
/// * The handshake pair, returning a base64 DER SPKI key and `serverTime`.
/// * Signature, timestamp-window and replay verification.
/// * Encrypted responses carrying `X-Encrypted: 1`.
/// * The two *different* error shapes — plaintext with a top-level `code` for
///   middleware errors, encrypted with a nested `detail.code` for handler errors.
///
/// Because it is driven by the same [DuiliaoCrypto] the app uses, these tests
/// verify the client's *protocol logic* (retry, dedup, calibration). Compatibility
/// with the real Python implementation is what `crypto_interop_test.dart` and
/// `backend/scripts/verify_dart_crypto.py` establish.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:duiliao_app/core/crypto/duiliao_crypto.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

class FakeBackend {
  FakeBackend({
    required this.signingSecret,
    this.timestampTolerance = 300,
    this.enforceSignature = true,
  }) {
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 1024, 12),
          _seededRandom(),
        ),
      );
    final pair = generator.generateKeyPair();
    _publicKey = pair.publicKey;
    _privateKey = pair.privateKey;
  }

  final String signingSecret;
  final int timestampTolerance;
  final bool enforceSignature;

  /// When true, a session is dropped the moment it is created, so every signed
  /// request sees `no_session`. Models a server that cannot hold sessions at all.
  bool invalidateSessionsImmediately = false;

  late final RSAPublicKey _publicKey;
  late final RSAPrivateKey _privateKey;
  final _crypto = DuiliaoCrypto();

  /// Active sessions: id -> AES key.
  final Map<String, Uint8List> sessions = {};
  final Set<String> _usedNonces = {};

  int handshakeCalls = 0;
  int publicKeyCalls = 0;
  final List<String> requestLog = [];

  /// Offset applied to this server's reported clock, to simulate device skew.
  int serverClockOffsetSeconds = 0;

  /// Drops every existing session, as a backend restart does.
  void restart() => sessions.clear();

  /// Per-path handlers. Return a JSON-encodable body, or throw [FakeHandlerError]
  /// to produce an encrypted handler-style error.
  final Map<String, Object? Function(FakeRequest req)> handlers = {};

  int get _now => (DateTime.now().millisecondsSinceEpoch ~/ 1000) + serverClockOffsetSeconds;

  /// The [http.Client] to hand to `ApiClient`.
  http.Client get client => _MockClient(this);

  Future<http.Response> handle(http.BaseRequest request) async {
    final path = request.url.path;
    final bodyBytes = request is http.Request
        ? Uint8List.fromList(request.bodyBytes)
        : Uint8List(0);

    if (path.endsWith('/crypto/public-key')) {
      publicKeyCalls++;
      return _plain(200, {
        'keyId': 'fake-key',
        'algorithm': 'RSA-OAEP-256',
        'publicKey': DuiliaoCrypto.b64Encode(_encodeSpki(_publicKey)),
        'serverTime': _now,
      });
    }

    if (path.endsWith('/crypto/handshake')) {
      handshakeCalls++;
      final payload = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
      final decoder = OAEPEncoding.withCustomDigest(() => SHA256Digest(), RSAEngine())
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(_privateKey));
      final aesKey = decoder.process(
        DuiliaoCrypto.b64Decode(payload['encryptedKey'] as String),
      );
      final sessionId = 'sess-${sessions.length}-${DateTime.now().microsecondsSinceEpoch}';
      sessions[sessionId] = Uint8List.fromList(aesKey);
      if (invalidateSessionsImmediately) sessions.remove(sessionId);
      return _plain(200, {
        'sessionId': sessionId,
        'expiresIn': 3600,
        'serverTime': _now,
      });
    }

    // --- middleware: session, signature, timestamp, replay ---------------- //
    final sessionId = _header(request, 'x-session-id');
    if (sessionId == null || !sessions.containsKey(sessionId)) {
      // Plaintext, with the code as a SIBLING of detail.
      return _plain(401, {
        'detail': 'Missing or expired encryption session',
        'code': 'no_session',
      });
    }
    final aesKey = sessions[sessionId]!;

    if (enforceSignature) {
      final timestamp = _header(request, 'x-timestamp') ?? '';
      final nonce = _header(request, 'x-nonce') ?? '';
      final signature = _header(request, 'x-signature') ?? '';

      final ts = int.tryParse(timestamp);
      if (ts == null || (_now - ts).abs() > timestampTolerance) {
        return _plain(401, {
          'detail': 'Stale or invalid timestamp',
          'code': 'bad_timestamp',
        });
      }
      final expected = DuiliaoCrypto.signRequest(
        secret: signingSecret,
        sessionId: sessionId,
        timestamp: timestamp,
        nonce: nonce,
        bodyBytes: bodyBytes,
      );
      if (expected != signature) {
        return _plain(401, {
          'detail': 'Invalid request signature',
          'code': 'bad_signature',
        });
      }
      if (nonce.isEmpty || !_usedNonces.add('$sessionId:$nonce')) {
        return _plain(401, {'detail': 'Replay detected', 'code': 'replay'});
      }
    }

    // --- decrypt the request body ---------------------------------------- //
    Object? decodedBody;
    if (bodyBytes.isNotEmpty) {
      try {
        final envelope = EncryptedEnvelope.fromJson(
          jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>,
        );
        decodedBody = _crypto.decryptJson(aesKey, envelope);
      } catch (_) {
        return _plain(400, {'detail': 'Malformed encrypted payload', 'code': 'bad_payload'});
      }
    }

    requestLog.add('${request.method} $path');

    // --- dispatch --------------------------------------------------------- //
    final key = handlers.keys.firstWhere(
      (candidate) => path.endsWith(candidate),
      orElse: () => '',
    );
    if (key.isEmpty) {
      return _encrypted(aesKey, 404, {'detail': {'message': 'Not Found', 'code': 'not_found'}});
    }
    try {
      final result = handlers[key]!(
        FakeRequest(method: request.method, path: path, body: decodedBody, headers: request.headers),
      );
      return _encrypted(aesKey, 200, result);
    } on FakeHandlerError catch (e) {
      // Handler errors are ENCRYPTED with the code NESTED inside detail.
      return _encrypted(aesKey, e.statusCode, {
        'detail': {'message': e.message, 'code': e.code},
      });
    }
  }

  http.Response _plain(int status, Object? body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  http.Response _encrypted(Uint8List key, int status, Object? body) {
    final envelope = _crypto.encryptJson(key, body);
    return http.Response(
      jsonEncode(envelope.toJson()),
      status,
      headers: {'content-type': 'application/json', 'x-encrypted': '1'},
    );
  }

  static String? _header(http.BaseRequest request, String name) {
    for (final entry in request.headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  /// Wrap a raw RSA public key in an X.509 SubjectPublicKeyInfo structure, which
  /// is the format the real endpoint serves.
  static Uint8List _encodeSpki(RSAPublicKey key) {
    final modulus = _derInteger(key.modulus!);
    final exponent = _derInteger(key.exponent!);
    final rsaSequence = _derSequence([...modulus, ...exponent]);
    // AlgorithmIdentifier for rsaEncryption (1.2.840.113549.1.1.1) with NULL params.
    const algorithm = <int>[
      0x30, 0x0d,
      0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
      0x05, 0x00,
    ];
    final bitString = <int>[0x03, ..._derLength(rsaSequence.length + 1), 0x00, ...rsaSequence];
    return Uint8List.fromList(_derSequence([...algorithm, ...bitString]));
  }

  static List<int> _derSequence(List<int> contents) =>
      [0x30, ..._derLength(contents.length), ...contents];

  static List<int> _derLength(int length) {
    if (length < 0x80) return [length];
    final bytes = <int>[];
    var remaining = length;
    while (remaining > 0) {
      bytes.insert(0, remaining & 0xff);
      remaining >>= 8;
    }
    return [0x80 | bytes.length, ...bytes];
  }

  static List<int> _derInteger(BigInt value) {
    var hex = value.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    var bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    // DER INTEGER is signed, so a leading high bit needs a zero pad.
    if (bytes.isNotEmpty && bytes.first & 0x80 != 0) bytes = [0x00, ...bytes];
    return [0x02, ..._derLength(bytes.length), ...bytes];
  }

  static SecureRandom _seededRandom() {
    final random = FortunaRandom();
    // Deterministic seed: key generation here only needs to be valid, not secret,
    // and a fixed seed keeps the tests fast and reproducible.
    random.seed(KeyParameter(Uint8List.fromList(List<int>.generate(32, (i) => i + 1))));
    return random;
  }
}

class FakeRequest {
  const FakeRequest({
    required this.method,
    required this.path,
    required this.body,
    required this.headers,
  });
  final String method;
  final String path;
  final Object? body;
  final Map<String, String> headers;

  String? get bearerToken {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'authorization') {
        final value = entry.value;
        if (value.startsWith('Bearer ')) return value.substring(7);
      }
    }
    return null;
  }
}

/// Throw from a handler to produce an encrypted, handler-style error response.
class FakeHandlerError implements Exception {
  const FakeHandlerError(this.statusCode, this.message, {this.code});
  final int statusCode;
  final String message;
  final String? code;
}

class _MockClient extends http.BaseClient {
  _MockClient(this._backend);
  final FakeBackend _backend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Buffer the body so the fake can read it, as a real server would.
    final materialised = request is http.Request
        ? request
        : (http.Request(request.method, request.url)..headers.addAll(request.headers));
    final response = await _backend.handle(materialised);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}
