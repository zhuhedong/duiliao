import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/providers.dart';
import 'core/storage/cache_store.dart';
import 'features/notifications/background_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationDocumentsDirectory();
  Hive.init(directory.path);
  CacheStore cache = HiveCacheStore();
  try {
    await cache.init();
  } catch (_) {
    // A corrupt local store must not prevent sign-in. This run simply has no
    // durable offline cache.
    cache = MemoryCacheStore();
  }
  try {
    await initializeBackgroundNotifications();
  } catch (_) {
    // Background execution is optional on platforms/builds that do not expose
    // the scheduler; foreground polling remains available.
  }
  runApp(
    ProviderScope(
      overrides: [cacheStoreProvider.overrideWithValue(cache)],
      child: const DuiliaoApp(),
    ),
  );
}
