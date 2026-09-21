/// Draw list: four lottery tabs, paged, pull to refresh, period-range filter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/draw.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import '../../ui/widgets/number_ball.dart';
import 'draw_detail_screen.dart';
import 'draws_providers.dart';

class DrawsScreen extends ConsumerStatefulWidget {
  const DrawsScreen({super.key});

  @override
  ConsumerState<DrawsScreen> createState() => _DrawsScreenState();
}

class _DrawsScreenState extends ConsumerState<DrawsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    final initial = Lottery.all.indexOf(ref.read(selectedLotteryProvider));
    _tabs = TabController(
      length: Lottery.all.length,
      initialIndex: initial < 0 ? 0 : initial,
      vsync: this,
    );
    // Keep the shared lottery selection in step, so opening another tab shows
    // the same lottery the operator was just looking at.
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      ref.read(selectedLotteryProvider.notifier).set(Lottery.all[_tabs.index]);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('开奖'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [for (final l in Lottery.all) Tab(text: l.label)],
        ),
        actions: [
          IconButton(
            tooltip: '期号区间筛选',
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: _openFilter,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [for (final l in Lottery.all) _DrawTab(lottery: l)],
      ),
    );
  }

  Future<void> _openFilter() async {
    final lottery = Lottery.all[_tabs.index];
    final current = ref.read(drawListProvider(lottery)).value;
    final result = await showModalBottomSheet<({String? from, String? to})>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PeriodFilterSheet(
        initialFrom: current?.periodFrom,
        initialTo: current?.periodTo,
      ),
    );
    if (result == null || !mounted) return;
    await ref
        .read(drawListProvider(lottery).notifier)
        .applyFilter(periodFrom: result.from, periodTo: result.to);
  }
}

class _DrawTab extends ConsumerWidget {
  const _DrawTab({required this.lottery});

  final Lottery lottery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(drawListProvider(lottery));
    final notifier = ref.read(drawListProvider(lottery).notifier);

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: AsyncView<DrawListState>(
        value: async,
        loading: const SkeletonList(itemHeight: 110),
        onRetry: notifier.refresh,
        emptyCheck: (state) => state.items.isEmpty,
        emptyMessage: '暂无开奖记录',
        builder: (state) => Column(
          children: [
            if (state.isStale)
              OfflineBanner(
                storedAtLabel: state.storedAtLabel,
                onRetry: notifier.refresh,
              ),
            if (state.isFiltered)
              _FilterChipBar(
                from: state.periodFrom,
                to: state.periodTo,
                onClear: () => notifier.applyFilter(),
              ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // Start the next page slightly before the end so the list
                  // rarely shows an empty gap.
                  if (notification.metrics.pixels >=
                      notification.metrics.maxScrollExtent - 400) {
                    notifier.loadMore();
                  }
                  return false;
                },
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 6, bottom: 96),
                  itemCount: state.items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == state.items.length) {
                      return _ListFooter(state: state);
                    }
                    final draw = state.items[index];
                    return _DrawCard(
                      draw: draw,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DrawDetailScreen(
                            lottery: lottery,
                            period: draw.period,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.state});

  final DrawListState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (state.items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(
          // Explicit end-of-list, so an operator knows they have seen everything
          // rather than wondering whether loading stalled.
          state.hasMore ? '上拉加载更多' : '没有更多了（共 ${state.total} 期）',
          style: context.texts.bodySmall
              ?.copyWith(color: context.colors.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _FilterChipBar extends StatelessWidget {
  const _FilterChipBar({this.from, this.to, required this.onClear});

  final String? from;
  final String? to;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final label = [
      if (from != null) '起 ${Period.short(from)}',
      if (to != null) '止 ${Period.short(to)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GlassContainer(
          blur: 16,
          borderRadius: BorderRadius.circular(20),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '期号筛选：$label',
                style: context.texts.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: DuiliaoColors.primary,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 14, color: DuiliaoColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawCard extends StatelessWidget {
  const _DrawCard({required this.draw, required this.onTap});

  final DrawRow draw;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final summary = draw.summary;
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                Period.compact(draw.period),
                style: context.texts.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              if (draw.drawDate != null)
                Text(
                  draw.drawDate!,
                  style: context.texts.bodySmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              const Spacer(),
              if (summary?.hasLianxiao == true)
                const GlassBadge(
                  label: '连肖',
                  color: DuiliaoColors.warning,
                  icon: Icons.link,
                ),
            ],
          ),
          const SizedBox(height: 12),
          DrawBallRow(draw: draw, ballSize: 38),
          if (summary != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _MiniTag(label: '和值 ${summary.sum7}'),
                _MiniTag(label: summary.sum7Size),
                _MiniTag(label: summary.sum7Odd),
                _MiniTag(label: '特${summary.temaXiao}'),
                _MiniTag(label: summary.temaHalfwave),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFF007AFF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFF007AFF).withValues(alpha: 0.18),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white70 : const Color(0xFF007AFF),
        ),
      ),
    );
  }
}

/// Period-range filter. Accepts loose input because the backend normalises it.
class _PeriodFilterSheet extends StatefulWidget {
  const _PeriodFilterSheet({this.initialFrom, this.initialTo});

  final String? initialFrom;
  final String? initialTo;

  @override
  State<_PeriodFilterSheet> createState() => _PeriodFilterSheetState();
}

class _PeriodFilterSheetState extends State<_PeriodFilterSheet> {
  late final TextEditingController _from =
      TextEditingController(text: widget.initialFrom ?? '');
  late final TextEditingController _to =
      TextEditingController(text: widget.initialTo ?? '');
  String? _error;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      blur: 35,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('期号区间筛选', style: context.texts.titleMedium),
          const SizedBox(height: 4),
          Text(
            '可填 248 或 2026248，服务端会自动规范化',
            style: context.texts.bodySmall
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _from,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '起始期号'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _to,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '结束期号'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: context.colors.error)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).pop((from: null, to: null)),
                  child: const Text('清除筛选'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('应用'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _submit() {
    final from = _from.text.trim();
    final to = _to.text.trim();
    for (final value in [from, to]) {
      if (value.isNotEmpty && !Period.looksValid(value)) {
        setState(() => _error = '期号格式不正确：$value');
        return;
      }
    }
    Navigator.of(context).pop((
      from: from.isEmpty ? null : from,
      to: to.isEmpty ? null : to,
    ));
  }
}
