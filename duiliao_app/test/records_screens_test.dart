import 'package:duiliao_app/features/design/records_screens.dart';
import 'package:duiliao_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        theme: DuiliaoTheme.dark(),
        home: child,
      ),
    );
  }

  testWidgets('RecordsScreen renders without layout exceptions and filters records',
      (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const RecordsScreen()));
    await tester.pump();

    expect(find.text('记录'), findsOneWidget);
    expect(find.text('智能识别 · 自动对奖'), findsOneWidget);
    expect(find.text('本期汇总'), findsOneWidget);
    expect(find.text('¥250'), findsOneWidget);
    expect(find.text('4 单 · 22 注'), findsOneWidget);

    // Filter tabs work without layout errors
    await tester.tap(find.text('待开奖').first);
    await tester.pump();
    expect(find.text('第 2026277 期'), findsOneWidget);

    await tester.tap(find.text('已中奖'));
    await tester.pump();
    expect(find.text('第 2026276 期'), findsOneWidget);

    await tester.tap(find.text('未中'));
    await tester.pump();
    expect(find.text('第 2026275 期'), findsOneWidget);
  });

  testWidgets('RecordAddScreen renders all 3 modes and saves record',
      (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const RecordAddScreen()));
    await tester.pump();

    expect(find.text('新增记录'), findsOneWidget);
    expect(find.text('¥50'), findsWidgets);

    // Switch to 连肖复试
    await tester.tap(find.text('连肖复试'));
    await tester.pump();
    expect(find.text('新增记录 · 连肖'), findsOneWidget);
    expect(find.text('组合展开 · 5 注'), findsOneWidget);
    expect(find.text('¥100'), findsWidgets);

    // Switch to 不中码
    await tester.tap(find.text('不中码'));
    await tester.pump();
    expect(find.text('新增记录 · 不中码'), findsOneWidget);
    expect(find.text('¥10'), findsWidgets);

    // Switch back to 号码单式 and test "龙兔各数5" -> 8 numbers × ¥5 = ¥40
    await tester.tap(find.text('号码单式'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '龙兔各数5');
    await tester.pump();
    expect(find.text('已识别 龙兔转 8 个号码 · 单注 ¥5'), findsOneWidget);
    expect(find.text('龙 (03·15·27·39)'), findsOneWidget);
    expect(find.text('兔 (04·16·28·40)'), findsOneWidget);
    expect(find.text('¥40'), findsWidgets);

    // Test "鼠虎马猴鸡 给我打复试3，4连一组5块" -> auto-switches to 连肖复试, C(5,3)+C(5,4)=15注 × ¥5 = ¥75
    await tester.enterText(
      find.byType(TextField).first,
      '鼠虎马猴鸡 给我打复试3，4连一组5块',
    );
    await tester.pump();
    expect(find.text('已识别 5 个生肖 · 复试 3,4 连 · 单注 ¥5'), findsOneWidget);
    expect(find.text('组合展开 · 15 注'), findsOneWidget);
    expect(find.text('¥75'), findsWidgets);
  });

  testWidgets('RecordDetailScreen and RecordStatsScreen render cleanly',
      (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const RecordDetailScreen()));
    await tester.pump();

    expect(find.text('记录详情'), findsOneWidget);
    expect(find.text('+¥75'), findsWidgets);
    expect(find.text('我的号码 · 中 3 码'), findsOneWidget);
    expect(find.text('开奖对照'), findsOneWidget);

    await tester.pumpWidget(wrap(const RecordStatsScreen()));
    await tester.pump();

    expect(find.text('记录统计'), findsOneWidget);
    expect(find.text('每日盈亏'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    expect(find.text('常中号码'), findsOneWidget);
    expect(find.text('月度小结'), findsOneWidget);
  });
}
