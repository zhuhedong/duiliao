/// Message centre and subscription settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_exception.dart';
import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/app_event.dart';
import '../../domain/models/source.dart';
import '../../domain/models/user.dart';
import '../../domain/play_type.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import '../comparison/comparison_screen.dart';
import '../consensus/consensus_screen.dart';
import '../draws/draw_detail_screen.dart';
import '../ratings/source_detail_screen.dart';
import 'notification_service.dart';

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(messageCentreProvider);
    final centre = ref.read(messageCentreProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('消息中心'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '订阅设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
            ),
          ),
          if (state.unreadCount > 0)
            TextButton(
              onPressed: centre.markAllRead,
              child: const Text('全部已读'),
            ),
        ],
      ),
      body: GlassBackground(
        child: RefreshIndicator(
          onRefresh: () async {
            final subscription = ref.read(subscriptionProvider).value;
            await centre.pollOnce(subscription: subscription);
          },
          child: state.messages.isEmpty
              ? const EmptyState(
                  message: '暂无消息',
                  icon: Icons.notifications_none,
                  detail: '开奖、命中、连挂与采集完成的通知会显示在这里',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: state.messages.length,
                  itemBuilder: (context, index) {
                    final message = state.messages[index];
                    return _MessageTile(
                      message: message,
                      onTap: () {
                        centre.markRead(message.event.dedupeKey);
                        _openTarget(context, message.event);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  /// Follow an event's deep link to the screen it refers to.
  void _openTarget(BuildContext context, AppEvent event) {
    final lottery = Lottery.parse(event.lottery);
    Widget? target;
    switch (event.type) {
      case AppEventType.drawPublished:
        if (event.period != null) {
          target = DrawDetailScreen(lottery: lottery, period: event.period!);
        }
      case AppEventType.consensusLeaderChanged:
        target = ConsensusScreen(lottery: lottery, initialPeriod: event.period);
      case AppEventType.sourceHit:
      case AppEventType.sourceMissStreak:
        final sourceId = event.data['source_id'];
        if (sourceId is String) {
          target = SourceDetailScreen(
            sourceId: sourceId,
            lottery: lottery,
            sourceName: event.data['source_name'] as String?,
          );
        }
      case AppEventType.collectJobFinished:
        target = ComparisonScreen(lottery: lottery, initialPeriod: event.period);
      case null:
        target = null;
    }
    if (target == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => target!));
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message, required this.onTap});

  final AppMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final event = message.event;
    final (icon, color) = switch (event.type) {
      AppEventType.drawPublished => (Icons.casino_outlined, context.colors.primary),
      AppEventType.sourceHit => (Icons.check_circle_outline, DuiliaoColors.hit),
      AppEventType.sourceMissStreak => (
          Icons.trending_down,
          DuiliaoColors.miss,
        ),
      AppEventType.consensusLeaderChanged => (
          Icons.swap_vert,
          DuiliaoColors.warning,
        ),
      AppEventType.collectJobFinished => (
          Icons.cloud_done_outlined,
          context.colors.tertiary,
        ),
      null => (Icons.notifications_none, DuiliaoColors.pending),
    };

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.14),
              border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        style: context.texts.bodyMedium?.copyWith(
                          fontWeight: message.read ? FontWeight.w500 : FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      _timeLabel(event.occurredAtTime),
                      style: context.texts.labelSmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    if (!message.read) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: context.colors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: context.colors.primary.withValues(alpha: 0.6),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  event.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _timeLabel(DateTime? at) {
    if (at == null) return '';
    return '${at.month}/${at.day} '
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
  }
}

/// Followed sources, default preferences and notification rules.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  Subscription? _draft;
  String _query = '';
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(subscriptionProvider);
    final sourcesAsync = ref.watch(allSourcesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('订阅与通知'),
        backgroundColor: Colors.transparent,
        actions: [
          if (_draft != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
      body: GlassBackground(
        child: AsyncView<Subscription>(
          value: async,
          loading: const SkeletonList(itemHeight: 56),
          onRetry: () => ref.invalidate(subscriptionProvider),
          builder: (saved) {
            final current = _draft ?? saved;
            return ListView(
              padding: const EdgeInsets.only(top: 6, bottom: 96),
              children: [
                const SectionHeader(
                  title: '通知规则',
                  subtitle: '关闭后不再弹出对应类型的本地通知',
                ),
                GlassGroup(
                  children: [
                    for (final entry in NotifyRule.toggles.entries)
                      SwitchListTile(
                        title: Text(entry.value),
                        subtitle: entry.key == NotifyRule.sourceHit ||
                                entry.key == NotifyRule.sourceMissStreak
                            ? const Text('仅对已关注的数据源生效')
                            : null,
                        value: current.isEnabled(
                          entry.key,
                          fallback: entry.key != NotifyRule.sourceHit &&
                              entry.key != NotifyRule.consensusLeaderChanged,
                        ),
                        onChanged: (value) => setState(
                          () => _draft = current.withRule(entry.key, value),
                        ),
                      ),
                    ListTile(
                      title: const Text('连挂提醒阈值'),
                      subtitle: Text('连续未中 ${current.missStreakThreshold} 期时提醒'),
                      trailing: SizedBox(
                        width: 140,
                        child: Slider(
                          value: current.missStreakThreshold.toDouble(),
                          min: 2,
                          max: 10,
                          divisions: 8,
                          label: '${current.missStreakThreshold}',
                          onChanged: (value) => setState(
                            () => _draft = current.withRule(
                              NotifyRule.missStreakThreshold,
                              value.round(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SectionHeader(title: '默认彩种'),
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final l in Lottery.all)
                        GlassFilterPill(
                          label: l.label,
                          isSelected: current.lotteries.contains(l.code),
                          onTap: () {
                            final next = [...current.lotteries];
                            current.lotteries.contains(l.code)
                                ? next.remove(l.code)
                                : next.add(l.code);
                            setState(
                              () => _draft = current.copyWith(lotteries: next),
                            );
                          },
                        ),
                    ],
                  ),
                ),

                const SectionHeader(title: '默认玩法'),
                GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final play in kPlayTypes)
                        GlassFilterPill(
                          label: play.name,
                          isSelected: current.playTypes.contains(play.key),
                          onTap: () {
                            final next = [...current.playTypes];
                            current.playTypes.contains(play.key)
                                ? next.remove(play.key)
                                : next.add(play.key);
                            setState(
                              () => _draft = current.copyWith(playTypes: next),
                            );
                          },
                        ),
                    ],
                  ),
                ),

                SectionHeader(
                  title: '关注数据源',
                  subtitle: '已关注 ${current.sourceIds.length} 个',
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: '搜索数据源',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                sourcesAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: ErrorState(
                      error: e,
                      onRetry: () => ref.invalidate(allSourcesProvider),
                    ),
                  ),
                  data: (sources) {
                    final visible =
                        sources.where((s) => s.matches(_query)).take(120).toList();
                    return GlassCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (final source in visible)
                            CheckboxListTile(
                              dense: true,
                              value: current.sourceIds.contains(source.sourceId),
                              onChanged: (_) => setState(
                                () => _draft = current.withSource(
                                  source.sourceId,
                                  !current.sourceIds.contains(source.sourceId),
                                ),
                              ),
                              title: Text(source.sourceName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${Lottery.labelFor(source.lottery)} · '
                                '${PlayTypes.labelFor(source.playType)}',
                                style: context.texts.labelSmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),

                const _NotificationTimingNote(),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(collectorRepositoryProvider).saveSubscription(draft);
      ref.invalidate(subscriptionProvider);
      if (mounted) setState(() => _draft = null);
      messenger.showSnackBar(const SnackBar(content: Text('订阅已保存')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.displayMessage)));
    } on NetworkException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.displayMessage)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// The full source catalogue, for the follow list.
final allSourcesProvider = FutureProvider<List<CollectorSource>>((ref) async {
  final fetched = await ref.read(collectorRepositoryProvider).sources();
  final rows = [...fetched.value];
  rows.sort((a, b) => a.sourceName.compareTo(b.sourceName));
  return rows;
});

/// States the delivery guarantee honestly rather than letting a user assume
/// notifications are instant.
class _NotificationTimingNote extends StatelessWidget {
  const _NotificationTimingNote();

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: DuiliaoColors.pending, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '关于通知时效',
                    style: context.texts.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '本 APP 不使用第三方推送，而是定期向服务端拉取事件后弹出本地通知。'
                    'APP 在前台时约每分钟拉取一次；'
                    'iOS 的后台唤醒时机由系统调度，不保证及时，'
                    '打开 APP 会立即拉取一次。',
                    style: context.texts.bodySmall
                        ?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
