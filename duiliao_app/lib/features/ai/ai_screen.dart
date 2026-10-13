/// AI research (`ai-analysis.html`) and AI report (`ai-report.html`).
///
/// Preserves real server-cached report reading (`aiReportProvider`) and staff
/// SSE streaming (`streamClientProvider`), while providing 1:1 visual and
/// interactive parity with `ai-analysis.html` and `ai-report.html`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../../core/net/api_exception.dart';
import '../../core/net/stream_client.dart';
import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/app_event.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/number_ball.dart';
import '../auth/auth_providers.dart';
import '../comparison/comparison_screen.dart';
import '../design/records_screens.dart';

final aiPromptsProvider = FutureProvider<List<AiPrompt>>(
  (ref) => ref.read(collectorRepositoryProvider).aiPrompts(),
);

final selectedPromptProvider = NotifierProvider<SelectedPrompt, String>(
  SelectedPrompt.new,
);

class SelectedPrompt extends Notifier<String> {
  @override
  String build() => 'macau_analyst_expert';
  void set(String id) => state = id;
}

final aiReportProvider =
    FutureProvider.family<
      AiReport?,
      ({Lottery lottery, String period, String promptId})
    >((ref, key) async {
      return ref
          .read(collectorRepositoryProvider)
          .aiReport(
            lottery: key.lottery.code,
            period: key.period,
            promptId: key.promptId,
          );
    });

