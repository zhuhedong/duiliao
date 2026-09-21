/// Authentication lifecycle: login, silent restore, rotation, lockout, sign-out.
library;

import 'package:duiliao_app/core/config/app_config.dart';
import 'package:duiliao_app/core/net/api_client.dart';
import 'package:duiliao_app/core/providers.dart';
import 'package:duiliao_app/core/storage/secure_store.dart';
import 'package:duiliao_app/data/auth_repository.dart';
import 'package:duiliao_app/domain/models/user.dart';
import 'package:duiliao_app/features/auth/auth_controller.dart';
import 'package:duiliao_app/features/auth/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

const _secret = 'test-signing-secret';

AppConfig _config() => AppConfig(
      apiBaseUrl: 'http://localhost:8000/api/v1',
      signingSecret: _secret,
      appId: 'test',
      requestTimeout: const Duration(seconds: 5),
      pollInterval: const Duration(seconds: 2),
    );

/// A fake backend with working auth routes.
class _AuthHarness {
  _AuthHarness() {
    backend = FakeBackend(signingSecret: _secret);
    store = InMemorySecureStore();

    backend.handlers['/auth/login'] = (req) {
      final body = req.body as Map<String, dynamic>? ?? const {};
      loginCalls++;
      lastDevice = body['device'] as Map<String, dynamic>?;
      if (lockedOut) {
        throw const FakeHandlerError(
          423,
          'Account temporarily locked. Try again later.',
          code: 'locked',
        );
      }
      if (body['password'] != password) {
        failedAttempts++;
        // The server locks the account after five failures.
        if (failedAttempts >= 5) lockedOut = true;
        throw const FakeHandlerError(
          401,
          'Invalid credentials',
          code: 'invalid_credentials',
        );
      }
      failedAttempts = 0;
      refreshTokens.add('refresh-1');
      return {
        'access_token': 'access-1',
        'refresh_token': 'refresh-1',
        'token_type': 'bearer',
        'expires_in': 900,
        'user': _userJson(role),
      };
    };

    backend.handlers['/auth/refresh'] = (req) {
      final body = req.body as Map<String, dynamic>? ?? const {};
      final supplied = body['refresh_token'] as String?;
      refreshCalls++;
      // The real backend rotates: the supplied token is revoked here.
      if (supplied == null || !refreshTokens.contains(supplied)) {
        throw const FakeHandlerError(401, 'Invalid refresh token', code: 'revoked');
      }
      refreshTokens.remove(supplied);
      final next = 'refresh-${refreshCalls + 1}';
      refreshTokens.add(next);
      return {
        'access_token': 'access-${refreshCalls + 1}',
        'refresh_token': next,
        'token_type': 'bearer',
        'expires_in': 900,
        // Deliberately no user object, matching the real endpoint.
      };
    };

    backend.handlers['/users/me'] = (_) => _userJson(role);
    backend.handlers['/auth/logout'] = (req) {
      final body = req.body as Map<String, dynamic>? ?? const {};
      if (body['all_devices'] == true) {
        refreshTokens.clear();
        allDevicesLogouts++;
      } else {
        refreshTokens.remove(body['refresh_token']);
      }
      return null;
    };
    backend.handlers['/users/me/sessions'] = (_) => [
          {
            'id': 'sess-web',
            'device_name': 'Chrome on macOS',
            'platform': 'web',
            'current': true,
          },
          {
            'id': 'sess-phone',
            'device_name': 'Pixel 8',
            'platform': 'android',
            'app_version': '1.0.0',
            'current': true,
          },
        ];

    client = ApiClient(config: _config(), httpClient: backend.client);
    repository = AuthRepository(client: client, store: store);
    // AuthNotifier is a Riverpod notifier, so it has to be driven through a
    // container; overriding the repository keeps the fake backend in play while
    // exercising the real provider wiring.
    container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(_config()),
        secureStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(client),
        authRepositoryProvider.overrideWithValue(repository),
      ],
    );
    controller = container.read(authStateProvider.notifier);
  }

  late final FakeBackend backend;
  late final InMemorySecureStore store;
  late final ApiClient client;
  late final AuthRepository repository;
  late final ProviderContainer container;
  late final AuthNotifier controller;

  /// Current auth state as the UI would observe it.
  AuthState get state => container.read(authStateProvider);

  /// The only password the fake accepts.
  static const String password = 'GoodPass123';
  String role = 'staff';
  final Set<String> refreshTokens = {};
  int loginCalls = 0;
  int refreshCalls = 0;
  int allDevicesLogouts = 0;
  int failedAttempts = 0;
  bool lockedOut = false;
  Map<String, dynamic>? lastDevice;

  static Map<String, dynamic> _userJson(String role) => {
        'id': 'user-1',
        'username': 'operator',
        'email': 'operator@duiliaoapp.com',
        'email_verified': true,
        'phone_verified': false,
        'display_name': '运营小王',
        'locale': 'zh',
        'timezone': 'Asia/Shanghai',
        'status': 'active',
        'role': role,
        'registration_source': 'android',
        'mfa_enabled': false,
        'created_at': '2026-01-01T00:00:00',
      };

  void dispose() {
    container.dispose();
    client.dispose();
  }
}

