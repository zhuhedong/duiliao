/// Native counterparts for the secondary screens shown in app-design.
///
/// These screens deliberately share the same glass primitives and real
/// repositories as the primary tabs. They are small, focused entry points so
/// an operator can reach every designed workflow without opening the web
/// prototype.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/consensus.dart';
import '../../domain/models/prediction.dart';
import '../../domain/models/source.dart';
import '../../domain/models/ratings.dart';
import '../../domain/play_type.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import '../auth/auth_providers.dart';
import '../comparison/comparison_screen.dart';
import '../consensus/consensus_screen.dart';

class SourceCatalogScreen extends ConsumerStatefulWidget {
  const SourceCatalogScreen({super.key});

  @override
  ConsumerState<SourceCatalogScreen> createState() =>
      _SourceCatalogScreenState();
}

class _SourceCatalogScreenState extends ConsumerState<SourceCatalogScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sourceCatalogProvider);
    return _DesignScaffold(
      title: '数据源采集',
      subtitle: '目录、启用状态与现场试跑',
      child: AsyncView<List<CollectorSource>>(
        value: async,
        loading: const SkeletonList(itemHeight: 106),
        onRetry: () => ref.invalidate(sourceCatalogProvider),
        emptyCheck: (items) => items.isEmpty,
        emptyMessage: '暂无可用数据源',
        builder: (items) {
          final filtered = items.where((item) => item.matches(_query)).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
            children: [
              TextField(
                decoration: const InputDecoration(
                  hintText: '搜索源名称、ID 或站族',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
              const SizedBox(height: 12),
              _MetricStrip(
                items: [
                  ('总源', '${items.length}', context.colors.primary),
                  (
                    '启用',
                    '${items.where((item) => item.enabled).length}',
                    DuiliaoColors.hit,
                  ),
                  (
                    '异常',
                    '${items.where((item) => item.isBroken).length}',
                    DuiliaoColors.miss,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final source in filtered) _SourceTile(source: source),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('没有匹配的数据源')),
                ),
            ],
          );
        },
      ),
    );
  }
}

final sourceCatalogProvider = FutureProvider<List<CollectorSource>>(
  (ref) async => (await ref.read(collectorRepositoryProvider).sources()).value,
);

class _SourceTile extends ConsumerWidget {
  const _SourceTile({required this.source});
  final CollectorSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = source.isBroken
        ? DuiliaoColors.miss
        : source.enabled
        ? DuiliaoColors.hit
        : DuiliaoColors.pending;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      onTap: () async {
        if (!ref.read(canOperateProvider) || source.sourceId.isEmpty) return;
        try {
          final result = await ref
              .read(collectorRepositoryProvider)
              .testSource(
                sourceId: source.sourceId,
                lottery: source.lottery.isEmpty ? 'macau' : source.lottery,
              );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${source.sourceName}：${result.ok ? '试跑成功' : result.errorMsg ?? '试跑失败'}',
                ),
              ),
            );
          }
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('试跑失败：$error')));
          }
        }
      },
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: Icon(
              source.isBroken ? Icons.warning_amber_rounded : Icons.public,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.sourceName.isEmpty
                      ? source.sourceId
                      : source.sourceName,
                  style: context.texts.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '${Lottery.labelFor(source.lottery)} · ${PlayTypes.labelFor(source.playType)} · ${source.siteFamily}',
                  style: context.texts.bodySmall,
                ),
              ],
            ),
          ),
          GlassBadge(
            label: source.isBroken
                ? '异常'
                : source.enabled
                ? '启用'
                : '停用',
            color: color,
          ),
        ],
      ),
    );
  }
}

class MonitorScreen extends ConsumerWidget {
  const MonitorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lottery = ref.watch(selectedLotteryProvider);
    final async = ref.watch(monitorProvider(lottery.code));
    return _DesignScaffold(
      title: '服务监控',
      subtitle: '采集源延迟与待判队列',
      child: AsyncView<List<MonitorRow>>(
        value: async,
        loading: const SkeletonList(itemHeight: 94),
        onRetry: () => ref.invalidate(monitorProvider(lottery.code)),
        emptyCheck: (items) => items.isEmpty,
        emptyMessage: '暂无监控数据',
        builder: (items) => ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [for (final item in items) _MonitorTile(row: item)],
        ),
      ),
    );
  }
}