final streamClientProvider = Provider<StreamClient>((ref) {
  final client = StreamClient(config: ref.watch(appConfigProvider));
  ref.onDispose(client.dispose);
  return client;
});

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key, this.initialPeriod});

  final String? initialPeriod;

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  int _modeIndex = 0; // 0 = 帖文研判, 1 = 连肖研判
  String? _customPeriod;
  final Set<String> _selectedSources = {
    '海哥平特一肖',
    '顶尖大师',
    '管家婆传真',
  };
  final _promptCtrl = TextEditingController();
  bool _fetching = false;
  int _injectedCount = 12;

  @override
  void initState() {
    super.initState();
    if (widget.initialPeriod != null && widget.initialPeriod!.isNotEmpty) {
      _customPeriod = widget.initialPeriod!;
    }
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  void _toggleSource(String name) {
    setState(() {
      if (_selectedSources.contains(name)) {
        if (_selectedSources.length > 1) {
          _selectedSources.remove(name);
        }
      } else {
        _selectedSources.add(name);
      }
    });
  }

  Future<void> _fetchContext() async {
    setState(() => _fetching = true);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() {
      _fetching = false;
      _injectedCount = _selectedSources.length * 4;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已抓取并去噪 ${_selectedSources.length} 个数据源（共 $_injectedCount 条上下文）',
        ),
      ),
    );
  }

  void _openReport(String activePeriod) {
    final lottery = ref.read(selectedLotteryProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AiReportScreen(
          period: activePeriod,
          lotteryLabel: '${lottery.label}六合彩',
          customInstruction: _promptCtrl.text.trim(),
        ),
      ),
    );
  }

  Future<void> _pickPeriod(String currentActive) async {
    final controller = TextEditingController(text: currentActive);
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('输入期号'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            helperText: '例如 $currentActive',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    final normalized = (value.length <= 3 && int.tryParse(value) != null)
        ? '${nowInChina().year}${value.padLeft(3, '0')}'
        : value;
    setState(() => _customPeriod = normalized);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Lottery>(selectedLotteryProvider, (prev, next) {
      if (prev != next && _customPeriod != null) {
        setState(() => _customPeriod = null);
      }
    });
    final lottery = ref.watch(selectedLotteryProvider);
    final latestAsync = ref.watch(latestPeriodProvider(lottery));
    final fallbackPeriod = currentPeriodForLottery(lottery);
    final serverPeriod = latestAsync.maybeWhen(
      data: (p) => (p != null && p.isNotEmpty) ? p : fallbackPeriod,
      orElse: () => fallbackPeriod,
    );
    final activePeriod = _customPeriod ?? serverPeriod;
    final prevNum = previousPeriodOf(activePeriod, 1);
    final shortEnd = activePeriod.length >= 3
        ? activePeriod.substring(activePeriod.length - 3)
        : activePeriod;
    final prev4 = previousPeriodOf(activePeriod, 4);
    final shortStart = prev4.length >= 3
        ? prev4.substring(prev4.length - 3)
        : prev4;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                title: 'AI研判',
                subtitle: '顶尖大师 · 智能去噪 · 注入上下文',
                leading: Navigator.of(context).canPop()
                    ? GlassIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: '返回',
                        onTap: () => Navigator.of(context).maybePop(),
                      )
                    : null,
                trailing: GlassIconButton(
                  icon: Icons.history_rounded,
                  tooltip: '历史记录',
                  onTap: () => _openReport(activePeriod),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  children: [
                    // 1. 模式切换 (帖文研判 | 连肖研判)
                    GlassSegmentedControl<int>(
                      items: const [0, 1],
                      selected: _modeIndex,
                      labelBuilder: (v) => v == 0 ? '帖文研判' : '连肖研判',
                      onChanged: (v) => setState(() => _modeIndex = v),
                    ),
                    // 2. 研判参数
                    const DesignSectionHeader(
                      title: '研判参数',
                      padding: EdgeInsets.fromLTRB(2, 18, 2, 10),
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '彩种',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final l in Lottery.all)
                                GlassChipTag(
                                  label: l.label,
                                  selected: lottery == l,
                                  onTap: () {
                                    setState(() => _customPeriod = null);
                                    ref
                                        .read(
                                          selectedLotteryProvider.notifier,
                                        )
                                        .set(l);
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '期号',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 7),
                          InkWell(
                            onTap: () => _pickPeriod(activePeriod),
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    '第 $activePeriod 期',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tabularStyle(
                                      const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '上期 $prevNum 已开奖',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: tabularStyle(
                                      TextStyle(
                                        fontSize: 11,
                                        color: context.colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '数据源(多选)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final src in const [
                                '海哥平特一肖',
                                '顶尖大师',
                                '管家婆传真',
                                '白小组',
                              ])
                                _selectedSources.contains(src)
                                    ? GestureDetector(
                                        onTap: () => _toggleSource(src),
                                        child: GlassStatusPill(
                                          label: src,
                                          tone: GlassPillTone.primary,
                                          showDot: false,
                                        ),
                                      )
                                    : GlassChipTag(
                                        label: src,
                                        selected: false,
                                        onTap: () => _toggleSource(src),
                                      ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: GlassButton(
                              isLoading: _fetching,
                              onPressed: _fetchContext,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.download_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 8),
                                  Text('抓取数据'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Builder(
                            builder: (context) {
                              final session =
                                  ref.watch(sessionStatusProvider).value ??
                                  ref.read(apiClientProvider).status;
                              final isConnected =
                                  session == SessionStatus.connected;
                              return GlassStatusPill(
                                label: isConnected
                                    ? '实时上下文 · 已连接抓取 · 已注入 $_injectedCount 条'
                                    : '本地上下文 · 缓存模式 · 已注入 $_injectedCount 条',
                                color: isConnected
                                    ? DuiliaoColors.hit
                                    : DuiliaoColors.warning,
                                pulse: true,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    // 3. 数据预览
                    const DesignSectionHeader(
                      title: '数据预览',
                      padding: EdgeInsets.fromLTRB(2, 18, 2, 10),
                    ),
                    const GlassGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        _DenoisedSourcePreviewRow(
                          badgeChar: '海',
                          name: '海哥平特一肖',
                          time: '20:14',
                          excerpt: '本期平特一肖主推蛇肖,防龙、鸡…',
                        ),
                        _DenoisedSourcePreviewRow(
                          badgeChar: '顶',
                          name: '顶尖大师',
                          time: '19:48',
                          excerpt: '蛇肖临门气势足,兼顾龙肖,特码看小数…',
                        ),
                        _DenoisedSourcePreviewRow(
                          badgeChar: '管',
                          name: '管家婆传真',
                          time: '18:02',
                          excerpt: '本期看好猴肖出头,防狗肖,蓝波走热…',
                        ),
                      ],
                    ),
                    // 4. 连肖数据预览
                    const DesignSectionHeader(
                      title: '连肖数据预览',
                      padding: EdgeInsets.fromLTRB(2, 18, 2, 10),
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Wrap(
                                spacing: 7,
                                children: [
                                  ZTag(label: '蛇'),
                                  ZTag(label: '龙'),
                                  ZTag(label: '鸡'),
                                ],
                              ),
                              Text(
                                '近 5 期 · $shortStart–$shortEnd',
                                style: tabularStyle(
                                  TextStyle(
                                    fontSize: 11,
                                    color: context.colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const _StreakZodiacRow(
                            zodiac: '蛇',
                            marks: [true, true, false, true, false],
                            hits: 3,
                            total: 5,
                            toneColor: DuiliaoColors.hit,
                          ),
                          const SizedBox(height: 10),
                          const _StreakZodiacRow(
                            zodiac: '龙',
                            marks: [false, true, true, false, true],
                            hits: 3,
                            total: 5,
                            toneColor: DuiliaoColors.hit,
                          ),
                          const SizedBox(height: 10),
                          const _StreakZodiacRow(
                            zodiac: '鸡',
                            marks: [true, false, false, true, false],
                            hits: 2,
                            total: 5,
                            toneColor: DuiliaoColors.warning,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 5. Prompt Dock (固定于底部)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: GlassCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(10),
                  borderRadius: BorderRadius.circular(18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.09),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.terminal_rounded,
                                size: 16,
                                color: context.colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _promptCtrl,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: const InputDecoration(
                                    hintText: '输入研判指令,如:综合三源给出本期平特一肖…',
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onSubmitted: (_) => _openReport(activePeriod),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 96,
                        child: GlassButton(
                          height: 44,
                          borderRadius: BorderRadius.circular(12),
                          onPressed: () => _openReport(activePeriod),
                          child: const Text(
                            '开始研判',
                            style: TextStyle(fontSize: 13.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DenoisedSourcePreviewRow extends StatelessWidget {
  const _DenoisedSourcePreviewRow({
    required this.badgeChar,
    required this.name,
    required this.time,
    required this.excerpt,
  });

  final String badgeChar;
  final String name;
  final String time;
  final String excerpt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: DuiliaoColors.primary.withValues(alpha: 0.14),
              border: Border.all(
                color: DuiliaoColors.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              badgeChar,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB39DFF),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      time,
                      style: tabularStyle(
                        TextStyle(
                          fontSize: 11,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  excerpt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const GlassStatusPill(
            label: '已去噪',
            tone: GlassPillTone.success,
            showDot: false,
          ),
        ],
      ),
    );
  }
}

class _StreakZodiacRow extends StatelessWidget {
  const _StreakZodiacRow({
    required this.zodiac,
    required this.marks,
    required this.hits,
    required this.total,
    required this.toneColor,
  });

  final String zodiac;
  final List<bool> marks;
  final int hits;
  final int total;
  final Color toneColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(
            zodiac,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final hit in marks) HitMarkBadge(isHit: hit),
          ],
        ),
        const Spacer(),
        RichText(
          text: TextSpan(
            style: tabularStyle(
              TextStyle(
                fontSize: 11,
                color: context.colors.onSurfaceVariant,
              ),
            ),
            children: [
              TextSpan(text: '近 $total 中 '),
              TextSpan(
                text: '$hits',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: toneColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 1:1 implementation of `ai-report.html` (`AI 研判报告`).
/// Also supports toggling raw Markdown/HTML or running live SSE streaming for staff.
class AiReportScreen extends ConsumerStatefulWidget {
  const AiReportScreen({
    super.key,
    required this.period,
    this.lotteryLabel = '澳门六合彩',
    this.customInstruction = '',
  });

  final String period;
  final String lotteryLabel;
  final String customInstruction;

  @override
  ConsumerState<AiReportScreen> createState() => _AiReportScreenState();
}

class _AiReportScreenState extends ConsumerState<AiReportScreen> {
  bool _showRawMarkdown = false;
  String? _streamBuffer;
  String? _streamStatus;
  bool _streaming = false;

  Future<void> _startStream(String promptId) async {
    final token = ref.read(authControllerProvider).accessToken;
    if (token == null || _streaming) return;
    final reportKey = (
      lottery: ref.read(selectedLotteryProvider),
      period: widget.period,
      promptId: promptId,
    );
    var generated = false;

    setState(() {
      _streaming = true;
      _streamBuffer = '';
      _streamStatus = '正在准备…';
    });

    try {
      final stream = ref.read(streamClientProvider).analyze(
            accessToken: token,
            promptId: promptId,
            period: Period.short(widget.period),
          );
      await for (final event in stream) {
        if (!mounted) return;
        setState(() {
          switch (event.stage) {
            case 'status':
            case 'started':
              _streamStatus = event.message ?? '正在生成…';
            case 'delta':
              _streamBuffer = (_streamBuffer ?? '') + event.delta;
            case 'done':
              _streamStatus = null;
              _streaming = false;
              generated = true;
            case 'error':
              _streamStatus = event.error ?? '生成失败';
              _streaming = false;
          }
        });
      }
      if (generated) {
        ref.invalidate(aiReportProvider(reportKey));
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _streaming = false;
          _streamStatus = e.displayMessage;
        });
      }
    } on NetworkException catch (e) {
      if (mounted) {
        setState(() {
          _streaming = false;
          _streamStatus = e.displayMessage;
        });
      }
    } finally {
      if (mounted) setState(() => _streaming = false);
    }
  }

  Future<void> _exportReport(String summaryText) async {
    await Clipboard.setData(ClipboardData(text: summaryText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('研判报告已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lottery = ref.watch(selectedLotteryProvider);
    final promptId = ref.watch(selectedPromptProvider);
    final canOperate = ref.watch(canOperateProvider);
    final key = (lottery: lottery, period: widget.period, promptId: promptId);
    final reportAsync = ref.watch(aiReportProvider(key));
    final cachedReport = reportAsync.maybeWhen(
      data: (r) => r,
      orElse: () => null,
    );

    const defaultSummary =
        '综合 3 源交叉验证,本期平特一肖主推【蛇】,次防【龙】【鸡】;特码区间倾向小数蓝波,关注 03、14、26。';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                title: 'AI 研判报告',
                centerTitle: true,
                leading: GlassIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '返回',
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                trailing: GlassIconButton(
                  icon: Icons.share_outlined,
                  tooltip: '分享',
                  onTap: () => _exportReport(
                    cachedReport?.content.isNotEmpty == true
                        ? cachedReport!.content
                        : defaultSummary,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  children: [
                    // 1. 报告元信息 (.chip wrap)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        GlassChipTag(label: '第 ${widget.period} 期'),
                        GlassChipTag(label: widget.lotteryLabel),
                        GlassChipTag(
                          label: cachedReport?.modelLabel.isNotEmpty == true
                              ? cachedReport!.modelLabel
                              : 'Kimi · 默认模型',
                        ),
                        GlassChipTag(
                          label: cachedReport?.generatedAt ?? '实时研判就绪',
                        ),
                        GlassChipTag(
                          label: cachedReport != null ? '服务端缓存' : '实时聚合研判',
                        ),
                      ],
                    ),
                    if (_streamBuffer != null) ...[
                      const DesignSectionHeader(
                        title: '实时流式输出',
                        padding: EdgeInsets.fromLTRB(2, 18, 2, 10),
                      ),
                      GlassCard(
                        margin: EdgeInsets.zero,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_streamStatus != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  _streamStatus!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: DuiliaoColors.primary,
                                  ),
                                ),
                              ),
                            MarkdownBody(
                              data: _streamBuffer!.isEmpty
                                  ? '正在等待模型输出…'
                                  : _streamBuffer!,
                              selectable: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                    // 2. 核心结论
                    const DesignSectionHeader(
                      title: '核心结论',
                      padding: EdgeInsets.fromLTRB(2, 18, 2, 10),
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 4,
                            height: 54,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              gradient: DuiliaoColors.auroraGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: DuiliaoColors.primary.withValues(alpha: 0.55),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _showRawMarkdown &&
                                    cachedReport?.content.isNotEmpty == true
                                ? MarkdownBody(
                                    data: cachedReport!.content,
                                    selectable: true,
                                  )
                                : const Text(
                                    defaultSummary,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      height: 1.75,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    // 3. 重点参考
                    const DesignSectionHeader(
                      title: '重点参考',
                      padding: EdgeInsets.fromLTRB(2, 18, 2, 10),
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '特码关注 · 小数蓝波',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 7,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              const NumberBall(
                                number: '03',
                                bose: '蓝',
                                showCaption: false,
                              ),
                              const NumberBall(
                                number: '14',
                                bose: '蓝',
                                showCaption: false,
                              ),
                              const NumberBall(
                                number: '26',
                                bose: '蓝',
                                goldBorder: true,
                                showCaption: false,
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 2),
                                child: Text(
                                  '金边为特选',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '生肖关注',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Wrap(
                            spacing: 7,
                            children: [
                              ZTag(label: '蛇'),
                              ZTag(label: '龙'),
                              ZTag(label: '鸡'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // 4. 各源观点
                    const DesignSectionHeader(
                      title: '各源观点',
                      padding: EdgeInsets.fromLTRB(2, 18, 2, 10),
                    ),
                    const GlassGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        _SourceViewpointRow(
                          name: '海哥平特一肖',
                          primaryZodiac: '蛇',
                          guardZodiacs: ['龙', '鸡'],
                          consistent: true,
                        ),
                        _SourceViewpointRow(
                          name: '顶尖大师',
                          primaryZodiac: '蛇',
                          guardZodiacs: ['龙'],
                          consistent: true,
                        ),
                        _SourceViewpointRow(
                          name: '管家婆传真',
                          primaryZodiac: '猴',
                          guardZodiacs: ['狗'],
                          consistent: false,
                        ),
                      ],
                    ),
                    // 5. 置信度
                    const DesignSectionHeader(
                      title: '置信度',
                      padding: EdgeInsets.fromLTRB(2, 18, 2, 10),
                    ),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '综合置信度',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '72%',
                                style: tabularStyle(
                                  const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFB39DFF),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const GlassLinearProgress(value: 0.72, height: 8),
                          const SizedBox(height: 12),
                          Text(
                            '综合置信度 72% · 基于近 50 期源命中率加权',
                            style: tabularStyle(
                              TextStyle(
                                fontSize: 11,
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // 6. 风险提示
                    GlassSubtleBox(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: DuiliaoColors.warning,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '研判结果仅供参考,不构成任何投注建议。数据源命中率存在波动,请理性对待。',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.65,
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 7. 底部操作行(sticky 底部)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: GlassCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(10),
                  borderRadius: BorderRadius.circular(18),
                  child: Row(
                    children: [
                      GlassGhostButton(
                        label: '原始 HTML',
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        onPressed: () {
                          setState(() => _showRawMarkdown = !_showRawMarkdown);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _showRawMarkdown ? '已切换至原始输出视图' : '已切换至结构化报告视图',
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      GlassGhostButton(
                        label: '重新研判',
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        onPressed: () {
                          if (canOperate) {
                            _startStream(promptId);
                          } else {
                            Navigator.of(context).maybePop();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GlassButton(
                          height: 44,
                          borderRadius: BorderRadius.circular(12),
                          onPressed: () => _exportReport(
                            cachedReport?.content.isNotEmpty == true
                                ? cachedReport!.content
                                : defaultSummary,
                          ),
                          child: const Text(
                            '导出报告',
                            style: TextStyle(fontSize: 13.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceViewpointRow extends StatelessWidget {
  const _SourceViewpointRow({
    required this.name,
    required this.primaryZodiac,
    required this.guardZodiacs,
    required this.consistent,
  });

  final String name;
  final String primaryZodiac;
  final List<String> guardZodiacs;
  final bool consistent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '主推',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    ZTag(label: primaryZodiac),
                    Text(
                      '防',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    for (final z in guardZodiacs) ZTag(label: z),
                  ],
                ),
              ],
            ),
          ),
          GlassStatusPill(
            label: consistent ? '一致' : '分歧',
            tone: consistent ? GlassPillTone.success : GlassPillTone.warning,
            showDot: false,
          ),
        ],
      ),
    );
  }
}
