/// The encrypted HTTP client every repository goes through.
///
/// Mirrors `frontend/src/lib/api.ts`, with three deliberate differences that the
/// backend's behaviour requires:
///
/// 1. **Error codes are read from both shapes.** See [extractApiErrorCode]. The
///    web client only reads `detail.code`, so it never detects the middleware's
///    top-level `no_session` and falls through to a pointless token refresh.
/// 2. **The clock is calibrated against the server.** The handshake returns
///    `serverTime`; signing with an uncorrected device clock that is off by more
///    than 300s fails every request with `bad_timestamp`, which on a phone is a
///    real possibility.
/// 3. **Concurrent handshakes are deduplicated with a shared future**, so ten
///    parallel requests on a cold start perform one handshake rather than ten.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../crypto/duiliao_crypto.dart';
import 'api_exception.dart';

/// Connection state of the encrypted session, for display in the UI.
enum SessionStatus { disconnected, connecting, connected }

/// An established AES session.
class _Session {
  _Session({required this.id, required this.key, required this.expiresAt});
  final String id;
  final Uint8List key;
  final DateTime expiresAt;

  /// Treated as expired slightly early so a request is not sent with a key the
  /// server is about to drop.
  bool get isExpired => DateTime.now().isAfter(
        expiresAt.subtract(const Duration(seconds: 30)),
      );
}

/// Supplies and refreshes the bearer token. Implemented by the auth layer;
/// injected to keep [ApiClient] independent of it.
abstract class TokenProvider {
  String? get accessToken;

  /// Attempt a refresh. Returns true when a new access token is available.
  Future<bool> refreshAccessToken();

  /// Called when refreshing is no longer possible and the user must sign in.
  void onAuthenticationLost();
}

/// A [TokenProvider] that never authenticates, for anonymous use and tests.
class NullTokenProvider implements TokenProvider {
  const NullTokenProvider();
  @override
  String? get accessToken => null;
  @override
  Future<bool> refreshAccessToken() async => false;
  @override
  void onAuthenticationLost() {}
}

class ApiClient {
  ApiClient({
    required this.config,
    http.Client? httpClient,
    DuiliaoCrypto? crypto,
    TokenProvider? tokenProvider,
  })  : _http = httpClient ?? http.Client(),
        _crypto = crypto ?? DuiliaoCrypto(),
        _tokens = tokenProvider ?? const NullTokenProvider();

  final AppConfig config;
  final http.Client _http;
  final DuiliaoCrypto _crypto;
  TokenProvider _tokens;

  _Session? _session;
  Future<void>? _handshakeInFlight;

  /// Seconds to add to the device clock to match the server's.
  int _clockOffsetSeconds = 0;

  final _statusController = StreamController<SessionStatus>.broadcast();
  SessionStatus _status = SessionStatus.disconnected;

  /// Number of handshakes performed. Exposed for tests and the debug screen.
  int handshakeCount = 0;

  // ------------------------------------------------------------------ //
  // Public surface
  // ------------------------------------------------------------------ //
  Stream<SessionStatus> get statusStream => _statusController.stream;
  SessionStatus get status => _status;
  int get clockOffsetSeconds => _clockOffsetSeconds;

