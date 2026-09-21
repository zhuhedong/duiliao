/// Riverpod wiring for the whole app.
///
/// Composition happens once here so features depend on abstractions rather than
/// constructing clients themselves, and so tests can override any layer.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/collector_repository.dart';
import '../domain/lottery.dart';
import 'config/app_config.dart';
import 'net/api_client.dart';
import 'storage/cache_store.dart';
import 'storage/secure_store.dart';

// --------------------------------------------------------------------------- //
// Infrastructure
// --------------------------------------------------------------------------- //
/// Build configuration. Overridden in tests.
final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

/// Secure storage for the refresh token. Overridden in tests.
final secureStoreProvider = Provider<SecureStore>(
  (ref) => FlutterSecureStore(),
);

/// On-disk cache. Initialised in `main()` before the app runs; a
/// [MemoryCacheStore] is substituted if Hive fails to open so the app still
/// works, just without offline reads.
final cacheStoreProvider = Provider<CacheStore>(
  (ref) => throw UnimplementedError('cacheStoreProvider must be overridden in main()'),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(config: ref.watch(appConfigProvider));
  ref.onDispose(client.dispose);
  return client;
});

/// Encrypted-session connection state, for the status indicator.
final sessionStatusProvider = StreamProvider<SessionStatus>((ref) {
  final client = ref.watch(apiClientProvider);
  return client.statusStream;
});

// --------------------------------------------------------------------------- //
// Repositories
// --------------------------------------------------------------------------- //
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    client: ref.watch(apiClientProvider),
    store: ref.watch(secureStoreProvider),
  ),
);

final collectorRepositoryProvider = Provider<CollectorRepository>(
  (ref) => CollectorRepository(
    client: ref.watch(apiClientProvider),
    cache: ref.watch(cacheStoreProvider),
  ),
);

// --------------------------------------------------------------------------- //
// UI preferences
// --------------------------------------------------------------------------- //
/// The lottery currently being browsed. Shared across tabs so switching tabs
/// does not silently change which lottery the operator is looking at.
final selectedLotteryProvider =
    NotifierProvider<SelectedLottery, Lottery>(SelectedLottery.new);

class SelectedLottery extends Notifier<Lottery> {
  @override
  Lottery build() => Lottery.macau;
  void set(Lottery lottery) => state = lottery;
}

/// Play type used by the ratings and consensus screens.
final selectedPlayTypeProvider =
    NotifierProvider<SelectedPlayType, String>(SelectedPlayType.new);

class SelectedPlayType extends Notifier<String> {
  @override
  String build() => 'pingte_xiao';
  void set(String playType) => state = playType;
}

/// Display preferences persisted only in memory for now; the profile screen
/// exposes them and they reset on a cold start.
@immutable
class DisplayPreferences {
  const DisplayPreferences({
    this.themeMode = ThemeModePreference.system,
    this.textScale = 1.0,
    this.biometricEnabled = false,
  });

  final ThemeModePreference themeMode;

  /// Multiplier applied to the app's text scale, 0.9–1.4.
  final double textScale;

  final bool biometricEnabled;

  DisplayPreferences copyWith({
    ThemeModePreference? themeMode,
    double? textScale,
    bool? biometricEnabled,
  }) =>
      DisplayPreferences(
        themeMode: themeMode ?? this.themeMode,
        textScale: textScale ?? this.textScale,
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      );
}

enum ThemeModePreference { system, light, dark }

final displayPreferencesProvider =
    NotifierProvider<DisplayPreferencesController, DisplayPreferences>(
  DisplayPreferencesController.new,
);

class DisplayPreferencesController extends Notifier<DisplayPreferences> {
  @override
  DisplayPreferences build() => const DisplayPreferences();

  Future<void> hydrate() async {
    final store = ref.read(secureStoreProvider);
    final theme = await store.read(SecureKeys.themeMode);
    final scale = double.tryParse(await store.read(SecureKeys.textScale) ?? '');
    final biometric = (await store.read(SecureKeys.biometricEnabled)) == '1';
    final mode = ThemeModePreference.values.firstWhere(
      (value) => value.name == theme,
      orElse: () => ThemeModePreference.system,
    );
    state = DisplayPreferences(
      themeMode: mode,
      textScale: (scale ?? 1).clamp(0.9, 1.4),
      biometricEnabled: biometric,
    );
  }

  void setThemeMode(ThemeModePreference mode) {
    state = state.copyWith(themeMode: mode);
    ref.read(secureStoreProvider).write(SecureKeys.themeMode, mode.name);
  }

  /// Clamped so an extreme value cannot make the UI unusable.
  void setTextScale(double scale) {
    final value = scale.clamp(0.9, 1.4);
    state = state.copyWith(textScale: value);
    ref.read(secureStoreProvider).write(SecureKeys.textScale, value.toString());
  }

  void setBiometricEnabled(bool enabled) {
    state = state.copyWith(biometricEnabled: enabled);
    ref.read(secureStoreProvider).write(
          SecureKeys.biometricEnabled,
          enabled ? '1' : '0',
        );
  }
}
