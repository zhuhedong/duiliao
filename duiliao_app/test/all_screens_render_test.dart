import 'package:duiliao_app/domain/lottery.dart';
import 'package:duiliao_app/features/ai/ai_screen.dart';
import 'package:duiliao_app/features/auth/login_screen.dart';
import 'package:duiliao_app/features/collect/collect_screen.dart';
import 'package:duiliao_app/features/comparison/comparison_screen.dart';
import 'package:duiliao_app/features/consensus/consensus_screen.dart';
import 'package:duiliao_app/features/design/jump_code_assistant_screen.dart';
import 'package:duiliao_app/features/design/ops_design_screens.dart';
import 'package:duiliao_app/features/design/records_screens.dart';
import 'package:duiliao_app/features/draws/draw_detail_screen.dart';
import 'package:duiliao_app/features/draws/draws_screen.dart';
import 'package:duiliao_app/features/home/home_screen.dart';
import 'package:duiliao_app/features/notifications/messages_screen.dart';
import 'package:duiliao_app/features/numbers/numbers_screen.dart';
import 'package:duiliao_app/features/profile/profile_screen.dart';
import 'package:duiliao_app/features/ratings/ratings_screen.dart';
import 'package:duiliao_app/features/ratings/source_detail_screen.dart';
import 'package:duiliao_app/features/rules/rules_screen.dart';
import 'package:duiliao_app/features/shell/operator_shell.dart';
import 'package:duiliao_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child, {ThemeData? theme}) {
    return ProviderScope(
      key: UniqueKey(),
      child: MaterialApp(
        key: UniqueKey(),
        theme: theme ?? DuiliaoTheme.dark(),
        home: child,
      ),
    );
  }

  Future<void> pumpAndScroll(
    WidgetTester tester,
    Widget screen, {
    Size logicalSize = const Size(393, 852),
  }) async {
    tester.view.physicalSize = Size(
      logicalSize.width * 3,
      logicalSize.height * 3,
    );
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(screen));
    await tester.pump(const Duration(milliseconds: 100));

    final listViews = find.byType(ListView);
    if (listViews.evaluate().isNotEmpty) {
      await tester.drag(listViews.first, const Offset(0, -350));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.drag(listViews.first, const Offset(0, -350));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.drag(listViews.first, const Offset(0, 700));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('1. LoginScreen & LockScreen (393x852 + 360x780)', (tester) async {
    await pumpAndScroll(tester, const LoginScreen());
    await pumpAndScroll(
      tester,
      const LoginScreen(),
      logicalSize: const Size(360, 780),
    );
    await pumpAndScroll(
      tester,
      LockScreen(onUnlock: () async => false),
      logicalSize: const Size(360, 780),
    );
  });

  testWidgets('2. OperatorShell & HomeScreen (dashboard.html)', (tester) async {
    await pumpAndScroll(tester, const OperatorShell());
    await pumpAndScroll(
      tester,
      const HomeScreen(),
      logicalSize: const Size(360, 780),
    );
  });

  Future<void> pumpModal(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('3. DrawsScreen (draws.html + filter sheet)', (tester) async {
    await pumpAndScroll(tester, const DrawsScreen());
    await pumpAndScroll(
      tester,
      const DrawsScreen(),
      logicalSize: const Size(360, 780),
    );
    final filterBtn = find.byTooltip('期号筛选');
    if (filterBtn.evaluate().isNotEmpty) {
      await tester.tap(filterBtn.first);
      await pumpModal(tester);
      final clearBtn = find.text('清除');
      if (clearBtn.evaluate().isNotEmpty) {
        await tester.tap(clearBtn.first);
        await pumpModal(tester);
      }
    }
  });

  testWidgets('4. DrawDetailScreen (draw-detail.html)', (tester) async {
    await pumpAndScroll(
      tester,
      const DrawDetailScreen(lottery: Lottery.macau, period: '2026276'),
    );
    await pumpAndScroll(
      tester,
      const DrawDetailScreen(lottery: Lottery.macau, period: '2026276'),
      logicalSize: const Size(360, 780),
    );
  });

  testWidgets('5. ComparisonScreen (consensus.html + evidence sheet)',
      (tester) async {
    await pumpAndScroll(tester, const ComparisonScreen());
    await pumpAndScroll(
      tester,
      const ComparisonScreen(),
      logicalSize: const Size(360, 780),
    );
  });

  testWidgets('6. ConsensusBoardScreen (consensus-board.html - all 3 tabs)',
      (tester) async {
    await pumpAndScroll(
      tester,
      const ConsensusBoardScreen(),
      logicalSize: const Size(360, 780),
    );
    for (final tab in ['玩法组共识', '入库与核验', '候选排行榜']) {
      final f = find.text(tab);
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first);
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    final period276 = find.text('第 2026276 期');
    if (period276.evaluate().isNotEmpty) {
      await tester.tap(period276.first);
      await tester.pump(const Duration(milliseconds: 50));
    }
    final auditTab = find.text('入库与核验');
    if (auditTab.evaluate().isNotEmpty) {
      await tester.tap(auditTab.first);
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('7. NumbersScreen (numbers.html + encyclopedia sheet)',
      (tester) async {
    await pumpAndScroll(
      tester,
      const NumbersScreen(),
      logicalSize: const Size(360, 780),
    );
    final encBtn = find.byTooltip('属性总表');
    if (encBtn.evaluate().isNotEmpty) {
      await tester.tap(encBtn.first);
      await pumpModal(tester);
    }
  });

  testWidgets('8. RatingsScreen (ratings.html + dialog)', (tester) async {
    await pumpAndScroll(
      tester,
      const RatingsScreen(),
      logicalSize: const Size(360, 780),
    );
    final infoBtn = find.byTooltip('评级说明');
    if (infoBtn.evaluate().isNotEmpty) {
      await tester.tap(infoBtn.first);
      await pumpModal(tester);
      await tester.tap(find.text('知道了'));
      await pumpModal(tester);
    }
  });

  testWidgets('9. SourceDetailScreen', (tester) async {
    await pumpAndScroll(
      tester,
      const SourceDetailScreen(
        sourceId: 'haige',
        lottery: Lottery.macau,
        sourceName: '海哥平特一肖',
      ),
      logicalSize: const Size(360, 780),
    );
  });

  testWidgets('10. AiScreen (ai-analysis.html)', (tester) async {
    await pumpAndScroll(
      tester,
      const AiScreen(),
      logicalSize: const Size(360, 780),
    );
    final streakMode = find.text('连肖研判');
    if (streakMode.evaluate().isNotEmpty) {
      await tester.tap(streakMode.first);
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('11. AiReportScreen (ai-report.html)', (tester) async {
    await pumpAndScroll(
      tester,
      const AiReportScreen(period: '2026277'),
      logicalSize: const Size(360, 780),
    );
    final rawBtn = find.text('原始 HTML');
    if (rawBtn.evaluate().isNotEmpty) {
      await tester.tap(rawBtn.first);
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('12. JumpCodeAssistantScreen (jump-code-assistant.html)',
      (tester) async {
    await pumpAndScroll(
      tester,
      const JumpCodeAssistantScreen(),
      logicalSize: const Size(360, 780),
    );
    final includeMode = find.text('正选号码');
    if (includeMode.evaluate().isNotEmpty) {
      await tester.tap(includeMode.first);
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('13. PlayCatalogScreen (play-catalog.html)', (tester) async {
    await pumpAndScroll(
      tester,
      const PlayCatalogScreen(),
      logicalSize: const Size(360, 780),
    );
  });

  testWidgets('14. SourceCatalogScreen (sources.html)', (tester) async {
    await pumpAndScroll(
      tester,
      const SourceCatalogScreen(),
      logicalSize: const Size(360, 780),
    );
    for (final chip in ['已启用', '已暂停', '异常', '全部']) {
      final f = find.text(chip);
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first);
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
  });

  testWidgets('15. MonitorScreen (monitor.html)', (tester) async {
    await pumpAndScroll(
      tester,
      const MonitorScreen(),
      logicalSize: const Size(360, 780),
    );
    final confirmBtn = find.text('确认缺期');
    if (confirmBtn.evaluate().isNotEmpty) {
      await tester.tap(confirmBtn.first);
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('16. SystemSettingsScreen (settings.html)', (tester) async {
    await pumpAndScroll(
      tester,
      const SystemSettingsScreen(),
      logicalSize: const Size(360, 780),
    );
  });

  testWidgets('17. ProfileScreen & SessionsScreen (profile.html)',
      (tester) async {
    await pumpAndScroll(
      tester,
      const ProfileScreen(),
      logicalSize: const Size(360, 780),
    );
    await pumpAndScroll(
      tester,
      const SessionsScreen(),
      logicalSize: const Size(360, 780),
    );
  });

  testWidgets('18. CollectScreen, RulesScreen, ConsensusScreen, MessagesScreen',
      (tester) async {
    await pumpAndScroll(
      tester,
      const CollectScreen(),
      logicalSize: const Size(360, 780),
    );
    await pumpAndScroll(
      tester,
      const RulesScreen(),
      logicalSize: const Size(360, 780),
    );
    await pumpAndScroll(
      tester,
      const ConsensusScreen(),
      logicalSize: const Size(360, 780),
    );
    await pumpAndScroll(
      tester,
      const MessagesScreen(),
      logicalSize: const Size(360, 780),
    );
    await pumpAndScroll(
      tester,
      const SubscriptionScreen(),
      logicalSize: const Size(360, 780),
    );
  });

  testWidgets('19. RecordsScreen, RecordAddScreen, RecordDetailScreen, RecordStatsScreen',
      (tester) async {
    await pumpAndScroll(
      tester,
      const RecordsScreen(),
      logicalSize: const Size(360, 780),
    );
    await pumpAndScroll(
      tester,
      const RecordAddScreen(),
      logicalSize: const Size(360, 780),
    );
    await pumpAndScroll(
      tester,
      const RecordDetailScreen(),
      logicalSize: const Size(360, 780),
    );
    await pumpAndScroll(
      tester,
      const RecordStatsScreen(),
      logicalSize: const Size(360, 780),
    );
  });
}
