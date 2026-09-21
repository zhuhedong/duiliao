/// Play-rule encyclopedia, grouped by scope.
///
/// The server's `/collector/rules` response is the authority. The client also
/// carries a transcribed copy for offline pickers, so this screen compares the
/// two and says so when they disagree — a client running against a newer
/// `rules.py` would otherwise silently mislabel play types.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/models/source.dart';
import '../../domain/play_type.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';

final rulesProvider = FutureProvider<
    ({List<RuleRow> rules, bool isStale, String? storedAt})>((ref) async {
  final fetched = await ref.read(collectorRepositoryProvider).rules();
  return (
    rules: fetched.value,
    isStale: fetched.isStale,
    storedAt: fetched.storedAtLabel,
  );
});

class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rulesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('玩法规则'),
        backgroundColor: Colors.transparent,
      ),
      body: GlassBackground(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(collectorRepositoryProvider).rules(forceRefresh: true);
            ref.invalidate(rulesProvider);
          },
          child: AsyncView<({List<RuleRow> rules, bool isStale, String? storedAt})>(
            value: async,
            loading: const SkeletonList(itemHeight: 80),
            onRetry: () => ref.invalidate(rulesProvider),
            emptyCheck: (data) => data.rules.isEmpty,
            emptyMessage: '未获取到玩法规则',
            builder: (data) {
              final grouped = <String, List<RuleRow>>{};
              for (final rule in data.rules) {
                grouped.putIfAbsent(rule.scope, () => []).add(rule);
              }
              final version = data.rules.first.version;
              final drifted = version != kTranscribedRuleVersion;

              return ListView(
                padding: const EdgeInsets.only(top: 6, bottom: 96),
                children: [
                  if (data.isStale)
                    OfflineBanner(
                      storedAtLabel: data.storedAt,
                      onRetry: () => ref.invalidate(rulesProvider),
                    ),
                  if (drifted)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: WarningNote(
                        message: '服务端规则版本为 $version，'
                            '本 APP 内置对照表为 $kTranscribedRuleVersion，'
                            '部分玩法名称可能不一致，建议更新 APP',
                        icon: Icons.sync_problem,
                      ),
                    ),
                  for (final entry in grouped.entries) ...[
                    SectionHeader(
                      title: entry.key,
                      subtitle: '${entry.value.length} 种玩法',
                    ),
                    for (final rule in entry.value) _RuleCard(rule: rule),
                  ],
                  GlassCard(
                    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '共 ${data.rules.length} 种玩法 · 规则版本 $version',
                          style: context.texts.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '每条判定结果都会记录当时使用的规则版本，在对照页的判定证据中可以查看。',
                          style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule});

  final RuleRow rule;

  @override
  Widget build(BuildContext context) {
    final configurable = rule.modes.contains('任一或全部');
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rule.name,
                  style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: context.colors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  rule.playType,
                  style: context.texts.labelSmall?.copyWith(
                    color: context.colors.primary,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Text(rule.condition, style: context.texts.bodyMedium),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              GlassBadge(
                label: configurable ? '可配置 任一/全部' : '固定判定',
                color: configurable
                    ? DuiliaoColors.warning
                    : context.colors.primary,
                icon: configurable ? Icons.tune_rounded : Icons.lock_outline_rounded,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '接受类型：'
                  '${(PlayTypes.tryParse(rule.playType)?.allowedKinds ?? const [])
                      .map(PlayTypes.kindLabel)
                      .join('、')}',
                  style: context.texts.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