  /// First 8 characters of the session id, for the debug screen.
  String? get sessionIdPreview {
    final id = _session?.id;
    if (id == null) return null;
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  // ignore: use_setters_to_change_properties
  void attachTokenProvider(TokenProvider provider) => _tokens = provider;

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      request<T>('GET', path, query: query);

  Future<T> post<T>(String path, {Object? body, Map<String, dynamic>? query}) =>
      request<T>('POST', path, body: body ?? const {}, query: query);

  Future<T> put<T>(String path, {Object? body, Map<String, dynamic>? query}) =>
      request<T>('PUT', path, body: body ?? const {}, query: query);

  Future<T> patch<T>(String path, {Object? body, Map<String, dynamic>? query}) =>
      request<T>('PATCH', path, body: body ?? const {}, query: query);

  Future<T> delete<T>(String path, {Map<String, dynamic>? query}) =>
      request<T>('DELETE', path, query: query);

  /// Perform an encrypted, signed request.
  ///
  /// [body] of `null` sends no body at all, matching the web client: the
  /// signature still covers the SHA-256 of the empty string.
  Future<T> request<T>(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool authenticated = true,
    bool isRetry = false,
  }) async {
    await _ensureSession();
    final session = _session;
    if (session == null) {
      throw const ApiException('encryption session unavailable');
    }

    // Encryption happens here rather than at the call site so that a retry after
    // a re-handshake automatically re-encrypts under the new session key.
    Uint8List rawBody = Uint8List(0);
    final headers = <String, String>{};
    if (body != null) {
      final envelope = _crypto.encryptJson(session.key, body);
      rawBody = Uint8List.fromList(utf8.encode(jsonEncode(envelope.toJson())));
      headers['Content-Type'] = 'application/json';
    }
    headers.addAll(_signatureHeaders(session.id, rawBody));

    final token = _tokens.accessToken;
    if (authenticated && token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final uri = _buildUri(path, query);
    final http.Response response;
    try {
      response = await _send(method, uri, headers, body == null ? null : rawBody);
    } on TimeoutException catch (e) {
      throw NetworkException('request timed out: $uri', cause: e);
    } on SocketException catch (e) {
      throw NetworkException('could not reach $uri', cause: e);
    } on http.ClientException catch (e) {
      throw NetworkException(e.message, cause: e);
    }

    final payload = _decodeBody(response, session.key);

    if (response.statusCode >= 400) {
      final code = extractApiErrorCode(payload);

      // The server's session store is in-memory, so a restart invalidates every
      // client's session. Re-handshake and retry once, transparently.
      if (response.statusCode == 401 && code == ApiErrorCode.noSession && !isRetry) {
        _clearSession();
        return request<T>(
          method,
          path,
          body: body,
          query: query,
          authenticated: authenticated,
          isRetry: true,
        );
      }

      // Expired access token: refresh once, then retry. Skipped for /auth/*
      // so a failing refresh cannot recurse.
      if (response.statusCode == 401 &&
          authenticated &&
          !isRetry &&
          !path.startsWith('/auth/')) {
        if (await _tokens.refreshAccessToken()) {
          return request<T>(
            method,
            path,
            body: body,
            query: query,
            authenticated: authenticated,
            isRetry: true,
          );
        }
        _tokens.onAuthenticationLost();
      }

      throw ApiException(
        extractApiErrorMessage(payload, response.reasonPhrase ?? 'HTTP ${response.statusCode}'),
        statusCode: response.statusCode,
        code: code,
        payload: payload,
      );
    }

    return _cast<T>(payload, path);
  }

  void dispose() {
    _statusController.close();
    _http.close();
  }

  // ------------------------------------------------------------------ //
  // Session handling
  // ------------------------------------------------------------------ //
  /// Establish a session if needed, collapsing concurrent callers onto one
  /// handshake.
  Future<void> _ensureSession() {
    final existing = _session;
    if (existing != null && !existing.isExpired) return Future.value();
    // Every caller awaits the same future, so N parallel cold requests trigger
    // exactly one handshake.
    return _handshakeInFlight ??= _handshake().whenComplete(() {
      _handshakeInFlight = null;
    });
  }

  Future<void> _handshake() async {
    _setStatus(SessionStatus.connecting);
    try {
      // Both handshake endpoints are exempt from encryption and signing, so they
      // are plain JSON calls.
      final keyInfo = await _plainGet('/crypto/public-key');
      final publicKeyB64 = keyInfo['publicKey'];
      if (publicKeyB64 is! String || publicKeyB64.isEmpty) {
        throw const ApiException('handshake: public key missing from response');
      }
      final publicKey = DuiliaoCrypto.parseSpkiPublicKey(publicKeyB64);
      final aesKey = _crypto.generateAesKey();
      final wrapped = DuiliaoCrypto.wrapAesKey(publicKey, aesKey);

      final handshake = await _plainPost('/crypto/handshake', {'encryptedKey': wrapped});
      final sessionId = handshake['sessionId'];
      if (sessionId is! String || sessionId.isEmpty) {
        throw const ApiException('handshake: sessionId missing from response');
      }
      final ttl = _asInt(handshake['expiresIn']) ?? 3600;

      // Calibrate before the first signed request, not after a failure.
      final serverTime = _asInt(handshake['serverTime']) ?? _asInt(keyInfo['serverTime']);
      if (serverTime != null && serverTime > 0) {
        _clockOffsetSeconds =
            serverTime - (DateTime.now().millisecondsSinceEpoch ~/ 1000);
      }

      _session = _Session(
        id: sessionId,
        key: aesKey,
        expiresAt: DateTime.now().add(Duration(seconds: ttl)),
      );
      handshakeCount++;
      _setStatus(SessionStatus.connected);
    } catch (e) {
      _setStatus(SessionStatus.disconnected);
      if (e is ApiException || e is NetworkException) rethrow;
      if (e is CryptoFailure) {
        throw ApiException('handshake failed: ${e.message}');
      }
      throw ApiException('handshake failed: $e');
    }
  }

  void _clearSession() {
    _session = null;
    _setStatus(SessionStatus.disconnected);
  }

  /// Drop the session so the next request re-handshakes. Used after a backend
  /// configuration change or from the debug screen.
  void resetSession() => _clearSession();

  void _setStatus(SessionStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  // ------------------------------------------------------------------ //
  // Signing
  // ------------------------------------------------------------------ //
  Map<String, String> _signatureHeaders(String sessionId, Uint8List rawBody) {
    final timestamp =
        ((DateTime.now().millisecondsSinceEpoch ~/ 1000) + _clockOffsetSeconds)
            .toString();
    final nonce = _crypto.randomNonceHex();
    return {
      'X-Session-Id': sessionId,
      'X-Timestamp': timestamp,
      'X-Nonce': nonce,
      'X-Signature': DuiliaoCrypto.signRequest(
        secret: config.signingSecret,
        sessionId: sessionId,
        timestamp: timestamp,
        nonce: nonce,
        bodyBytes: rawBody,
      ),
      'X-App-Id': config.appId,
    };
  }

  // ------------------------------------------------------------------ //
  // Transport helpers
  // ------------------------------------------------------------------ //
  Uri _buildUri(String path, Map<String, dynamic>? query) {
    final base = Uri.parse('${config.apiBaseUrl}$path');
    if (query == null || query.isEmpty) return base;
    // Null-valued params are dropped rather than sent as "null"; everything else
    // is stringified because Uri only accepts String/Iterable<String>.
    final params = <String, dynamic>{};
    query.forEach((key, value) {
      if (value == null) return;
      params[key] = value is Iterable
          ? value.map((v) => v.toString()).toList()
          : value.toString();
    });
    return base.replace(queryParameters: {...base.queryParameters, ...params});
  }

  Future<http.Response> _send(
    String method,
    Uri uri,
    Map<String, String> headers,
    Uint8List? body,
  ) {
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    return _http
        .send(request)
        .then(http.Response.fromStream)
        .timeout(config.requestTimeout);
  }

  Future<Map<String, dynamic>> _plainGet(String path) async {
    final uri = Uri.parse('${config.apiBaseUrl}$path');
    try {
      final res = await _http.get(uri).timeout(config.requestTimeout);
      return _decodePlainJson(res, uri);
    } on TimeoutException catch (e) {
      throw NetworkException('request timed out: $uri', cause: e);
    } on SocketException catch (e) {
      throw NetworkException('could not reach $uri', cause: e);
    } on http.ClientException catch (e) {
      throw NetworkException(e.message, cause: e);
    }
  }

  Future<Map<String, dynamic>> _plainPost(String path, Object body) async {
    final uri = Uri.parse('${config.apiBaseUrl}$path');
    try {
      final res = await _http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(config.requestTimeout);
      return _decodePlainJson(res, uri);
    } on TimeoutException catch (e) {
      throw NetworkException('request timed out: $uri', cause: e);
    } on SocketException catch (e) {
      throw NetworkException('could not reach $uri', cause: e);
    } on http.ClientException catch (e) {
      throw NetworkException(e.message, cause: e);
    }
  }

  Map<String, dynamic> _decodePlainJson(http.Response res, Uri uri) {
    Object? decoded;
    try {
      decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    } on FormatException {
      decoded = res.body;
    }
    if (res.statusCode >= 400) {
      throw ApiException(
        extractApiErrorMessage(decoded, 'HTTP ${res.statusCode} from $uri'),
        statusCode: res.statusCode,
        code: extractApiErrorCode(decoded),
        payload: decoded,
      );
    }
    if (decoded is Map<String, dynamic>) return decoded;
    throw ApiException('unexpected response shape from $uri');
  }

  /// Decode a response body, decrypting when the server marks it encrypted.
  ///
  /// Both shapes must be handled: middleware-level errors come back as plaintext
  /// with no `X-Encrypted` header, while handler responses — including handler
  /// errors — are encrypted.
  Object? _decodeBody(http.Response response, Uint8List key) {
    if (response.bodyBytes.isEmpty) return null;
    final isEncrypted = response.headers['x-encrypted'] == '1';
    if (!isEncrypted) {
      try {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        return utf8.decode(response.bodyBytes, allowMalformed: true);
      }
    }
    try {
      final envelope = EncryptedEnvelope.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
      return _crypto.decryptJson(key, envelope);
    } on CryptoFailure catch (e) {
      throw ApiException('could not decrypt response: ${e.message}');
    } catch (e) {
      throw ApiException('malformed encrypted response: $e');
    }
  }

  /// Cast a decoded payload to the expected type with a message that names the
  /// path, so a contract change is diagnosable from a log line.
  T _cast<T>(Object? payload, String path) {
    if (payload is T) return payload;
    if (null is T && payload == null) return payload as T;
    throw ApiException(
      'unexpected response type from $path: expected $T, got ${payload.runtimeType}',
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
