/// 01–49 attribute encyclopedia, with a multi-dimension reverse lookup.
///
/// Attributes split into two classes, which the UI must keep distinguishable:
/// fixed ones (波色/大小/单双/头/尾/合数) never change, while 生肖/家野/五行 rotate with
/// the lunar year. That is why the whole screen is keyed by a **date** — pick a
/// date either side of 春节 and the zodiac mapping differs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/models/draw.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import '../../ui/widgets/number_ball.dart';

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Selected date for the attribute table.
final numbersDateProvider = NotifierProvider<NumbersDate, String>(NumbersDate.new);

class NumbersDate extends Notifier<String> {
  @override
  String build() => _formatDate(DateTime.now());
  void set(DateTime date) => state = _formatDate(date);
}

final numbersProvider = FutureProvider.family<
    ({NumbersResult result, bool isStale, String? storedAt}), String>(
  (ref, date) async {
    final fetched =
        await ref.read(collectorRepositoryProvider).numbers(date: date);
    return (
      result: fetched.value,
      isStale: fetched.isStale,
      storedAt: fetched.storedAtLabel,
    );
  },
);

/// Active reverse-lookup filters: attribute name -> accepted values.
@immutable
class NumberFilters {
  const NumberFilters({this.selections = const {}});

  final Map<String, Set<String>> selections;

  bool get isEmpty => selections.values.every((v) => v.isEmpty);

  Set<String> valuesFor(String key) => selections[key] ?? const {};

  NumberFilters toggle(String key, String value) {
    final next = {
      for (final entry in selections.entries) entry.key: {...entry.value},
    };
    final bucket = next.putIfAbsent(key, () => <String>{});
    if (!bucket.remove(value)) bucket.add(value);
    return NumberFilters(selections: next);
  }

  NumberFilters cleared() => const NumberFilters();

  /// A number matches when, for every active dimension, its value is one of the
  /// selected ones. Within a dimension the selections are OR'd; across
  /// dimensions they are AND'd — so "绿波 + 大 + 双" narrows rather than widens.
  bool matches(NumberAttr attr) {
    for (final entry in selections.entries) {
      if (entry.value.isEmpty) continue;
      final actual = _valueOf(attr, entry.key);
      if (actual == null || !entry.value.contains(actual)) return false;
    }
    return true;
  }

  static String? _valueOf(NumberAttr attr, String key) => switch (key) {
        'bose' => attr.bose,
        'size' => attr.size,
        'odd' => attr.odd,
        'head' => attr.head,
        'wei' => attr.wei,
        'sum' => attr.sum,
        'jiaye' => attr.jiaye,
        'gender' => attr.gender,
        'tianDi' => attr.tianDi,
        'yinYang' => attr.yinYang,
        'luck' => attr.luck,
        'season' => attr.season,
        'direction' => attr.direction,
        'xiao' => attr.xiao,
        'wuxing' => attr.wuxing,
        _ => null,
      };
}

final numberFiltersProvider =
    NotifierProvider<NumberFiltersController, NumberFilters>(
  NumberFiltersController.new,
);

class NumberFiltersController extends Notifier<NumberFilters> {
  @override
  NumberFilters build() => const NumberFilters();
  void toggle(String key, String value) => state = state.toggle(key, value);
  void clear() => state = state.cleared();
}

class NumbersScreen extends ConsumerStatefulWidget {
  const NumbersScreen({super.key});

  @override
  ConsumerState<NumbersScreen> createState() => _NumbersScreenState();
}

