/// Authentication against `/auth/*` and `/users/me`.
///
/// There is deliberately **no registration path**. Accounts are created by an
/// administrator in the web console; this is an internal operations app, and
/// exposing sign-up would let anyone who obtains the APK create an account.
library;

import 'dart:async';

import '../core/net/api_client.dart';
import '../core/net/api_exception.dart';
import '../core/storage/secure_store.dart';
import '../domain/models/user.dart';

/// Device metadata sent with a login so the web console's session list can
/// identify this handset.
///
/// The backend's `DeviceInfo` schema uses **camelCase** keys, unlike the rest of
/// the API which is snake_case.
class DeviceDescriptor {
  const DeviceDescriptor({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.appVersion,
  });

  /// Stable per-installation id, so repeated sign-ins reuse one session row.
  final String deviceId;

  /// Human-readable model, e.g. `Pixel 8`.
  final String deviceName;

  /// `android` or `ios`.
  final String platform;

  final String appVersion;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'platform': platform,
        'appVersion': appVersion,
      };
}

/// Outcome of a sign-in attempt.
class LoginResult {
  const LoginResult({required this.tokens, required this.user});
  final AuthTokens tokens;
  final AppUser user;
}

class AuthRepository {
  AuthRepository({required this._client, required this._store});

  final ApiClient _client;
  final SecureStore _store;

  /// Sign in with an email, phone or username in a single [identifier] field.
  Future<LoginResult> login({
    required String identifier,
    required String password,
    DeviceDescriptor? device,
  }) async {
    final payload = <String, dynamic>{
      'identifier': identifier.trim(),
      'password': password,
      if (device != null) 'device': device.toJson(),
    };
    final response = await _client.post<Map<String, dynamic>>(
      '/auth/login',
      body: payload,
      // No bearer token exists yet, and sending a stale one could trigger a
      // pointless refresh attempt.
    );
    final tokens = AuthTokens.fromJson(response);
    final user = AppUser.fromJson(
      response['user'] is Map<String, dynamic>
          ? response['user'] as Map<String, dynamic>
          : const {},
    );
    await persistRefreshToken(tokens.refreshToken);
    // Remembered so the login form can prefill; not a secret, but kept in the
    // same store to avoid a second storage dependency.
    await _store.write(SecureKeys.lastIdentifier, identifier.trim());
    return LoginResult(tokens: tokens, user: user);
  }

  /// Exchange a refresh token for a new pair.
  ///
  /// The backend **rotates** refresh tokens: the supplied one is revoked as part
  /// of this call, so the new one must be persisted before the old is discarded
  /// or the session is lost.
  Future<AuthTokens> refresh(String refreshToken) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/auth/refresh',
      body: {'refresh_token': refreshToken},
    );
    final tokens = AuthTokens.fromJson(response);
    if (!tokens.isValid) {
      throw const ApiException('refresh response missing tokens');
    }
    await persistRefreshToken(tokens.refreshToken);
    return tokens;
  }

  /// The signed-in user. `/auth/refresh` does not return a user object, so this
  /// is what repopulates the profile after a silent sign-in.
  Future<AppUser> me() async {
    final response = await _client.get<Map<String, dynamic>>('/users/me');
    return AppUser.fromJson(response);
  }

  Future<AppUser> updateProfile({
    String? displayName,
    String? avatarUrl,
    String? locale,
    String? timezone,
  }) async {
    // Only send what changed: the backend applies a partial update, and sending
    // an explicit null would clear the field.
    final body = <String, dynamic>{
      'display_name': ?displayName,
      'avatar_url': ?avatarUrl,
      'locale': ?locale,
      'timezone': ?timezone,
    };
    final response =
        await _client.patch<Map<String, dynamic>>('/users/me', body: body);
    return AppUser.fromJson(response);
  }

  /// Change the password. Returns without a body on success.
  ///
  /// Note the backend does **not** revoke other sessions on a password change,
  /// so the caller should offer to sign out other devices explicitly.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.post<Object?>(
      '/users/me/password',
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }

  Future<List<DeviceSession>> listSessions() async {
    final response = await _client.get<List<dynamic>>('/users/me/sessions');
    return response
        .whereType<Map<String, dynamic>>()
        .map(DeviceSession.fromJson)
        .toList(growable: false);
  }

  /// Revoke one session by its id.
  Future<void> revokeSession(String sessionId) async {
    await _client.delete<Object?>('/users/me/sessions/$sessionId');
  }

  /// Sign out. [allDevices] revokes every session for the account.
  Future<void> logout({String? refreshToken, bool allDevices = false}) async {
    try {
      await _client.post<Object?>(
        '/auth/logout',
        body: {
          'refresh_token': ?refreshToken,
          'all_devices': allDevices,
        },
      );
    } on ApiException {
      // A failed revoke must not trap the user in a signed-in state; the local
      // credential is cleared regardless.
    } on NetworkException {
      // Same reasoning offline.
    } finally {
      await _store.clearCredentials();
    }
  }

  // ------------------------------------------------------------------ //
  // Credential storage
  // ------------------------------------------------------------------ //
  Future<String?> readRefreshToken() => _store.read(SecureKeys.refreshToken);

  Future<void> persistRefreshToken(String token) =>
      _store.write(SecureKeys.refreshToken, token);

  Future<void> clearCredentials() => _store.clearCredentials();

  Future<String?> readLastIdentifier() => _store.read(SecureKeys.lastIdentifier);
}
