/// Jump Code Assistant (jump-code-assistant.html) & Play Catalog (play-catalog.html).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/lottery.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/number_ball.dart';
import 'records_screens.dart';

class JumpCodeAssistantScreen extends StatefulWidget {
  const JumpCodeAssistantScreen({super.key});

  @override
  State<JumpCodeAssistantScreen> createState() =>
      _JumpCodeAssistantScreenState();
}

class _JumpCodeAssistantScreenState extends State<JumpCodeAssistantScreen> {
  Lottery _lottery = Lottery.macau;
  String _period = '2026277';
  String _mode = 'exclude'; // 'include' (正选) or 'exclude' (反选)
  final Set<String> _selected = <String>{};

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

  static const Map<String, List<String>> _groups = {
    '单双': ['单', '双'],
    '大小': ['大', '小'],
    '大小单双': ['大单', '小单', '大双', '小双'],
    '五行': ['金', '木', '水', '火', '土'],
    '波色': ['红波', '蓝波', '绿波'],
    '家野': ['家禽', '野兽'],
    '波色单双': ['红单', '红双', '蓝单', '蓝双', '绿单', '绿双'],
    '生肖': ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'],
    '尾数': [
      '0尾',
      '1尾',
      '2尾',
      '3尾',
      '4尾',
      '5尾',
      '6尾',
      '7尾',
      '8尾',
      '9尾',
      '大尾',
      '小尾',
    ],
    '头数': ['0头', '1头', '2头', '3头', '4头'],
  };

  bool _matchesCondition(int n, String cond) {
    final isOdd = n % 2 == 1;
    final isBig = n >= 25;
    final bose = Lottery2026Lookup.boseForNumber(n); // red / blue / green
    final xiao = Lottery2026Lookup.xiaoForNumber(n);
    final isJia = Lottery2026Lookup.jiaXiao.contains(xiao);
    final wuxing = _wuxingFor(n);
    final tail = n % 10;
    final head = n ~/ 10;

    return switch (cond) {
      '单' => isOdd,
      '双' => !isOdd,
      '大' => isBig,
      '小' => !isBig,
      '大单' => isBig && isOdd,
      '小单' => !isBig && isOdd,
      '大双' => isBig && !isOdd,
      '小双' => !isBig && !isOdd,
      '金' || '木' || '水' || '火' || '土' => wuxing == cond,
      '红波' => bose.contains('红') || bose == 'red',
      '蓝波' => bose.contains('蓝') || bose == 'blue',
      '绿波' => bose.contains('绿') || bose == 'green',
      '家禽' => isJia,
      '野兽' => !isJia,
      '红单' => (bose.contains('红') || bose == 'red') && isOdd,
      '红双' => (bose.contains('红') || bose == 'red') && !isOdd,
      '蓝单' => (bose.contains('蓝') || bose == 'blue') && isOdd,
      '蓝双' => (bose.contains('蓝') || bose == 'blue') && !isOdd,
      '绿单' => (bose.contains('绿') || bose == 'green') && isOdd,
      '绿双' => (bose.contains('绿') || bose == 'green') && !isOdd,
      '鼠' ||
      '牛' ||
      '虎' ||
      '兔' ||
      '龙' ||
      '蛇' ||
      '马' ||
      '羊' ||
      '猴' ||
      '鸡' ||
      '狗' ||
      '猪' => xiao == cond,
      '大尾' => tail >= 5,
      '小尾' => tail < 5,
      _ when cond.endsWith('尾') => '$tail尾' == cond,
      _ when cond.endsWith('头') => '$head头' == cond,
      _ => false,
    };
  }