class _NumbersScreenState extends ConsumerState<NumbersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _gridView = true;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final date = ref.watch(numbersDateProvider);
    final async = ref.watch(numbersProvider(date));

    return Scaffold(
      appBar: AppBar(
        title: const Text('号码属性'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: '属性总表'), Tab(text: '属性反查')],
        ),
        actions: [
          if (_tabs.index == 0)
            IconButton(
              tooltip: _gridView ? '切换列表' : '切换网格',
              icon: Icon(_gridView ? Icons.view_list : Icons.grid_view),
              onPressed: () => setState(() => _gridView = !_gridView),
            ),
          IconButton(
            tooltip: '选择日期',
            icon: const Icon(Icons.calendar_today),
            onPressed: _pickDate,
          ),
        ],
      ),
      body: AsyncView<({NumbersResult result, bool isStale, String? storedAt})>(
        value: async,
        loading: const SkeletonList(itemHeight: 60),
        onRetry: () => ref.invalidate(numbersProvider(date)),
        builder: (data) => Column(
          children: [
            if (data.isStale)
              OfflineBanner(
                storedAtLabel: data.storedAt,
                onRetry: () => ref.invalidate(numbersProvider(date)),
              ),
            _DateBar(date: data.result.date, onPick: _pickDate),
            if (!data.result.wuxingAvailable)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                // Stated explicitly: otherwise blank 五行 cells look like a bug.
                child: WarningNote(
                  message: '该年份无权威五行表，五行属性不可用'
                      '${data.result.wuxingYears.isEmpty ? '' : '（有表年份：'
                          '${data.result.wuxingYears.join('、')}）'}',
                  icon: Icons.info_outline,
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _AttributeTable(result: data.result, grid: _gridView),
                  _ReverseLookup(result: data.result),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final current = DateTime.tryParse(ref.read(numbersDateProvider)) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      // Wide enough to inspect any year the seeded attribute table covers.
      firstDate: DateTime(2000),
      lastDate: DateTime(2040, 12, 31),
      helpText: '选择日期（生肖随农历年轮转）',
    );
    if (picked == null) return;
    ref.read(numbersDateProvider.notifier).set(picked);
  }
}

class _DateBar extends StatelessWidget {
  const _DateBar({required this.date, required this.onPick});

  final String date;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.event, size: 16),
            const SizedBox(width: 6),
            Text('按 $date 计算', style: context.texts.bodyMedium),
            const Spacer(),
            TextButton(onPressed: onPick, child: const Text('更换日期')),
          ],
        ),
      );
}

class _AttributeTable extends StatelessWidget {
  const _AttributeTable({required this.result, required this.grid});

  final NumbersResult result;
  final bool grid;

  @override
  Widget build(BuildContext context) {
    if (result.items.isEmpty) {
      return const EmptyState(message: '暂无号码属性数据');
    }
    if (grid) {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 76,
          childAspectRatio: 0.72,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: result.items.length,
        itemBuilder: (context, index) {
          final attr = result.items[index];
          return InkWell(
            onTap: () => _showDetail(context, attr),
            borderRadius: BorderRadius.circular(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NumberBall(number: attr.num, attr: attr, size: 38),
                const SizedBox(height: 2),
                Text(attr.xiao, style: context.texts.labelSmall),
              ],
            ),
          );
        },
      );
    }
    return ListView.separated(
      itemCount: result.items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final attr = result.items[index];
        return ListTile(
          leading: NumberBall(
            number: attr.num,
            attr: attr,
            size: 36,
            showColorName: false,
          ),
          title: Text('${attr.xiao} · ${attr.bose} · ${attr.size}${attr.odd}'),
          subtitle: Text(
            '头${attr.head} 尾${attr.wei} 合${attr.sum} ${attr.jiaye}'
            '${attr.wuxing == null ? '' : ' 五行${attr.wuxing}'}',
          ),
          onTap: () => _showDetail(context, attr),
        );
      },
    );
  }

  void _showDetail(BuildContext context, NumberAttr attr) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _NumberDetailSheet(attr: attr),
    );
  }
}

class _NumberDetailSheet extends StatelessWidget {
  const _NumberDetailSheet({required this.attr});

  final NumberAttr attr;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NumberBall(number: attr.num, attr: attr, size: 52),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${attr.num} 号', style: context.texts.titleLarge),
                  Text(
                    '${attr.xiao} · ${attr.bose}',
                    style: context.texts.bodyMedium
                        ?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 24),
          // Fixed attributes first: these never change, so they are the stable
          // reference an operator can rely on regardless of date.
          _Group(
            title: '固定属性',
            subtitle: '不随年份变化',
            entries: {
              '波色': attr.bose,
              '大小': attr.size,
              '单双': attr.odd,
              '头数': attr.head,
              '尾数': attr.wei,
              '合数单双': attr.sum,
              '半波': attr.halfwave,
            },
          ),
          _Group(
            title: '年度属性',
            subtitle: '随农历年轮转',
            entries: {
              '生肖': attr.xiao,
              '家野': attr.jiaye,
              '五行': attr.wuxing ?? '该年份无权威五行表',
            },
          ),
          _Group(
            title: '2026 灵码',
            entries: {
              '称谓': attr.role,
              '花': attr.flower,
              '时辰': attr.hour,
              '地支': attr.dizhi,
              '生肖色': attr.xiaoColor,
              '笔画': attr.stroke,
            },
          ),
          _Group(
            title: '生肖分类',
            entries: {
              '天地肖': attr.tianDi,
              '阴阳肖': attr.yinYang,
              '男女肖': attr.gender,
              '吉凶肖': attr.luck,
              '季节': attr.season,
              '方位': attr.direction,
            },
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.entries, this.subtitle});

  final String title;
  final String? subtitle;
  final Map<String, String?> entries;

  @override
  Widget build(BuildContext context) {
    final present = entries.entries.where((e) => e.value != null && e.value!.isNotEmpty);
    if (present.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: context.texts.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: 6),
                Text(
                  subtitle!,
                  style: context.texts.labelSmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in present)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${entry.key} ${entry.value}',
                      style: context.texts.labelMedium),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Multi-dimension filter with a live match count.
