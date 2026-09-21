/// Draw detail: drop order, per-ball attributes, period summary, 连肖 detection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_exception.dart';
import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/draw.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import '../../ui/widgets/number_ball.dart';
import '../auth/auth_providers.dart';
import '../comparison/comparison_screen.dart';
import 'draws_providers.dart';

class DrawDetailScreen extends ConsumerWidget {
  const DrawDetailScreen({super.key, required this.lottery, required this.period});

  final Lottery lottery;
  final String period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (lottery: lottery, period: period);
    final async = ref.watch(drawDetailProvider(key));
    final canOperate = ref.watch(canOperateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('${lottery.label} ${Period.compact(period)}'),
        actions: [
          IconButton(
            tooltip: '本期对照',
            icon: const Icon(Icons.compare_arrows),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ComparisonScreen(lottery: lottery, initialPeriod: period),
              ),
            ),
          ),
          // Draw sync and re-judging mutate data, so they are staff/admin only.
          // Hiding them for role=user is a usability measure; the server enforces
          // the boundary.
          if (canOperate)
            PopupMenuButton<String>(
              onSelected: (action) => _runAction(context, ref, action),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'sync', child: Text('同步开奖')),
                PopupMenuItem(value: 'judge', child: Text('重新判定')),
              ],
            ),
        ],
      ),
      body: AsyncView<DrawRow?>(
        value: async,
        loading: const SkeletonList(itemHeight: 120),
        onRetry: () => ref.invalidate(drawDetailProvider(key)),
        emptyCheck: (draw) => draw == null,
        emptyMessage: '未找到该期开奖',
        builder: (draw) => _DetailBody(draw: draw!),
      ),
    );
  }

  Future<void> _runAction(BuildContext context, WidgetRef ref, String action) async {
    final repo = ref.read(collectorRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(action == 'sync' ? '正在同步开奖…' : '正在重新判定…')),
    );
    try {
      if (action == 'sync') {
        final result = await repo.syncDraws(lottery: lottery.code, period: period);
        messenger.showSnackBar(SnackBar(
          content: Text('同步完成：新增 ${result['inserted'] ?? 0}，更新 ${result['updated'] ?? 0}'),
        ));
        ref.invalidate(drawDetailProvider((lottery: lottery, period: period)));
        ref.invalidate(drawListProvider(lottery));
      } else {
        final result = await repo.judge(lottery: lottery.code, period: period);
        messenger.showSnackBar(SnackBar(
          content: Text('判定完成：${result.judged} 条，命中 ${result.hits}'),
        ));
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.displayMessage)));
    } on NetworkException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.displayMessage)));
    }
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.draw});

  final DrawRow draw;

  @override
  Widget build(BuildContext context) {
    final summary = draw.summary;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _DropOrderCard(draw: draw),
        if (summary != null) _SummaryCard(summary: summary),
        if (summary != null &&
            (summary.lianxiaoGroups.isNotEmpty ||
                summary.adjacentLianxiao.isNotEmpty))
          _LianxiaoCard(summary: summary),
        if (draw.isEnriched)
          _PerBallCard(draw: draw)
        else
          const Padding(
            padding: EdgeInsets.all(16),
            child: WarningNote(
              message: '该期未包含逐球属性数据，无法展示生肖与五行明细',
              icon: Icons.info_outline,
            ),
          ),
      ],
    );
  }
}

/// z1–z6 in the order the balls were drawn, then the 特码.
class _DropOrderCard extends StatelessWidget {
  const _DropOrderCard({required this.draw});

