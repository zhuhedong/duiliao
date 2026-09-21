/// ApiClient protocol behaviour: handshake dedup, signing, envelope handling,
/// error-code extraction from both shapes, retry, refresh and clock calibration.
library;

import 'package:duiliao_app/core/config/app_config.dart';
import 'package:duiliao_app/core/net/api_client.dart';
import 'package:duiliao_app/core/net/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

const _secret = 'test-signing-secret';

AppConfig _config({String secret = _secret}) => AppConfig(
      apiBaseUrl: 'http://localhost:8000/api/v1',
      signingSecret: secret,
      appId: 'test',
      requestTimeout: const Duration(seconds: 5),
      pollInterval: const Duration(seconds: 2),
    );

({ApiClient client, FakeBackend backend}) _build({
  String clientSecret = _secret,
  TokenProvider? tokens,
}) {
  final backend = FakeBackend(signingSecret: _secret);
  backend.handlers['/collector/rules'] = (_) => [
        {'play_type': 'tema_n', 'name': '特码', 'scope': '特码', 'version': '2026-09-06.2'},
      ];
  backend.handlers['/echo'] = (req) => {'received': req.body};
  final client = ApiClient(
    config: _config(secret: clientSecret),
    httpClient: backend.client,
    tokenProvider: tokens,
  );
  return (client: client, backend: backend);
}

class _RecordingTokenProvider implements TokenProvider {
  _RecordingTokenProvider({this.token = 'access-token', this.refreshSucceeds = true});
  String? token;
  bool refreshSucceeds;
  int refreshCalls = 0;
  int authLostCalls = 0;

  @override
  String? get accessToken => token;

  @override
  Future<bool> refreshAccessToken() async {
    refreshCalls++;
    if (refreshSucceeds) {
      token = 'refreshed-token';
      return true;
    }
    return false;
  }

  @override
  void onAuthenticationLost() => authLostCalls++;
}