class _ReverseLookup extends ConsumerWidget {
  const _ReverseLookup({required this.result});

  final NumbersResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(numberFiltersProvider);
    final controller = ref.read(numberFiltersProvider.notifier);
    final matched = result.items.where(filters.matches).toList();

    // Dimensions are built from the actual data, so a value that never occurs is
    // never offered as a filter.
    final dimensions = <String, ({String label, List<String> values})>{
      'bose': (label: '波色', values: _distinct(result, (a) => a.bose)),
      'size': (label: '大小', values: _distinct(result, (a) => a.size)),
      'odd': (label: '单双', values: _distinct(result, (a) => a.odd)),
      'head': (label: '头数', values: _distinct(result, (a) => a.head)),
      'wei': (label: '尾数', values: _distinct(result, (a) => a.wei)),
      'sum': (label: '合数单双', values: _distinct(result, (a) => a.sum)),
      'jiaye': (label: '家野', values: _distinct(result, (a) => a.jiaye)),
      'gender': (label: '男女肖', values: _ordered(result, (a) => a.gender, const ['男肖', '女肖'])),
      'tianDi': (label: '天地肖', values: _ordered(result, (a) => a.tianDi, const ['天肖', '地肖'])),
      'yinYang': (label: '阴阳肖', values: _ordered(result, (a) => a.yinYang, const ['阳肖', '阴肖'])),
      'luck': (label: '吉凶肖', values: _ordered(result, (a) => a.luck, const ['吉肖', '凶肖'])),
      'season': (label: '季节', values: _ordered(result, (a) => a.season, const ['春', '夏', '秋', '冬'])),
      'direction': (label: '方位', values: _ordered(result, (a) => a.direction, const ['东', '南', '西', '北'])),
      'xiao': (label: '生肖', values: _distinct(result, (a) => a.xiao)),
      if (result.wuxingAvailable)
        'wuxing': (label: '五行', values: _distinct(result, (a) => a.wuxing)),
    };

    return Column(
      children: [
        Material(
          color: context.colors.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text(
                  '命中 ${matched.length} 个号码',
                  style: context.texts.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (!filters.isEmpty)
                  TextButton(
                    onPressed: controller.clear,
                    child: const Text('清除条件'),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: matched.isEmpty
                    ? Text(
                        '没有号码同时满足所有条件',
                        style: TextStyle(color: context.colors.error),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final attr in matched)
                            NumberBall(
                              number: attr.num,
                              attr: attr,
                              size: 36,
                              showColorName: false,
                            ),
                        ],
                      ),
              ),
              const Divider(),
              for (final entry in dimensions.entries)
                if (entry.value.values.isNotEmpty)
                  _FilterRow(
                    label: entry.value.label,
                    values: entry.value.values,
                    selected: filters.valuesFor(entry.key),
                    onToggle: (value) => controller.toggle(entry.key, value),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  static List<String> _distinct(
    NumbersResult result,
    String? Function(NumberAttr) pick,
  ) {
    final values = result.items.map(pick).whereType<String>().toSet().toList();
    values.sort();
    return values;
  }

  static List<String> _ordered(
    NumbersResult result,
    String? Function(NumberAttr) pick,
    List<String> order,
  ) {
    final present = result.items.map(pick).whereType<String>().toSet();
    if (present.isEmpty) return const [];
    return order.where(present.contains).toList();
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.values,
    required this.selected,
    required this.onToggle,
  });

  final String label;
  final List<String> values;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.texts.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final value in values)
                FilterChip(
                  label: Text(value),
                  selected: selected.contains(value),
                  onSelected: (_) => onToggle(value),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
