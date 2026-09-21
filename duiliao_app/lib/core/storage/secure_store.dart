/// Persistence for credentials and small preferences.
///
/// The refresh token is the only long-lived secret on the device, so it goes in
/// the platform keystore (Keychain on iOS, EncryptedSharedPreferences on
/// Android). The access token is deliberately **never** persisted — it lives in
/// memory for minutes and is cheap to re-obtain, so writing it to disk would add
/// exposure for no benefit.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keys used in secure storage.
abstract final class SecureKeys {
  static const String refreshToken = 'duiliao.refresh_token';
  static const String biometricEnabled = 'duiliao.biometric_enabled';
  static const String themeMode = 'duiliao.theme_mode';
  static const String textScale = 'duiliao.text_scale';
  static const String deviceId = 'duiliao.device_id';
  static const String lastIdentifier = 'duiliao.last_identifier';
}

/// Thin wrapper so the auth layer can be tested without a platform channel.
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> clearCredentials();
}

class FlutterSecureStore implements SecureStore {
  FlutterSecureStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                // Requires the device to have been unlocked at least once since
                // boot, and excludes the value from iCloud/iTunes backups so a
                // restored backup cannot resurrect a session.
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  /// Remove the refresh token while keeping device-level preferences.
  ///
  /// The device id survives so the web console's session list keeps showing one
  /// entry per physical device rather than a new one after every sign-out, and
  /// the biometric preference survives so the user does not have to re-enable it.
  @override
  Future<void> clearCredentials() async {
    await _storage.delete(key: SecureKeys.refreshToken);
  }
}

/// In-memory implementation for tests.
class InMemorySecureStore implements SecureStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<void> clearCredentials() async => values.remove(SecureKeys.refreshToken);
}