void main() {
  group('login', () {
    test('a correct password authenticates and exposes the role', () async {
      final h = _AuthHarness();
      final ok = await h.controller.login(
        identifier: 'operator',
        password: 'GoodPass123',
      );
      expect(ok, isTrue);
      expect(h.state.phase, AuthPhase.authenticated);
      expect(h.state.user?.displayName, '运营小王');
      expect(h.state.role, UserRole.staff);
      expect(h.state.canOperate, isTrue);
      expect(h.controller.accessToken, 'access-1');
      h.dispose();
    });

    test('the refresh token is persisted but the access token is not', () async {
      final h = _AuthHarness();
      await h.controller.login(identifier: 'operator', password: 'GoodPass123');
      expect(h.store.values[SecureKeys.refreshToken], 'refresh-1');
      // The access token must never be written to disk.
      expect(
        h.store.values.values.contains('access-1'),
        isFalse,
        reason: 'the access token must stay in memory only',
      );
      h.dispose();
    });

    test('device metadata is sent so the console can identify this handset', () async {
      final h = _AuthHarness();
      await h.controller.login(identifier: 'operator', password: 'GoodPass123');
      // The backend's DeviceInfo schema uses camelCase, unlike the rest of the
      // API, so a snake_case key here would silently produce an unnamed session.
      expect(h.lastDevice, isNotNull);
      expect(
        h.lastDevice!.keys.toSet(),
        {'deviceId', 'deviceName', 'platform', 'appVersion'},
      );
      h.dispose();
    });

    test('a wrong password reports a readable error and stays signed out', () async {
      final h = _AuthHarness();
      final ok = await h.controller.login(identifier: 'operator', password: 'wrong');
      expect(ok, isFalse);
      expect(h.state.phase, AuthPhase.unauthenticated);
      expect(h.state.errorMessage, '账号或密码错误');
      expect(h.controller.accessToken, isNull);
      h.dispose();
    });

    test('five failures surface the account lockout', () async {
      final h = _AuthHarness();
      for (var i = 0; i < 5; i++) {
        await h.controller.login(identifier: 'operator', password: 'wrong');
      }
      // The sixth attempt, even with the right password, is refused with 423.
      final ok = await h.controller.login(
        identifier: 'operator',
        password: 'GoodPass123',
      );
      expect(ok, isFalse);
      expect(h.state.errorMessage, '账号已临时锁定，请稍后再试');
      h.dispose();
    });

    test('the identifier is trimmed and remembered for prefill', () async {
      final h = _AuthHarness();
      await h.controller.login(identifier: '  operator  ', password: 'GoodPass123');
      expect(await h.repository.readLastIdentifier(), 'operator');
      h.dispose();
    });

    test('a plain user does not get operator permissions', () async {
      final h = _AuthHarness()..role = 'user';
      await h.controller.login(identifier: 'operator', password: 'GoodPass123');
      expect(h.state.role, UserRole.user);
      expect(
        h.state.canOperate,
        isFalse,
        reason: 'the collection tab must stay hidden for role=user',
      );
      h.dispose();
    });

    test('submitting sets and clears the in-flight flag', () async {
      final h = _AuthHarness();
      final future = h.controller.login(identifier: 'operator', password: 'GoodPass123');
      // The flag is set synchronously before awaiting.
      expect(h.state.isSubmitting, isTrue);
      await future;
      expect(h.state.isSubmitting, isFalse);
      h.dispose();
    });
  });

  group('silent restore', () {
    test('a stored refresh token signs the user back in', () async {
      final h = _AuthHarness();
      await h.controller.login(identifier: 'operator', password: 'GoodPass123');
      final storedToken = h.store.values[SecureKeys.refreshToken];
      h.dispose();

      // A fresh controller, as after a process restart.
      final h2 = _AuthHarness();
      h2.refreshTokens.add(storedToken!);
      await h2.store.write(SecureKeys.refreshToken, storedToken);

      await h2.controller.restore();
      expect(h2.controller.state.phase, AuthPhase.authenticated);
      // /auth/refresh returns no user, so the profile must be fetched separately.
      expect(h2.controller.state.user?.displayName, '运营小王');
      expect(h2.loginCalls, 0, reason: 'restore must not require credentials');
      h2.dispose();
    });

    test('no stored token goes straight to the login screen', () async {
      final h = _AuthHarness();
      await h.controller.restore();
      expect(h.state.phase, AuthPhase.unauthenticated);
      expect(h.state.errorMessage, isNull);
      h.dispose();
    });

    test('an invalid stored token is discarded', () async {
      final h = _AuthHarness();
      await h.store.write(SecureKeys.refreshToken, 'not-a-real-token');
      await h.controller.restore();
      expect(h.state.phase, AuthPhase.unauthenticated);
      expect(
        h.store.values[SecureKeys.refreshToken],
        isNull,
        reason: 'a dead token must not be retried forever',
      );
      h.dispose();
    });

    test('restore can land in the locked state when biometrics are on', () async {
      final h = _AuthHarness();
      h.refreshTokens.add('refresh-stored');
      await h.store.write(SecureKeys.refreshToken, 'refresh-stored');
      await h.controller.restore(requireBiometric: true);
      expect(h.state.phase, AuthPhase.locked);
      expect(h.state.isLocked, isTrue);
      // Content must stay hidden until unlocked.
      expect(h.state.isAuthenticated, isFalse);

      h.controller.completeUnlock();
      expect(h.state.phase, AuthPhase.authenticated);
      h.dispose();
    });
  });

  group('token rotation', () {
    test('each refresh stores the newly issued token', () async {
      final h = _AuthHarness();
      h.refreshTokens.add('refresh-seed');
      await h.store.write(SecureKeys.refreshToken, 'refresh-seed');

      final tokens = await h.repository.refresh('refresh-seed');
      expect(tokens.refreshToken, isNot('refresh-seed'));
      expect(
        h.store.values[SecureKeys.refreshToken],
        tokens.refreshToken,
        reason: 'the rotated token must be persisted or the session is lost',
      );
      h.dispose();
    });

    test('reusing a rotated token is rejected', () async {
      final h = _AuthHarness();
      h.refreshTokens.add('refresh-seed');
      await h.repository.refresh('refresh-seed');
      // The old value was revoked server-side by the rotation.
      await expectLater(
        h.repository.refresh('refresh-seed'),
        throwsA(anything),
      );
      h.dispose();
    });

    test('concurrent refreshes collapse into one request', () async {
      final h = _AuthHarness();
      h.refreshTokens.add('refresh-seed');
      await h.store.write(SecureKeys.refreshToken, 'refresh-seed');

      final results = await Future.wait([
        h.controller.refreshAccessToken(),
        h.controller.refreshAccessToken(),
        h.controller.refreshAccessToken(),
      ]);
      expect(results, everyElement(isTrue));
      expect(
        h.refreshCalls,
        1,
        reason: 'the refresh token is single-use, so parallel rotations would '
            'invalidate each other',
      );
      h.dispose();
    });

    test('a failed refresh reports false without wiping a usable token', () async {
      final h = _AuthHarness();
      await h.store.write(SecureKeys.refreshToken, 'unknown-token');
      expect(await h.controller.refreshAccessToken(), isFalse);
      h.dispose();
    });

    test('losing authentication clears the token and the state', () async {
      final h = _AuthHarness();
      await h.controller.login(identifier: 'operator', password: 'GoodPass123');
      h.controller.onAuthenticationLost();
      expect(h.state.phase, AuthPhase.unauthenticated);
      expect(h.state.errorMessage, '登录已过期，请重新登录');
      expect(h.controller.accessToken, isNull);
      h.dispose();
    });
  });

  group('sign out', () {
    test('signing out clears the credential and the state', () async {
      final h = _AuthHarness();
      await h.controller.login(identifier: 'operator', password: 'GoodPass123');
      await h.controller.logout();
      expect(h.state.phase, AuthPhase.unauthenticated);
      expect(h.controller.accessToken, isNull);
      expect(h.store.values[SecureKeys.refreshToken], isNull);
      h.dispose();
    });

    test('signing out of all devices revokes every session', () async {
      final h = _AuthHarness();
      await h.controller.login(identifier: 'operator', password: 'GoodPass123');
      await h.controller.logout(allDevices: true);
      expect(h.allDevicesLogouts, 1);
      expect(h.refreshTokens, isEmpty);
      h.dispose();
    });

    test('a failing logout call still clears the local credential', () async {
      final h = _AuthHarness();
      await h.controller.login(identifier: 'operator', password: 'GoodPass123');
      h.backend.handlers['/auth/logout'] =
          (_) => throw const FakeHandlerError(500, 'boom');
      await h.controller.logout();
      expect(
        h.store.values[SecureKeys.refreshToken],
        isNull,
        reason: 'a server error must not trap the user in a signed-in state',
      );
      expect(h.state.phase, AuthPhase.unauthenticated);
      h.dispose();
    });
  });

  group('profile and sessions', () {
    test('device sessions parse and this device is identified by name', () async {
      final h = _AuthHarness();
      await h.controller.login(identifier: 'operator', password: 'GoodPass123');
      final sessions = await h.repository.listSessions();
      expect(sessions, hasLength(2));

      final phone = sessions.firstWhere((s) => s.platform == 'android');
      expect(
        phone.isThisDevice(thisDeviceName: 'Pixel 8', thisAppVersion: '1.0.0'),
        isTrue,
      );
      final web = sessions.firstWhere((s) => s.platform == 'web');
      expect(web.isThisDevice(thisDeviceName: 'Pixel 8'), isFalse);
      // Every live session reports current=true, so it cannot mark this device.
      expect(sessions.every((s) => s.current), isTrue);
      h.dispose();
    });

    test('a profile edit sends only the changed fields', () async {
      final h = _AuthHarness();
      await h.controller.login(identifier: 'operator', password: 'GoodPass123');
      Map<String, dynamic>? received;
      h.backend.handlers['/users/me'] = (req) {
        if (req.method == 'PATCH') {
          received = req.body as Map<String, dynamic>?;
        }
        return _AuthHarness._userJson('staff');
      };
      await h.repository.updateProfile(displayName: '新的昵称');
      expect(
        received,
        {'display_name': '新的昵称'},
        reason: 'sending an explicit null would clear the other fields',
      );
      h.dispose();
    });

    test('reloading the user replaces the cached profile', () async {
      final h = _AuthHarness();
      await h.controller.login(identifier: 'operator', password: 'GoodPass123');
      h.backend.handlers['/users/me'] = (_) => {
            ..._AuthHarness._userJson('admin'),
            'display_name': '改名后',
          };
      await h.controller.reloadUser();
      expect(h.state.user?.displayName, '改名后');
      expect(h.state.role, UserRole.admin);
      h.dispose();
    });

    test('a password change posts both values', () async {
      final h = _AuthHarness();
      await h.controller.login(identifier: 'operator', password: 'GoodPass123');
      Map<String, dynamic>? received;
      h.backend.handlers['/users/me/password'] = (req) {
        received = req.body as Map<String, dynamic>?;
        return null;
      };
      await h.repository.changePassword(
        currentPassword: 'GoodPass123',
        newPassword: 'NewPass456',
      );
      expect(received, {
        'current_password': 'GoodPass123',
        'new_password': 'NewPass456',
      });
      h.dispose();
    });
  });

  group('state helpers', () {
    test('an unauthenticated state grants nothing', () {
      const state = AuthState(phase: AuthPhase.unauthenticated);
      expect(state.canOperate, isFalse);
      expect(state.role, isNull);
      expect(state.isAuthenticated, isFalse);
    });

    test('restoring grants nothing, so no privileged tab flashes', () {
      const state = AuthState();
      expect(state.phase, AuthPhase.restoring);
      expect(state.canOperate, isFalse);
    });

    test('clearError removes the message', () async {
      final h = _AuthHarness();
      await h.controller.login(identifier: 'x', password: 'wrong');
      expect(h.state.errorMessage, isNotNull);
      h.controller.clearError();
      expect(h.state.errorMessage, isNull);
      h.dispose();
    });

    test('updateUser replaces the profile without a request', () {
      final h = _AuthHarness();
      h.controller.updateUser(AppUser.fromJson(_AuthHarness._userJson('admin')));
      expect(h.state.user?.role, UserRole.admin);
      h.dispose();
    });
  });
}
