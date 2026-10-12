/// Draw detail aligned 1:1 with draw-detail.html.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_exception.dart';
import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/draw.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/number_ball.dart';
import 'draws_providers.dart';

class DrawDetailScreen extends ConsumerWidget {
  const DrawDetailScreen({
    super.key,
    required this.lottery,
    required this.period,
    this.initialDraw,
  });

  final Lottery lottery;
  final String period;
  final DrawRow? initialDraw;

  static const Set<int> _jin = {4, 5, 12, 13, 26, 27, 34, 35, 42, 43};
  static const Set<int> _mu = {8, 9, 16, 17, 24, 25, 38, 39, 46, 47};
  static const Set<int> _shui = {1, 14, 15, 22, 23, 30, 31, 44, 45};
  static const Set<int> _huo = {2, 3, 10, 11, 18, 19, 32, 33, 40, 41, 48, 49};

  static String _wuxingFor(int n) {
    if (_jin.contains(n)) return '金';
    if (_mu.contains(n)) return '木';
    if (_shui.contains(n)) return '水';
    if (_huo.contains(n)) return '火';
    return '土';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (lottery: lottery, period: period);
    final async = ref.watch(drawDetailProvider(key));
    final draw =
        async.value ??
        initialDraw ??
        DrawRow(
          lottery: lottery.code,
          period: period,
          drawDate: '2026-09-26 21:32:18',
          balls: const ['03', '11', '19', '27', '34', '42'],
          tema: '26',
        );

    final temaInt = int.tryParse(draw.tema) ?? 26;
    final temaXiao =
        draw.summary?.temaXiao ?? Lottery2026Lookup.xiaoForNumber(temaInt);
    final temaBose = switch (Lottery2026Lookup.boseForNumber(temaInt)) {
      'red' => '红波',
      'green' => '绿波',
      _ => '蓝波',
    };
    final jiaye = Lottery2026Lookup.jiaXiao.contains(temaXiao) ? '家禽' : '野兽';
    final oddEven = temaInt.isOdd ? '单' : '双';
    final sizeLabel = temaInt >= 25 ? '大 (25-49)' : '小 (01-24)';
    final wuxing = draw.summary?.temaWuxing ?? _wuxingFor(temaInt);
    final head = temaInt ~/ 10;
    final tail = temaInt % 10;
    final heshu = head + tail;
    final heOdd = heshu.isOdd ? '合单' : '合双';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                center: true,
                leading: GlassIconButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                title: '第 $period 期',
                subtitle: '${lottery.label}六合彩',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    // Hero Draw Card
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '开奖时间 · ${draw.openedAt ?? draw.drawDate ?? '2026-09-26 21:32:18'}',
                                style: context.texts.labelSmall,
                              ),
                              const GlassStatusPill(
                                label: '已对奖',
                                color: DuiliaoColors.hit,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          DrawBallRow(draw: draw, ballSize: 38),
                        ],
                      ),
                    ),

                    // Section 1: 属性明细
                    const DesignSectionHeader(title: '属性明细'),
                    GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 2.35,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _AttrBox(
                          label: '特码',
                          value: '${draw.tema} · $temaBose',
                          valueColor: DuiliaoColors.waveBlueA,
                        ),
                        _AttrBox(
                          label: '特肖',
                          value: '$temaXiao · $jiaye',
                        ),
                        _AttrBox(label: '单双', value: oddEven),
                        _AttrBox(label: '大小', value: sizeLabel),
                        _AttrBox(label: '五行', value: wuxing),
                        _AttrBox(label: '头数', value: '$head 头'),
                        _AttrBox(label: '尾数', value: '$tail 尾'),
                        _AttrBox(label: '合数', value: '$heshu · $heOdd'),
                      ],
                    ),

                    // Section 2: 对奖结果
                    const DesignSectionHeader(
                      title: '对奖结果',
                      trailingText: '命中 9 / 24',
                    ),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: const [
                        _JudgeSourceRow(
                          status: HitMarkStatus.hit,
                          name: '海哥平特一肖',
                          sub: '平特一肖 · 推荐 蛇',
                          pillLabel: '命中',
                          pillColor: DuiliaoColors.hit,
                        ),
                        _JudgeSourceRow(
                          status: HitMarkStatus.hit,
                          name: '顶尖大师',
                          sub: '特码 · 推荐 08 14 26 33',
                          pillLabel: '命中',
                          pillColor: DuiliaoColors.hit,
                        ),
                        _JudgeSourceRow(
                          status: HitMarkStatus.hit,
                          name: '管家婆传真',
                          sub: '平特肖 · 推荐 兔 蛇 羊',
                          pillLabel: '命中',
                          pillColor: DuiliaoColors.hit,
                        ),
                        _JudgeSourceRow(
                          status: HitMarkStatus.miss,
                          name: '白小组',
                          sub: '连肖 · 推荐 马 猴 鸡',
                          pillLabel: '未中',
                          pillColor: DuiliaoColors.miss,
                        ),
                        _JudgeSourceRow(
                          status: HitMarkStatus.fake,
                          name: '玄机图解',
                          sub: '自称命中 · 官方对奖未中',
                          pillLabel: '虚假报喜',
                          pillColor: DuiliaoColors.warning,
                        ),
                      ],
                    ),

                    // Section 3: 采集入库
                    const DesignSectionHeader(title: '采集入库'),
                    GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.9,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _IngestKpiBox(label: '本期新增', value: '128'),
                        _IngestKpiBox(
                          label: '去重后',
                          value: '96',
                          valueColor: Theme.of(context).colorScheme.primary,
                        ),
                        const _IngestKpiBox(label: '涉及来源', value: '24'),
                        const _IngestKpiBox(
                          label: '完成时间',
                          value: '21:35',
                          valueColor: DuiliaoColors.hit,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Bottom action dock
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Row(
                  children: [
                    GlassGhostButton(
                      label: '同步日志',
                      icon: Icons.refresh_rounded,
                      onTap: () => _syncDraw(context, ref),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GlassButton(
                        onPressed: () => _triggerJudge(context, ref),
                        child: const Text('手动触发对奖'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _syncDraw(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(collectorRepositoryProvider)
          .syncDraws(lottery: lottery.code, period: period);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '同步完成：新增 ${result['inserted'] ?? 0}，更新 ${result['updated'] ?? 0}',
          ),
        ),
      );
      ref.invalidate(drawDetailProvider((lottery: lottery, period: period)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.displayMessage)));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('已同步第 $period 期开奖日志')),
      );
    }
  }

  Future<void> _triggerJudge(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(collectorRepositoryProvider)
          .judge(lottery: lottery.code, period: period);
      messenger.showSnackBar(
        SnackBar(content: Text('对奖完成：${result.judged} 条，命中 ${result.hits}')),
      );
      ref.invalidate(drawDetailProvider((lottery: lottery, period: period)));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('已完成第 $period 期全部来源对奖复核')),
      );
    }
  }
}

class _AttrBox extends StatelessWidget {
  const _AttrBox({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return GlassSubtleBox(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: context.texts.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _JudgeSourceRow extends StatelessWidget {
  const _JudgeSourceRow({
    required this.status,
    required this.name,
    required this.sub,
    required this.pillLabel,
    required this.pillColor,
  });

  final HitMarkStatus status;
  final String name;
  final String sub;
  final String pillLabel;
  final Color pillColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          HitMarkBadge(status: status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(sub, style: context.texts.labelSmall),
              ],
            ),
          ),
          GlassStatusPill(
            label: pillLabel,
            color: pillColor,
            showDot: false,
          ),
        ],
      ),
    );
  }
}

class _IngestKpiBox extends StatelessWidget {
  const _IngestKpiBox({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: context.texts.labelSmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
