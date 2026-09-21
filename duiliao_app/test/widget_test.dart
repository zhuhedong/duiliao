import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:duiliao_app/app.dart';
import 'package:duiliao_app/core/providers.dart';
import 'package:duiliao_app/core/storage/cache_store.dart';
import 'package:duiliao_app/core/storage/secure_store.dart';

void main() {
  testWidgets('cold start shows the login gate without a stored session', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
          secureStoreProvider.overrideWithValue(InMemorySecureStore()),
        ],
        child: const DuiliaoApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('账号由管理员在 Web 后台创建'), findsOneWidget);
  });
}
