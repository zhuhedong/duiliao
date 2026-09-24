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
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: GlassContainer(
                  height: 54,
                  borderRadius: BorderRadius.circular(999),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          '历史开奖',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '期号筛选',
                        icon: const Icon(Icons.filter_alt_outlined, size: 20),
                        onPressed: _openFilter,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(20),
                  padding: const EdgeInsets.all(4),
                  child: TabBar(
                    controller: _tabs,
                    indicator: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                    ),
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                    tabs: [for (final l in Lottery.all) Tab(text: l.label)],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [for (final l in Lottery.all) _DrawTab(lottery: l)],
                ),
              ),
            ],
          ),
        ),
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
                  if (notification.metrics.pixels >=
                      notification.metrics.maxScrollExtent - 400) {
                    notifier.loadMore();
                  }
                  return false;
                },
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 10, bottom: 96),
                  itemCount: state.items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == state.items.length) {
                      return _ListFooter(
                        state: state,
                        onRetry: notifier.loadMore,
                      );
                    }
                    final draw = state.items[index];
                    return _TimelineDrawNode(
                      draw: draw,
                      isFirst: index == 0,
                      isLast: index == state.items.length - 1,
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
  const _ListFooter({required this.state, required this.onRetry});

  final DrawListState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (state.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                state.loadMoreError!,
                style: context.texts.bodySmall?.copyWith(color: context.colors.error),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
    }
    if (state.items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(
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
          borderRadius: BorderRadius.circular(20),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 16, color: DuiliaoColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineDrawNode extends StatelessWidget {
  const _TimelineDrawNode({
    required this.draw,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final DrawRow draw;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final summary = draw.summary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline column
          SizedBox(
            width: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The vertical line
                Positioned(
                  top: isFirst ? 30 : 0,
                  bottom: isLast ? 30 : 0,
                  width: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          primary.withValues(alpha: 0.5),
                          primary.withValues(alpha: 0.1),
                        ],
                      ),
                    ),
                  ),
                ),
                // The glowing node
                Positioned(
                  top: 24,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primary,
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Card content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 14, top: 4, bottom: 12),
              child: GlassContainer(
                onTap: onTap,
                borderRadius: BorderRadius.circular(20),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            Period.compact(draw.period),
                            style: context.texts.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (draw.drawDate != null)
                          Text(
                            draw.drawDate!,
                            style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                          ),
                        const Spacer(),
                        if (summary?.hasLianxiao == true)
                          GlassBadge(
                            label: '连肖',
                            color: DuiliaoColors.warning,
                            icon: Icons.link,
                            small: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DrawBallRow(draw: draw, ballSize: 34),
                    if (summary != null) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _MiniFluidTag(label: '和值 ${summary.sum7}'),
                          _MiniFluidTag(label: summary.sum7Size),
                          _MiniFluidTag(label: summary.sum7Odd),
                          _MiniFluidTag(label: '特${summary.temaXiao}', isHighlight: true),
                          _MiniFluidTag(label: summary.temaHalfwave, isHighlight: true),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniFluidTag extends StatelessWidget {
  const _MiniFluidTag({required this.label, this.isHighlight = false});

  final String label;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isHighlight
            ? primary.withValues(alpha: 0.15)
            : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHighlight
              ? primary.withValues(alpha: 0.3)
              : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1)),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isHighlight ? primary : (isDark ? Colors.white70 : Colors.black87),
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
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('期号区间筛选', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            '可填 248 或 2026248，服务端会自动规范化',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _from,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '起始期号',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _to,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '结束期号',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop((from: null, to: null)),
                  child: const Text('清除'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassButton(
                  onPressed: _submit,
                  height: 44,
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