final monitorProvider = FutureProvider.family<List<MonitorRow>, String>((
  ref,
  lottery,
) async {
  return (await ref.read(collectorRepositoryProvider).monitor(lottery: lottery))
      .value;
});

class _MonitorTile extends StatelessWidget {
  const _MonitorTile({required this.row});
  final MonitorRow row;

  @override
  Widget build(BuildContext context) {
    final color = (row.neverCollected || row.isStale)
        ? DuiliaoColors.warning
        : DuiliaoColors.hit;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(row.sourceName, style: context.texts.titleSmall),
              ),
              GlassBadge(
                label: row.neverCollected
                    ? '未采集'
                    : row.isStale
                    ? '延迟'
                    : '正常',
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '最新 ${row.latestPeriod ?? '—'}',
                style: context.texts.bodySmall,
              ),
              const Spacer(),
              Text('待判 ${row.pendingTotal}', style: context.texts.bodySmall),
              const SizedBox(width: 12),
              Text('已判 ${row.confirmedTotal}', style: context.texts.bodySmall),
            ],
          ),
          if (row.lastSeen != null) ...[
            const SizedBox(height: 4),
            Text('最近：${row.lastSeen}', style: context.texts.labelSmall),
          ],
        ],
      ),
    );
  }
}

class ConsensusBoardScreen extends ConsumerWidget {
  const ConsensusBoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lottery = ref.watch(selectedLotteryProvider);
    final latest = ref.watch(latestPeriodProvider(lottery));
    return _DesignScaffold(
      title: '共识排行榜',
      subtitle: '多源去重 · 支持证据 · 官方核验',
      child: latest.when(
        loading: () => const SkeletonList(itemHeight: 120),
        error: (error, _) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(latestPeriodProvider(lottery)),
        ),
        data: (period) {
          if (period == null) return const EmptyState(message: '暂无可用期号');
          final playType = ref.watch(selectedPlayTypeProvider);
          final key = (lottery: lottery, period: period, playType: playType);
          final async = ref.watch(consensusProvider(key));
          return AsyncView<
            ({ConsensusResult result, bool isStale, String? storedAt})
          >(
            value: async,
            loading: const SkeletonList(itemHeight: 120),
            onRetry: () => ref.invalidate(consensusProvider(key)),
            builder: (data) => _ConsensusBoardBody(
              result: data.result,
              period: period,
              stale: data.isStale,
            ),
          );
        },
      ),
    );
  }
}

class _ConsensusBoardBody extends StatelessWidget {
  const _ConsensusBoardBody({
    required this.result,
    required this.period,
    required this.stale,
  });

  final ConsensusResult result;
  final String period;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final numberLeader = result.temaTallies.isEmpty
        ? null
        : result.temaTallies.first;
    final zodiacLeader = result.texiaoTallies.isEmpty
        ? null
        : result.texiaoTallies.first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
      children: [
        if (stale)
          const Align(
            alignment: Alignment.centerLeft,
            child: GlassBadge(label: '离线缓存', color: DuiliaoColors.pending),
          ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '第 $period 期共识结论',
                      style: context.texts.titleMedium,
                    ),
                  ),
                  GlassBadge(
                    label: result.isDrawn ? '已核验' : '待开奖',
                    color: result.isDrawn
                        ? DuiliaoColors.hit
                        : DuiliaoColors.warning,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _LeaderCard(label: '领跑特码', item: numberLeader),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LeaderCard(label: '领跑特肖', item: zodiacLeader),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (result.temaTallies.isNotEmpty)
          _ConsensusRankList(title: '特码候选榜', items: result.temaTallies),
        if (result.texiaoTallies.isNotEmpty)
          _ConsensusRankList(title: '特肖候选榜', items: result.texiaoTallies),
        if (result.sortedGroups.isNotEmpty) ...[
          const SectionHeader(title: '玩法组共识', subtitle: '按来源组票数排序'),
          for (final group in result.sortedGroups.take(8))
            GlassCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          PlayTypes.labelFor(group.playType),
                          style: context.texts.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          group.leader == null
                              ? '暂无领跑项'
                              : formatAtoms(group.leader!),
                          style: context.texts.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${group.leaderVotes} 票',
                    style: context.texts.labelLarge,
                  ),
                ],
              ),
            ),
        ],
        if (result.temaTallies.isEmpty &&
            result.texiaoTallies.isEmpty &&
            result.groups.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: EmptyState(message: '本期暂无共识数据'),
          ),
      ],
    );
  }
}