  final DrawRow draw;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('落球顺序', style: context.texts.titleSmall),
                const Spacer(),
                Text(
                  draw.source,
                  style: context.texts.labelSmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Position labels are shown above the balls so 正码 order is explicit.
            Row(
              children: [
                for (var i = 0; i < draw.balls.length; i++)
                  Expanded(
                    child: Column(
                      children: [
                        Text('z${i + 1}', style: context.texts.labelSmall),
                        const SizedBox(height: 4),
                        NumberBall(
                          number: draw.balls[i],
                          attr: i < draw.ballsDetail.length
                              ? draw.ballsDetail[i]
                              : null,
                          size: 38,
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '特码',
                        style: context.texts.labelSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      NumberBall(
                        number: draw.tema,
                        attr: draw.temaDetail,
                        isSpecial: true,
                        size: 38,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (draw.openedAt != null) ...[
              const SizedBox(height: 10),
              Text(
                '开奖时间 ${draw.openedAt}',
                style: context.texts.bodySmall
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final DrawSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('期号汇总', style: context.texts.titleSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                StatTile(label: '七球和值', value: '${summary.sum7}'),
                StatTile(label: '和值大小', value: summary.sum7Size),
                StatTile(label: '和值单双', value: summary.sum7Odd),
              ],
            ),
            const Divider(height: 24),
            Text('特码属性', style: context.texts.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _AttrChip(label: '生肖', value: summary.temaXiao),
                _AttrChip(label: '波色', value: summary.temaBose),
                _AttrChip(label: '大小', value: summary.temaSize),
                _AttrChip(label: '单双', value: summary.temaOdd),
                _AttrChip(label: '合数', value: summary.temaSumOdd),
                _AttrChip(label: '家野', value: summary.temaJiaye),
                _AttrChip(label: '半波', value: summary.temaHalfwave),
                // Null 五行 is stated rather than left blank, so the absence is
                // attributable to a missing table rather than a display bug.
                _AttrChip(
                  label: '五行',
                  value: summary.temaWuxing ?? '无权威五行表',
                  muted: summary.temaWuxing == null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttrChip extends StatelessWidget {
  const _AttrChip({required this.label, required this.value, this.muted = false});

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: context.texts.labelSmall
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          Text(
            value,
            style: context.texts.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: muted ? context.colors.onSurfaceVariant : null,
              fontStyle: muted ? FontStyle.italic : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// 连肖: balls in this draw sharing a zodiac, and whether any are adjacent in
/// drop order.
class _LianxiaoCard extends StatelessWidget {
  const _LianxiaoCard({required this.summary});

  final DrawSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('连肖检测', style: context.texts.titleSmall),
                const SizedBox(width: 8),
                if (summary.hasAdjacentLianxiao == true)
                  const StatusChip(
                    label: '顺位紧邻',
                    color: DuiliaoColors.warning,
                    icon: Icons.link,
                    compact: true,
                  ),
              ],
            ),
            if (summary.lianxiaoText != null) ...[
              const SizedBox(height: 6),
              Text(summary.lianxiaoText!, style: context.texts.bodySmall),
            ],
            const SizedBox(height: 10),
            for (final group in summary.lianxiaoGroups)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 54,
                      child: Text(
                        '${group.xiao} ×${group.count}',
                        style: context.texts.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        children: [
                          for (var i = 0; i < group.nums.length; i++)
                            Column(
                              children: [
                                NumberBall(
                                  number: group.nums[i],
                                  size: 30,
                                  showColorName: false,
                                ),
                                if (i < group.positions.length)
                                  Text(
                                    group.positions[i],
                                    style: context.texts.labelSmall,
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (summary.adjacentLianxiao.isNotEmpty) ...[
              const Divider(height: 20),
              Text('紧邻同肖', style: context.texts.labelLarge),
              const SizedBox(height: 6),
              for (final adjacent in summary.adjacentLianxiao)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${adjacent.xiao}：${adjacent.pos1} ${adjacent.num1} → '
                    '${adjacent.pos2} ${adjacent.num2}',
                    style: context.texts.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Every ball's full attribute set, expandable per ball.
class _PerBallCard extends StatelessWidget {
  const _PerBallCard({required this.draw});

  final DrawRow draw;

  @override
  Widget build(BuildContext context) {
    final entries = <({String position, NumberAttr attr})>[
      for (var i = 0; i < draw.ballsDetail.length; i++)
        (position: 'z${i + 1}', attr: draw.ballsDetail[i]),
      if (draw.temaDetail != null) (position: '特码', attr: draw.temaDetail!),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Text('逐球属性', style: context.texts.titleSmall),
            ),
            for (final entry in entries)
              ExpansionTile(
                dense: true,
                shape: const Border(),
                collapsedShape: const Border(),
                leading: NumberBall(
                  number: entry.attr.num,
                  attr: entry.attr,
                  isSpecial: entry.position == '特码',
                  size: 34,
                  showColorName: false,
                ),
                title: Row(
                  children: [
                    Text(
                      entry.position,
                      style: context.texts.labelMedium
                          ?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${entry.attr.xiao} · ${entry.attr.bose} · '
                      '${entry.attr.size}${entry.attr.odd}',
                      style: context.texts.bodyMedium,
                    ),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _AttributeGrid(attr: entry.attr),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AttributeGrid extends StatelessWidget {
  const _AttributeGrid({required this.attr});

  final NumberAttr attr;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String?)>[
      ('生肖', attr.xiao),
      ('家野', attr.jiaye),
      ('波色', attr.bose),
      ('大小', attr.size),
      ('单双', attr.odd),
      ('头数', attr.head),
      ('尾数', attr.wei),
      ('合数单双', attr.sum),
      ('五行', attr.wuxing),
      ('半波', attr.halfwave),
      // 2026 灵码 fields.
      ('称谓', attr.role),
      ('花', attr.flower),
      ('时辰', attr.hour),
      ('地支', attr.dizhi),
      ('生肖色', attr.xiaoColor),
      ('笔画', attr.stroke),
      // Zodiac classifications.
      ('天地肖', attr.tianDi),
      ('阴阳肖', attr.yinYang),
      ('男女肖', attr.gender),
      ('吉凶肖', attr.luck),
      ('季节', attr.season),
      ('方位', attr.direction),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (label, value) in rows)
          if (value != null && value.isNotEmpty)
            _AttrChip(label: label, value: value)
          // 五行 is the one attribute whose absence is meaningful, so it is
          // stated rather than omitted.
          else if (label == '五行')
            const _AttrChip(label: '五行', value: '该年份无权威五行表', muted: true),
      ],
    );
  }
}