  bool _keepNumber(int n) {
    if (_selected.isEmpty) return _mode == 'exclude';
    if (_mode == 'exclude') {
      for (final cond in _selected) {
        if (_matchesCondition(n, cond)) return false;
      }
      return true;
    } else {
      for (final entry in _groups.entries) {
        final activeInGroup = entry.value.where(_selected.contains).toList();
        if (activeInGroup.isEmpty) continue;
        final matchesAny = activeInGroup.any((c) => _matchesCondition(n, c));
        if (!matchesAny) return false;
      }
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final kept = <int>[
      for (var n = 1; n <= 49; n++)
        if (_keepNumber(n)) n,
    ];
    final droppedCount = 49 - kept.length;
    final codeText = kept
        .map((n) => n.toString().padLeft(2, '0'))
        .join(' ');
    final keptXiaos =
        kept.map((n) => Lottery2026Lookup.xiaoForNumber(n)).toSet().toList();
    final redCount =
        kept.where((n) => Lottery2026Lookup.boseForNumber(n).contains('红')).length;
    final blueCount =
        kept.where((n) => Lottery2026Lookup.boseForNumber(n).contains('蓝')).length;
    final greenCount =
        kept.where((n) => Lottery2026Lookup.boseForNumber(n).contains('绿')).length;
    final oddCount = kept.where((n) => n % 2 == 1).length;
    final evenCount = kept.length - oddCount;
    final bigCount = kept.where((n) => n >= 25).length;
    final smallCount = kept.length - bigCount;

    final formulaText = _selected.isEmpty
        ? (_mode == 'exclude'
              ? '当前未选择排除条件，保留全部 01–49（49 个号码）'
              : '当前未选择正选条件，请点击上方属性按钮筛选号码')
        : (_mode == 'exclude'
              ? '保留 = 01–49 排除 [${_selected.join('、')}] → 剩余 ${kept.length} 码'
              : '保留 = 满足 [${_selected.join(' · ')}] → 命中 ${kept.length} 码');

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
                title: '跳码助手',
                actions: [
                  GlassIconButton(
                    icon: Icons.menu_book_outlined,
                    tooltip: '玩法目录',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PlayCatalogScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                  children: [
                    // Hero intro card
                    GlassCard(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(15),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '号码组合筛选器',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '支持多属性叠加筛选，实时计算剩余号码、分布结构与复制文本。',
                                  style: context.texts.bodySmall?.copyWith(
                                    fontSize: 11.5,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          GlassStatusPill(
                            label: _mode == 'exclude' ? '反选模式' : '正选模式',
                            color: _mode == 'exclude'
                                ? DuiliaoColors.warning
                                : DuiliaoColors.primaryDark,
                            showDot: true,
                          ),
                        ],
                      ),
                    ),

                    // Lottery & Period & Mode
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in Lottery.all)
                          GlassChipTag(
                            label: item.label,
                            active: item == _lottery,
                            onTap: () => setState(() => _lottery = item),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GlassSegmentedControl<String>(
                      items: const ['2026277', '2026276'],
                      selected: _period,
                      labelBuilder: (p) => '第 $p 期',
                      onChanged: (v) => setState(() => _period = v),
                    ),
                    const SizedBox(height: 10),
                    GlassSegmentedControl<String>(
                      items: const ['include', 'exclude'],
                      selected: _mode,
                      labelBuilder: (m) =>
                          m == 'include' ? '正选号码' : '反选号码',
                      onChanged: (v) => setState(() => _mode = v),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _mode == 'exclude'
                          ? '反选模式：从 01–49 全集中剔除任意命中所选属性的号码。'
                          : '正选模式：同类属性取并集（OR），不同类属性取交集（AND）。',
                      style: context.texts.labelSmall?.copyWith(fontSize: 11),
                    ),

                    // 10 Filter Groups Card
                    const DesignSectionHeader(
                      title: '属性条件',
                      trailingText: '点击多选叠加',
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final entry in _groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: Row(
                                children: [
                                  Text(
                                    entry.key,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _mode == 'exclude' ? '排除项' : '保留项',
                                    style: context.texts.labelSmall?.copyWith(
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GridView.count(
                              crossAxisCount: switch (entry.key) {
                                '单双' || '大小' || '家野' => 2,
                                '波色' => 3,
                                '大小单双' || '生肖' || '尾数' => 4,
                                '五行' || '头数' => 5,
                                '波色单双' => 3,
                                _ => 4,
                              },
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                              childAspectRatio: switch (entry.key) {
                                '单双' || '大小' || '家野' => 3.6,
                                '波色' || '波色单双' => 2.6,
                                _ => 2.1,
                              },
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                for (final val in entry.value)
                                  _FilterOptButton(
                                    label: val,
                                    selected: _selected.contains(val),
                                    isExclude: _mode == 'exclude',
                                    onTap: () => setState(() {
                                      if (_selected.contains(val)) {
                                        _selected.remove(val);
                                      } else {
                                        _selected.add(val);
                                      }
                                    }),
                                  ),
                              ],
                            ),
                            if (entry.key != _groups.keys.last)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Divider(height: 1),
                              ),
                          ],
                        ],
                      ),
                    ),

                    // Result section
                    const DesignSectionHeader(title: '跳码结果'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '当前剩余 ${kept.length} 个号码',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_mode == 'exclude' ? '已排除' : '未保留'} $droppedCount 个 · 占比 ${(kept.length / 49 * 100).toStringAsFixed(1)}%',
                                      style: context.texts.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                              GlassGhostButton(
                                label: '清空',
                                compact: true,
                                onTap: () => setState(_selected.clear),
                              ),
                              const SizedBox(width: 8),
                              GlassGhostButton(
                                label: '复制结果',
                                icon: Icons.copy_rounded,
                                compact: true,
                                onTap: () {
                                  Clipboard.setData(
                                    ClipboardData(text: codeText),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '已复制 ${kept.length} 个号码到剪贴板',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          if (_selected.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final cond in _selected)
                                  ZTag(
                                    label:
                                        '${_mode == 'exclude' ? '排除' : '保留'}: $cond',
                                    variant: _mode == 'exclude'
                                        ? ZTagVariant.primary
                                        : ZTagVariant.hit,
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          GlassSubtleBox(
                            padding: const EdgeInsets.all(12),
                            borderRadius: 12,
                            child: SizedBox(
                              width: double.infinity,
                              child: SelectableText(
                                codeText.isEmpty ? '无符合条件的号码' : codeText,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.55,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 7x7 Ball grid
                          GridView.builder(
                            itemCount: 49,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 7,
                                  mainAxisSpacing: 6,
                                  crossAxisSpacing: 6,
                                  mainAxisExtent: 52,
                                ),
                            itemBuilder: (context, idx) {
                              final numVal = idx + 1;
                              final isKept = _keepNumber(numVal);
                              return Center(
                                child: NumberBall(
                                  number: numVal.toString().padLeft(2, '0'),
                                  bose: Lottery2026Lookup.boseForNumber(numVal),
                                  xiao: Lottery2026Lookup.xiaoForNumber(numVal),
                                  size: 28,
                                  dimmed: !isKept,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          GlassSubtleBox(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 9,
                            ),
                            borderRadius: 10,
                            child: Text(
                              formulaText,
                              style: context.texts.labelSmall?.copyWith(
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Attribute Summary
                    const DesignSectionHeader(title: '属性概览'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(14),
                      child: GridView(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 9,
                              crossAxisSpacing: 9,
                              mainAxisExtent: 68,
                            ),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          GlassSubtleBox(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('保留生肖', style: context.texts.labelSmall),
                                const SizedBox(height: 4),
                                Text(
                                  keptXiaos.isEmpty
                                      ? '无'
                                      : keptXiaos.join(' '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GlassSubtleBox(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('保留波色', style: context.texts.labelSmall),
                                const SizedBox(height: 4),
                                Text(
                                  '红$redCount · 蓝$blueCount · 绿$greenCount',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GlassSubtleBox(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '保留单双 / 大小',
                                  style: context.texts.labelSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '单$oddCount 双$evenCount / 大$bigCount 小$smallCount',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GlassSubtleBox(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('已选条件', style: context.texts.labelSmall),
                                const SizedBox(height: 4),
                                Text(
                                  '${_selected.length} 项 (${_mode == 'exclude' ? '反选' : '正选'})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RecordAddScreen(
                              initialText:
                                  '正码 $codeText 各 10',
                            ),
                          ),
                        );
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded, size: 18),
                          SizedBox(width: 6),
                          Text('将结果带入新增记录'),
                        ],
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
}

class _FilterOptButton extends StatelessWidget {
  const _FilterOptButton({
    required this.label,
    required this.selected,
    required this.isExclude,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isExclude;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isExclude
        ? DuiliaoColors.auroraFuchsia
        : DuiliaoColors.auroraViolet;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      activeColor.withValues(alpha: 0.34),
                      DuiliaoColors.auroraIndigo.withValues(alpha: 0.24),
                    ],
                  )
                : null,
            color: selected
                ? null
                : (isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03)),
            border: Border.all(
              color: selected
                  ? activeColor.withValues(alpha: 0.65)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.08)),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Play Catalog Screen (play-catalog.html).
class PlayCatalogScreen extends StatelessWidget {
  const PlayCatalogScreen({super.key});

  static const _lotteries = [
    ('澳', '澳门', 'macau', '每日 21:30 开奖 · 默认主彩种'),
    ('港', '香港', 'hk', '官方六合彩规则口径 · 49 号码体系'),
    ('台', '台湾', 'taiwan', '同步支持采集、开奖、统计与对照'),
    ('新', '新彩', 'new', '与主流程共用 21 种标准玩法定义'),
  ];

  static const _temaPlays = [
    ('特码', 'tema_n', '01–49 号码', '任一命中特码'),
    ('特肖', 'texiao', '12 生肖', '任一等于特码生肖'),
    ('特码波色', 'tema_bose', '红 / 蓝 / 绿', '任一等于特码波色'),
    ('特码单双', 'tema_odd', '单 / 双', '任一等于特码单双'),
    ('特码大小', 'tema_size', '大 / 小', '25–49 为大'),
    ('特码尾数', 'tema_tail', '0尾–9尾', '等于特码个位'),
    ('特码头数', 'tema_head', '0头–4头', '等于特码十位'),
    ('特码合数', 'tema_heshu', '合单/双/大/小', '十位 + 个位'),
  ];

  static const _zhengPlays = [
    ('平特肖', 'pingte_xiao', '12 生肖', '7 码生肖任一命中'),
    ('平特一肖', 'pingte_1xiao', '单一生肖', '出现在 7 码生肖集合'),
    ('平特尾数', 'pingte_tail', '0尾–9尾', '出现在 7 码尾数集合'),
    ('正码', 'zhengma_n', '01–49 号码', '6 个正码任一/全部'),
  ];

  static const _comboPlays = [
    ('一肖中特 · yixiao_tema'),
    ('家禽野兽 · jiaye'),
    ('天地肖 · tiandi_xiao'),
    ('男女肖 · nannv_xiao'),
    ('五行 · wuxing'),
    ('特码两面 · tema_twoface'),
  ];

  static const _missPlays = [
    ('连肖', 'lianxiao', '2–8 连肖', '全部出现在 7 码生肖中'),
    ('N不中', 'nbuzhong', '5–12 不中', '所选号码全部不出现在 7 码中'),
    ('杀肖', 'shaxiao', '排除生肖', '所杀生肖全部不出现在 7 码中'),
  ];

  @override
  Widget build(BuildContext context) {
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
                title: '彩种与玩法',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                  children: [
                    // Summary Card
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '项目支持目录',
                                      style: context.texts.labelSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      '4 个彩种 · 21 个玩法',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const GlassStatusPill(
                                label: '已同步',
                                color: DuiliaoColors.hit,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '源自 constants.py 与 rules.py 的统一规则表，供采集、多源对照、源评级、AI 研判与我的记录共用。',
                            style: context.texts.bodySmall?.copyWith(
                              fontSize: 11.5,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Lotteries
                    const DesignSectionHeader(
                      title: '彩种 · lottery',
                      trailingText: '4 项',
                    ),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        for (final l in _lotteries)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                BrandLogoBox(
                                  label: l.$1,
                                  size: 36,
                                  borderRadius: 10,
                                  fontSize: 13,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l.$2,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        l.$4,
                                        style: context.texts.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                                GlassChipTag(label: l.$3),
                              ],
                            ),
                          ),
                      ],
                    ),

                    // 特码类 (8)
                    const DesignSectionHeader(
                      title: '特码类 (8)',
                      trailingText: '对照范围：特码',
                    ),
                    _PlayGrid(items: _temaPlays),

                    // 平特与正码 (4)
                    const DesignSectionHeader(
                      title: '平特与正码 (4)',
                      trailingText: '对照范围：6 正码 / 7 码',
                    ),
                    _PlayGrid(items: _zhengPlays),

                    // 组合玩法 (6)
                    const DesignSectionHeader(
                      title: '组合玩法 (6)',
                      trailingText: '属性 / 两面 / 五行',
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final c in _comboPlays)
                                GlassChipTag(label: c),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '一肖中特：所选生肖在 6 正码或特码中命中均可结算；特码两面支持大单、大双、小单、小双、合单、合双等复合判定。',
                            style: context.texts.labelSmall?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 不中与杀号 (3)
                    const DesignSectionHeader(
                      title: '不中与杀号 (3)',
                      trailingText: '复试 / 全不中判定',
                    ),
                    _PlayGrid(items: _missPlays),
                    const SizedBox(height: 10),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '录入联动说明',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '新增记录支持号码单式、连肖复试与 N 不中三种专用录入视图。',
                                  style: context.texts.labelSmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          GlassStatusPill(
                            label: '规则完备',
                            color: Theme.of(context).colorScheme.primary,
                            showDot: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('返回新增记录'),
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
}

class _PlayGrid extends StatelessWidget {
  const _PlayGrid({required this.items});
  final List<(String, String, String, String)> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: 74,
      ),
      itemBuilder: (context, idx) {
        final item = items[idx];
        return GlassSubtleBox(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      item.$1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    item.$2,
                    style: context.texts.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              Text(
                '${item.$3} · ${item.$4}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelSmall?.copyWith(fontSize: 10.5),
              ),
            ],
          ),
        );
      },
    );
  }
}