class _LeaderCard extends StatelessWidget {
  const _LeaderCard({required this.label, required this.item});
  final String label;
  final AtomTallyItem? item;

  @override
  Widget build(BuildContext context) => GlassContainer(
    borderRadius: BorderRadius.circular(16),
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.texts.labelSmall),
        const SizedBox(height: 6),
        Text(item?.value ?? '—', style: context.texts.headlineSmall),
        Text(
          item == null
              ? '暂无票数'
              : '${item!.votes} 票 · ${item!.percentage.toStringAsFixed(1)}%',
          style: context.texts.labelSmall,
        ),
      ],
    ),
  );
}

class _ConsensusRankList extends StatelessWidget {
  const _ConsensusRankList({required this.title, required this.items});
  final String title;
  final List<AtomTallyItem> items;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeader(title: title, subtitle: '按来源组计票'),
      for (var i = 0; i < items.length && i < 10; i++)
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(width: 26, child: Text('${i + 1}')),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(items[i].value, style: context.texts.titleSmall),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: items[i].barFraction),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text('${items[i].votes} 票', style: context.texts.labelLarge),
            ],
          ),
        ),
    ],
  );
}

class PlayCatalogScreen extends StatelessWidget {
  const PlayCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _DesignScaffold(
      title: '彩种与玩法',
      subtitle: '21 种玩法规则目录',
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          for (final entry in PlayTypes.grouped.entries) ...[
            SectionHeader(
              title: entry.key.label,
              subtitle: '${entry.value.length} 种玩法',
            ),
            for (final play in entry.value)
              GlassCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(play.name, style: context.texts.titleSmall),
                    ),
                    Text(play.key, style: context.texts.labelSmall),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _DesignScaffold(
      title: '记录',
      subtitle: '投注记录与玩法工具',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('我的记录', style: context.texts.titleMedium),
                const SizedBox(height: 6),
                Text(
                  '记录保存接口将在运营端开放后同步；当前可先使用跳码助手和玩法目录。',
                  style: context.texts.bodySmall,
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RecordAddScreen()),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('新增记录'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _ActionTile(
            icon: Icons.auto_awesome_motion,
            title: '跳码助手',
            detail: '按生肖、波色、五行和大小单双组合筛选号码',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const JumpCodeAssistantScreen(),
              ),
            ),
          ),
          _ActionTile(
            icon: Icons.menu_book_outlined,
            title: '玩法目录',
            detail: '浏览 21 种玩法的适用范围与规则',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlayCatalogScreen()),
            ),
          ),
          _ActionTile(
            icon: Icons.bar_chart_outlined,
            title: '记录统计',
            detail: '查看命中、未中和窗口趋势',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecordStatsScreen()),
            ),
          ),
          _ActionTile(
            icon: Icons.playlist_add,
            title: '连肖复试',
            detail: '按生肖组合创建复试记录',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const RecordAddScreen(mode: '连肖复试'),
              ),
            ),
          ),
          _ActionTile(
            icon: Icons.block,
            title: '不中码',
            detail: '按排除号码创建不中码记录',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const RecordAddScreen(mode: '不中码'),
              ),
            ),
          ),
          _ActionTile(
            icon: Icons.receipt_long,
            title: '记录详情',
            detail: '查看已保存记录的期号、玩法与判定',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecordDetailScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class RecordAddScreen extends StatefulWidget {
  const RecordAddScreen({super.key, this.mode = '号码单式'});
  final String mode;

  @override
  State<RecordAddScreen> createState() => _RecordAddScreenState();
}

class _RecordAddScreenState extends State<RecordAddScreen> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DesignScaffold(
    title: '新增记录 · ${widget.mode}',
    subtitle: '记录草稿只在确认后提交',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('记录参数', style: context.texts.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: widget.mode == '不中码' ? '排除号码' : '选择号码',
                  hintText: '例如 01, 08, 26',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Lottery>(
                initialValue: Lottery.macau,
                decoration: const InputDecoration(labelText: '彩种'),
                items: [
                  for (final lottery in Lottery.all)
                    DropdownMenuItem(
                      value: lottery,
                      child: Text(lottery.label),
                    ),
                ],
                onChanged: (_) {},
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _toast(
                  context,
                  _controller.text.trim().isEmpty ? '请先填写号码' : '记录草稿已保存',
                ),
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存记录'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class RecordStatsScreen extends StatelessWidget {
  const RecordStatsScreen({super.key});
  @override
  Widget build(BuildContext context) => _DesignScaffold(
    title: '记录统计',
    subtitle: '命中趋势与窗口表现',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('尚未有可结算记录', style: context.texts.titleMedium),
              const SizedBox(height: 6),
              Text(
                '新增记录并完成开奖判定后，这里会展示命中率、连中和连挂。',
                style: context.texts.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _MetricStrip(
          items: [
            ('命中率', '—', DuiliaoColors.pending),
            ('已结算', '0', DuiliaoColors.pending),
            ('当前连中', '—', DuiliaoColors.pending),
          ],
        ),
      ],
    ),
  );
}

class RecordDetailScreen extends StatelessWidget {
  const RecordDetailScreen({super.key});
  @override
  Widget build(BuildContext context) => _DesignScaffold(
    title: '记录详情',
    subtitle: '记录流水与判定证据',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('暂无已保存记录', style: context.texts.titleMedium),
                  ),
                  const Icon(Icons.hourglass_empty),
                ],
              ),
              const SizedBox(height: 8),
              Text('保存记录后，开奖详情、命中状态和证据会在这里聚合。', style: context.texts.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

class JumpCodeAssistantScreen extends StatefulWidget {
  const JumpCodeAssistantScreen({super.key});
  @override
  State<JumpCodeAssistantScreen> createState() =>
      _JumpCodeAssistantScreenState();
}

class _JumpCodeAssistantScreenState extends State<JumpCodeAssistantScreen> {
  final Set<String> _selected = {};
  final _groups = const {
    '波色': ['红', '蓝', '绿'],
    '大小': ['大', '小'],
    '单双': ['单', '双'],
    '生肖': ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'],
    '五行': ['金', '木', '水', '火', '土'],
  };

  @override
  Widget build(BuildContext context) {
    return _DesignScaffold(
      title: '跳码助手',
      subtitle: '组合属性筛选 01–49',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          for (final entry in _groups.entries) ...[
            SectionHeader(title: entry.key),
            GlassCard(
              padding: const EdgeInsets.all(10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in entry.value)
                    FilterChip(
                      label: Text(value),
                      selected: _selected.contains(value),
                      onSelected: (yes) => setState(
                        () => yes
                            ? _selected.add(value)
                            : _selected.remove(value),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('清空'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _toast(
                    context,
                    _selected.isEmpty
                        ? '请选择至少一个属性'
                        : '已选 ${_selected.length} 个条件',
                  ),
                  icon: const Icon(Icons.copy),
                  label: const Text('应用筛选'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SystemSettingsScreen extends ConsumerWidget {
  const SystemSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(displayPreferencesProvider);
    return _DesignScaffold(
      title: '系统设置',
      subtitle: '连接、显示与本地维护',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        children: [
          GlassCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('主题'),
                  subtitle: Text(preferences.themeMode.name),
                  trailing: const Icon(Icons.chevron_right),
                ),
                ListTile(
                  leading: const Icon(Icons.text_fields),
                  title: const Text('字号'),
                  subtitle: Text('${(preferences.textScale * 100).round()}%'),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          GlassCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('服务连接'),
                  subtitle: Text(ref.read(appConfigProvider).displayHost),
                ),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('清理离线缓存'),
                  onTap: () async {
                    await ref.read(collectorRepositoryProvider).clearCache();
                    if (context.mounted) _toast(context, '缓存已清理');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesignScaffold extends StatelessWidget {
  const _DesignScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          Text(subtitle, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
      backgroundColor: Colors.transparent,
    ),
    body: GlassBackground(child: child),
  );
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.items});
  final List<(String, String, Color)> items;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < items.length; i++)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == items.length - 1 ? 0 : 8),
            child: GlassCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(items[i].$1, style: context.texts.labelSmall),
                  const SizedBox(height: 3),
                  Text(
                    items[i].$2,
                    style: context.texts.titleLarge?.copyWith(
                      color: items[i].$3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GlassCard(
    onTap: onTap,
    child: Row(
      children: [
        Icon(icon, color: context.colors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.texts.titleSmall),
              const SizedBox(height: 3),
              Text(detail, style: context.texts.bodySmall),
            ],
          ),
        ),
        const Icon(Icons.chevron_right),
      ],
    ),
  );
}

void _toast(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
