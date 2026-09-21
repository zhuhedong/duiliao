/// OS-scheduled notification polling.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/config/app_config.dart';
import '../../core/net/api_client.dart';
import '../../core/storage/cache_store.dart';
import '../../core/storage/secure_store.dart';
import '../../data/auth_repository.dart';
import '../../data/collector_repository.dart';
import 'notification_service.dart';

const _taskName = 'duiliao_event_poll';

@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (task != _taskName) return true;
    try {
      await _pollInBackground();
      return true;
    } catch (_) {
      return false;
    } finally {
      // Workmanager's periodic API is Android-only in 0.5.x. On iOS the
      // equivalent is a chain of BGProcessingTask requests; scheduling the
      // next one after each invocation keeps the same best-effort cadence.
      if (Platform.isIOS) {
        try {
          await Workmanager().registerOneOffTask(
            _taskName,
            _taskName,
            initialDelay: const Duration(minutes: 15),
            constraints: Constraints(networkType: NetworkType.connected),
          );
        } catch (_) {
          // The OS may reject a request while the app is terminating. The next
          // foreground launch registers it again.
        }
      }
    }
  });
}

/// Register the minimum Android periodic interval. iOS may run the same task
/// later or skip it entirely; opening the app always performs an immediate poll.
Future<void> initializeBackgroundNotifications() async {
  await Workmanager().initialize(
    backgroundCallbackDispatcher,
    isInDebugMode: false,
  );
  if (Platform.isIOS) {
    await Workmanager().registerOneOffTask(
      _taskName,
      _taskName,
      initialDelay: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } else {
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }
}

class _BackgroundTokenProvider implements TokenProvider {
  _BackgroundTokenProvider(this.repository);
  final AuthRepository repository;
  String? token;
  @override
  String? get accessToken => token;
  @override
  Future<bool> refreshAccessToken() async {
    final stored = await repository.readRefreshToken();
    if (stored == null || stored.isEmpty) return false;
    try {
      final result = await repository.refresh(stored);
      token = result.accessToken;
      return true;
    } catch (_) {
      return false;
    }
  }
  @override
  void onAuthenticationLost() {}
}

Future<void> _pollInBackground() async {
  final directory = await getApplicationDocumentsDirectory();
  Hive.init(directory.path);
  final cache = HiveCacheStore();
  await cache.init();
  final secure = const FlutterSecureStorage();
  final store = _SecureStoreAdapter(secure);
  final client = ApiClient(config: AppConfig.fromEnvironment());
  final auth = AuthRepository(client: client, store: store);
  final tokens = _BackgroundTokenProvider(auth);
  client.attachTokenProvider(tokens);
  if (!await tokens.refreshAccessToken()) {
    client.dispose();
    return;
  }
  final repo = CollectorRepository(client: client, cache: cache);
  final cursor = (await cache.read(CacheKeys.eventCursor, ttl: const Duration(days: 3650)))?.value as String?;
  final page = await repo.events(since: cursor, limit: 50);
  final presenter = LocalNotificationPresenter();
  final stored = await cache.read(CacheKeys.messages, ttl: const Duration(days: 3650));
  final messages = <AppMessage>[];
  if (stored?.value is List) {
    for (final raw in stored!.value as List) {
      final message = AppMessage.fromJson(raw);
      if (message != null) messages.add(message);
    }
  }
  final known = messages.map((message) => message.event.dedupeKey).toSet();
  final fresh = page.events.where((event) => !known.contains(event.dedupeKey)).toList();
  for (final event in fresh) {
    await presenter.show(event, event.dedupeKey.hashCode & 0x7fffffff);
  }
  if (fresh.isNotEmpty) {
    await cache.write(
      CacheKeys.messages,
      [
        ...fresh.map((event) => AppMessage(event: event, read: false).toJson()),
        ...messages.map((message) => message.toJson()),
      ].take(kMaxStoredMessages).toList(),
    );
  }
  if (page.nextCursor != null) await cache.write(CacheKeys.eventCursor, page.nextCursor);
  client.dispose();
}

class _SecureStoreAdapter implements SecureStore {
  const _SecureStoreAdapter(this.storage);
  final FlutterSecureStorage storage;
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) => storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
  @override
  Future<void> clearCredentials() => storage.delete(key: SecureKeys.refreshToken);
}
