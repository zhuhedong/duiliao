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
      appBar: AppBar(title: const Text('玩法规则')),
      body: RefreshIndicator(
        onRefresh: () async {
          // Pull-to-refresh bypasses the cache, which otherwise holds rules for
          // seven days.
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
            // Preserve the server's ordering within each scope: rules.py lists
            // them in a deliberate sequence.
            final grouped = <String, List<RuleRow>>{};
            for (final rule in data.rules) {
              grouped.putIfAbsent(rule.scope, () => []).add(rule);
            }
            final version = data.rules.first.version;
            final drifted = version != kTranscribedRuleVersion;

            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
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
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '共 ${data.rules.length} 种玩法 · 规则版本 $version',
                        style: context.texts.bodySmall
                            ?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        // Explains why an old judgement may not match today's rules.
                        '每条判定结果都会记录当时使用的规则版本，'
                        '在对照页的判定证据中可以查看。',
                        style: context.texts.bodySmall
                            ?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
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
    // Two of the 21 plays are configurable per source (any vs all); the rest are
    // fixed. Flagging the configurable ones matters because the same prediction
    // can be judged differently depending on the source's hit_mode.
    final configurable = rule.modes.contains('任一或全部');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    rule.name,
                    style: context.texts.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  rule.playType,
                  style: context.texts.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(rule.condition, style: context.texts.bodyMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                StatusChip(
                  label: configurable ? '可配置 任一/全部' : '固定判定',
                  color: configurable
                      ? DuiliaoColors.warning
                      : context.colors.onSurfaceVariant,
                  icon: configurable ? Icons.tune : Icons.lock_outline,
                  compact: true,
                ),
                const SizedBox(width: 8),
                Text(
                  '接受类型：'
                  '${(PlayTypes.tryParse(rule.playType)?.allowedKinds ?? const [])
                      .map(PlayTypes.kindLabel)
                      .join('、')}',
                  style: context.texts.labelSmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
