import 'package:duiliao_app/domain/lottery.dart';
import 'package:duiliao_app/features/design/records_screens.dart';
import 'package:duiliao_app/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets(
      'RecordsScreen starts with 0 fake records, supports adding and deleting records cleanly',
      (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: DuiliaoTheme.dark(),
          home: const RecordsScreen(),
        ),
      ),
    );
    await tester.pump();

    // 1. Starts empty with no un-deletable fake records
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('暂无投注记录'), findsOneWidget);
    expect(find.text('¥0'), findsOneWidget);
    expect(find.text('0 单 · 0 注'), findsOneWidget);

    // 2. Add a real record and verify it appears and can be deleted directly on the list page
    container.read(bettingRecordsProvider.notifier).addRecord(
          const BettingRecordItem(
            id: 'rec-user-1',
            lottery: Lottery.macau,
            period: '2026277',
            playType: '正码',
            timeLabel: '20:15',
            numbers: ['03', '15', '27', '39', '04', '16', '28', '40'],
            xiaos: [],
            stakePerNote: 5,
            multiplier: 1,
            notesCount: 8,
            totalAmount: 40,
            status: 'pending',
            rawInput: '龙兔各数5',
          ),
        );
    await tester.pump();

    expect(find.text('第 2026277 期'), findsOneWidget);
    expect(find.text('1 单 · 8 注'), findsOneWidget);

    // Tap the delete button on the record card
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pump();

    expect(container.read(bettingRecordsProvider), isEmpty);
    expect(find.text('暂无投注记录'), findsOneWidget);
  });

  testWidgets('RecordAddScreen starts empty without default values and supports chips/input',
      (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const RecordAddScreen()));
    await tester.pump();

    // Verify default value is removed: starts empty with 0 notes and ¥0
    expect(find.text('新增记录'), findsOneWidget);
    expect(find.text('0 注 · 合计 ¥0'), findsOneWidget);
    expect(find.text('等待输入号码或生肖'), findsOneWidget);
    expect(find.text('读取剪切板'), findsOneWidget);

    // Switch to 连肖复试 - still clean and empty
    await tester.tap(find.text('连肖复试'));
    await tester.pump();
    expect(find.text('新增记录 · 连肖'), findsOneWidget);
    expect(find.text('等待输入生肖内容'), findsOneWidget);
    expect(find.text('0 注 · 合计 ¥0'), findsOneWidget);

    // Click sample chip: 示例：复试3,4连一组5块
    await tester.tap(find.text('示例：复试3,4连一组5块'));
    await tester.pump();
    expect(find.text('已识别 5 个生肖 · 复试 3,4 连 · 单注 ¥5'), findsOneWidget);
    expect(find.text('组合展开 · 15 注'), findsOneWidget);
    expect(find.text('¥75'), findsWidgets);

    // Switch to 不中码
    await tester.tap(find.text('不中码'));
    await tester.pump();
    expect(find.text('新增记录 · 不中码'), findsOneWidget);

    // Click sample chip: 示例：6不中各10
    await tester.tap(find.text('示例：6不中各10'));
    await tester.pump();
    expect(find.text('已识别 6 个号码 · 6 不中 · 单注 ¥10'), findsOneWidget);
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

  testWidgets('RecordAddScreen auto reads clipboard on launch', (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // Mock platform clipboard content
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.getData') {
          return const <String, dynamic>{'text': '龙牛猴鸡兔复试4连个数10'};
        }
        return null;
      },
    );

    await tester.pumpWidget(wrap(const RecordAddScreen()));
    // Let postFrameCallback run
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Clipboard content should have been automatically read into input
    expect(find.text('已识别 5 个生肖 · 复试 4 连 · 单注 ¥10'), findsOneWidget);
    expect(find.text('组合展开 · 5 注'), findsOneWidget);
    ScaffoldMessenger.of(
      tester.element(find.byType(RecordAddScreen)),
    ).clearSnackBars();
    await tester.pump();
  });

  testWidgets('RecordDetailScreen and RecordStatsScreen render cleanly',
      (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    const wonRecord = BettingRecordItem(
      id: 'rec-won-1',
      lottery: Lottery.macau,
      period: '2026276',
      playType: '正码',
      timeLabel: '09-26 19:52',
      numbers: ['06', '11', '17', '26', '30', '42'],
      xiaos: [],
      stakePerNote: 5,
      multiplier: 1,
      notesCount: 6,
      totalAmount: 30,
      status: 'won',
      hitNumbers: ['11', '26', '42'],
      hitNotes: 3,
      payout: 105,
      netProfit: 75,
      winPillLabel: '中 3 码 +¥75',
      rawInput: '06.11.17.26.30.42个数5',
      drawNumbers: ['03', '11', '19', '27', '34', '42'],
      specialNumber: '26',
      drawTime: '09-26 21:32',
    );

    await tester.pumpWidget(wrap(const RecordDetailScreen(record: wonRecord)));
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

  testWidgets('Records copy single and whole period to specified period',
      (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: DuiliaoTheme.dark(),
          home: const RecordsScreen(),
        ),
      ),
    );
    await tester.pump();

    // 1. Add record in period 2026286
    container.read(bettingRecordsProvider.notifier).addRecord(
          const BettingRecordItem(
            id: 'rec-test-copy-1',
            lottery: Lottery.macau,
            period: '2026286',
            playType: '正码',
            timeLabel: '10:00',
            numbers: ['03', '15', '27'],
            xiaos: [],
            stakePerNote: 10,
            multiplier: 1,
            notesCount: 3,
            totalAmount: 30,
            status: 'won',
            hitNumbers: ['03'],
            payout: 70,
            netProfit: 40,
            rawInput: '03,15,27各10',
          ),
        );
    await tester.pump();

    expect(find.text('第 2026286 期'), findsOneWidget);
    expect(find.text('整期复制'), findsOneWidget);

    // 2. Test copyRecordToPeriod
    final copied = await container
        .read(bettingRecordsProvider.notifier)
        .copyRecordToPeriod('rec-test-copy-1', '2026287');
    expect(copied, isNotNull);
    expect(copied!.period, '2026287');
    expect(copied.status, 'pending');
    expect(copied.hitNumbers, isEmpty);
    expect(copied.payout, 0);
    expect(copied.netProfit, -30);
    await tester.pump();

    expect(find.text('第 2026287 期'), findsOneWidget);

    // 3. Test copyPeriodToPeriod
    final batchCopied = await container
        .read(bettingRecordsProvider.notifier)
        .copyPeriodToPeriod('2026286', '2026288');
    expect(batchCopied.length, 1);
    expect(batchCopied.first.period, '2026288');
    expect(batchCopied.first.status, 'pending');
    await tester.pump();

    expect(find.text('第 2026288 期'), findsOneWidget);
  });
}