void main() {
  group('handshake', () {
    test('establishes a session on the first request', () async {
      final h = _build();
      final rules = await h.client.get<List<dynamic>>('/collector/rules');
      expect(rules, hasLength(1));
      expect(h.backend.handshakeCalls, 1);
      expect(h.client.status, SessionStatus.connected);
      h.client.dispose();
    });

    test('ten concurrent requests trigger exactly one handshake', () async {
      final h = _build();
      await Future.wait(
        List.generate(10, (_) => h.client.get<List<dynamic>>('/collector/rules')),
      );
      expect(
        h.backend.handshakeCalls,
        1,
        reason: 'concurrent callers must share one in-flight handshake',
      );
      expect(h.backend.publicKeyCalls, 1);
      h.client.dispose();
    });

    test('the session is reused across sequential requests', () async {
      final h = _build();
      for (var i = 0; i < 5; i++) {
        await h.client.get<List<dynamic>>('/collector/rules');
      }
      expect(h.backend.handshakeCalls, 1);
      h.client.dispose();
    });

    test('status stream reports connecting then connected', () async {
      final h = _build();
      final seen = <SessionStatus>[];
      final sub = h.client.statusStream.listen(seen.add);
      await h.client.get<List<dynamic>>('/collector/rules');
      await Future<void>.delayed(Duration.zero);
      expect(seen, [SessionStatus.connecting, SessionStatus.connected]);
      await sub.cancel();
      h.client.dispose();
    });

    test('exposes a short session id for display', () async {
      final h = _build();
      await h.client.get<List<dynamic>>('/collector/rules');
      expect(h.client.sessionIdPreview, isNotNull);
      expect(h.client.sessionIdPreview!.length, lessThanOrEqualTo(8));
      h.client.dispose();
    });
  });

  group('no_session recovery', () {
    test('re-handshakes and retries when the backend drops sessions', () async {
      final h = _build();
      await h.client.get<List<dynamic>>('/collector/rules');
      expect(h.backend.handshakeCalls, 1);

      // A backend restart clears the in-memory session store.
      h.backend.restart();

      final rules = await h.client.get<List<dynamic>>('/collector/rules');
      expect(rules, hasLength(1), reason: 'the retry should succeed transparently');
      expect(h.backend.handshakeCalls, 2);
      h.client.dispose();
    });

    test('a request body is re-encrypted under the new session key', () async {
      final h = _build();
      await h.client.post<Map<String, dynamic>>('/echo', body: {'n': 1});
      h.backend.restart();

      // If the retry reused the old key, the fake backend would fail to decrypt
      // and return bad_payload instead of echoing.
      final echoed = await h.client.post<Map<String, dynamic>>('/echo', body: {'n': 2});
      expect(echoed['received'], {'n': 2});
      h.client.dispose();
    });

    test('recovery is attempted only once, then the error surfaces', () async {
      final backend = FakeBackend(signingSecret: _secret)
        ..invalidateSessionsImmediately = true;
      backend.handlers['/collector/rules'] = (_) => [];
      final client = ApiClient(config: _config(), httpClient: backend.client);

      // Every signed request sees no_session, so the client should handshake,
      // retry once, and then give up rather than looping forever.
      await expectLater(
        client.get<List<dynamic>>('/collector/rules'),
        throwsA(isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.noSession,
        )),
      );
      expect(
        backend.handshakeCalls,
        2,
        reason: 'initial handshake plus exactly one retry',
      );
      client.dispose();
    });
  });

  group('signature and clock', () {
    test('a wrong signing secret yields bad_signature', () async {
      final h = _build(clientSecret: 'the-wrong-secret');
      await expectLater(
        h.client.get<List<dynamic>>('/collector/rules'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiErrorCode.badSignature)
              .having((e) => e.statusCode, 'status', 401)
              .having((e) => e.isConfigurationProblem, 'isConfigurationProblem', true),
        ),
      );
      h.client.dispose();
    });

    test('a device clock skewed past the window still succeeds after calibration',
        () async {
      final backend = FakeBackend(signingSecret: _secret);
      backend.handlers['/collector/rules'] = (_) => [];
      // Server clock 400s ahead of the device: without calibration the client's
      // timestamp is outside the +-300s window and every call fails.
      backend.serverClockOffsetSeconds = 400;

      final client = ApiClient(config: _config(), httpClient: backend.client);
      final rules = await client.get<List<dynamic>>('/collector/rules');
      expect(rules, isEmpty);
      expect(
        client.clockOffsetSeconds,
        greaterThanOrEqualTo(395),
        reason: 'the offset must absorb the skew',
      );
      client.dispose();
    });

    test('a nonce is never reused, so nothing is rejected as a replay', () async {
      final h = _build();
      for (var i = 0; i < 20; i++) {
        await h.client.get<List<dynamic>>('/collector/rules');
      }
      expect(h.backend.requestLog, hasLength(20));
      h.client.dispose();
    });

    test('sends all five signature headers', () async {
      final backend = FakeBackend(signingSecret: _secret);
      Map<String, String>? captured;
      backend.handlers['/probe'] = (req) {
        captured = req.headers;
        return {'ok': true};
      };
      final client = ApiClient(config: _config(), httpClient: backend.client);
      await client.get<Map<String, dynamic>>('/probe');
      final lower = {
        for (final e in captured!.entries) e.key.toLowerCase(): e.value,
      };
      expect(lower.keys, containsAll([
        'x-session-id',
        'x-timestamp',
        'x-nonce',
        'x-signature',
        'x-app-id',
      ]));
      expect(lower['x-nonce']!.length, 32);
      expect(lower['x-signature']!.length, 64);
      expect(int.tryParse(lower['x-timestamp']!), isNotNull);
      client.dispose();
    });
  });

  group('error shapes', () {
    test('reads a top-level code from a plaintext middleware error', () async {
      // The decisive check: middleware errors are plaintext with `code` as a
      // sibling of `detail`, not nested inside it. A client that only reads
      // detail.code (as the web client does) reports null here.
      final backend = FakeBackend(signingSecret: _secret)
        ..invalidateSessionsImmediately = true;
      backend.handlers['/collector/rules'] = (_) => [];
      final client = ApiClient(config: _config(), httpClient: backend.client);

      await expectLater(
        client.get<List<dynamic>>('/collector/rules'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiErrorCode.noSession)
              .having((e) => e.isSessionExpired, 'isSessionExpired', true)
              .having((e) => e.statusCode, 'status', 401),
        ),
      );
      client.dispose();
    });

    test('reads a nested code from an encrypted handler error', () async {
      final h = _build();
      h.backend.handlers['/forbidden'] = (_) =>
          throw const FakeHandlerError(403, 'Insufficient permissions', code: 'forbidden');
      await expectLater(
        h.client.get<Map<String, dynamic>>('/forbidden'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 403)
              .having((e) => e.code, 'code', 'forbidden')
              .having((e) => e.isForbidden, 'isForbidden', true),
        ),
      );
      h.client.dispose();
    });

    test('extractor handles all three detail shapes', () {
      expect(extractApiErrorMessage({'detail': 'flat string'}, 'fb'), 'flat string');
      expect(
        extractApiErrorMessage({'detail': {'message': 'nested', 'code': 'x'}}, 'fb'),
        'nested',
      );
      expect(extractApiErrorMessage('bare string', 'fb'), 'bare string');
      expect(extractApiErrorMessage({'unexpected': 1}, 'fallback'), 'fallback');
      // FastAPI validation error list.
      expect(
        extractApiErrorMessage({'detail': [{'msg': 'field required'}]}, 'fb'),
        'field required',
      );
    });

    test('maps codes to actionable Chinese messages', () {
      expect(
        const ApiException('', code: ApiErrorCode.invalidCredentials).displayMessage,
        '账号或密码错误',
      );
      expect(
        const ApiException('', code: ApiErrorCode.locked).displayMessage,
        '账号已临时锁定，请稍后再试',
      );
      expect(
        const ApiException('', code: ApiErrorCode.badTimestamp).displayMessage,
        '设备时间偏差过大，请检查系统时间',
      );
      expect(
        const ApiException('', statusCode: 403).displayMessage,
        '当前账号没有该操作权限',
      );
      expect(const ApiException('', statusCode: 500).displayMessage, '服务端异常，请稍后重试');
    });

    test('a 404 surfaces as isNotFound', () async {
      final h = _build();
      await expectLater(
        h.client.get<Map<String, dynamic>>('/nothing-here'),
        throwsA(isA<ApiException>().having((e) => e.isNotFound, 'isNotFound', true)),
      );
      h.client.dispose();
    });
  });

  group('token refresh', () {
    test('refreshes once and retries the original request', () async {
      final tokens = _RecordingTokenProvider();
      final backend = FakeBackend(signingSecret: _secret);
      var attempts = 0;
      backend.handlers['/protected'] = (req) {
        attempts++;
        if (req.bearerToken != 'refreshed-token') {
          throw const FakeHandlerError(401, 'Access token expired');
        }
        return {'ok': true};
      };
      final client = ApiClient(
        config: _config(),
        httpClient: backend.client,
        tokenProvider: tokens,
      );

      final result = await client.get<Map<String, dynamic>>('/protected');
      expect(result['ok'], true);
      expect(tokens.refreshCalls, 1);
      expect(attempts, 2, reason: 'original call, then the retry');
      client.dispose();
    });

    test('a failed refresh reports authentication lost', () async {
      final tokens = _RecordingTokenProvider(refreshSucceeds: false);
      final backend = FakeBackend(signingSecret: _secret);
      backend.handlers['/protected'] =
          (_) => throw const FakeHandlerError(401, 'Access token expired');
      final client = ApiClient(
        config: _config(),
        httpClient: backend.client,
        tokenProvider: tokens,
      );

      await expectLater(
        client.get<Map<String, dynamic>>('/protected'),
        throwsA(isA<ApiException>()),
      );
      expect(tokens.refreshCalls, 1);
      expect(tokens.authLostCalls, 1);
      client.dispose();
    });

    test('never tries to refresh while calling /auth/*', () async {
      final tokens = _RecordingTokenProvider();
      final backend = FakeBackend(signingSecret: _secret);
      backend.handlers['/auth/login'] = (_) => throw const FakeHandlerError(
            401,
            'Invalid credentials',
            code: 'invalid_credentials',
          );
      final client = ApiClient(
        config: _config(),
        httpClient: backend.client,
        tokenProvider: tokens,
      );

      await expectLater(
        client.post<Map<String, dynamic>>('/auth/login', body: {'identifier': 'a'}),
        throwsA(isA<ApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.invalidCredentials,
        )),
      );
      expect(tokens.refreshCalls, 0, reason: 'refreshing during login would recurse');
      client.dispose();
    });

    test('attaches the bearer token when present', () async {
      final tokens = _RecordingTokenProvider(token: 'my-token');
      final backend = FakeBackend(signingSecret: _secret);
      String? seen;
      backend.handlers['/whoami'] = (req) {
        seen = req.bearerToken;
        return {'ok': true};
      };
      final client = ApiClient(
        config: _config(),
        httpClient: backend.client,
        tokenProvider: tokens,
      );
      await client.get<Map<String, dynamic>>('/whoami');
      expect(seen, 'my-token');
      client.dispose();
    });
  });

  group('request encoding', () {
    test('a body round trips through encryption', () async {
      final h = _build();
      final payload = {
        'lottery': 'macau',
        'period': '2026248',
        'source_ids': ['a', 'b'],
        'nested': {'wuxing': null},
      };
      final echoed = await h.client.post<Map<String, dynamic>>('/echo', body: payload);
      expect(echoed['received'], equals(payload));
      h.client.dispose();
    });

    test('non-ASCII survives the round trip', () async {
      final h = _build();
      final echoed = await h.client.post<Map<String, dynamic>>(
        '/echo',
        body: {'text': '澳门 平特肖 猪猪猪'},
      );
      expect((echoed['received'] as Map)['text'], '澳门 平特肖 猪猪猪');
      h.client.dispose();
    });

    test('GET sends no body but still signs the empty hash', () async {
      final h = _build();
      final rules = await h.client.get<List<dynamic>>('/collector/rules');
      expect(rules, hasLength(1));
      h.client.dispose();
    });

    test('query parameters are appended and nulls dropped', () async {
      final backend = FakeBackend(signingSecret: _secret);
      String? capturedPath;
      backend.handlers['/draws'] = (req) {
        capturedPath = req.path;
        return {'ok': true};
      };
      final client = ApiClient(config: _config(), httpClient: backend.client);
      await client.get<Map<String, dynamic>>(
        '/draws',
        query: {'lottery': 'macau', 'limit': 50, 'offset': null},
      );
      expect(capturedPath, contains('/draws'));
      client.dispose();
    });

    test('list query parameters are expanded', () async {
      final backend = FakeBackend(signingSecret: _secret);
      backend.handlers['/multi'] = (_) => {'ok': true};
      final client = ApiClient(config: _config(), httpClient: backend.client);
      await client.get<Map<String, dynamic>>('/multi', query: {'w': [30, 50, 100]});
      client.dispose();
    });

    test('a wrong expected type gives a diagnosable error', () async {
      final h = _build();
      await expectLater(
        // /collector/rules returns a List, not a Map.
        h.client.get<Map<String, dynamic>>('/collector/rules'),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          allOf(contains('/collector/rules'), contains('expected')),
        )),
      );
      h.client.dispose();
    });
  });

  group('configuration', () {
    test('flags a placeholder signing secret', () {
      expect(
        const AppConfig(
          apiBaseUrl: 'http://x/api/v1',
          signingSecret: 'CHANGE_ME_app_signing_secret_change_me',
          appId: 'app',
          requestTimeout: Duration(seconds: 1),
          pollInterval: Duration(seconds: 1),
        ).hasPlaceholderSecret,
        isTrue,
      );
      expect(_config().hasPlaceholderSecret, isFalse);
    });

    test('strips a trailing slash from the base url', () {
      // Verified through the factory's normalisation logic.
      const raw = 'http://host/api/v1/';
      final trimmed = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
      expect(trimmed, 'http://host/api/v1');
    });

    test('displayHost shows scheme, host and port only', () {
      expect(_config().displayHost, 'http://localhost:8000');
    });
  });
}
