/// AI research: read the server-cached report, and (staff only) regenerate it.
///
/// Reading is free and never triggers a model call — `/ai/report` only returns
/// what is already cached. Generation is restricted to staff/admin because each
/// run makes the server scrape a site and bill an LLM request; without that split
/// every viewer would produce a fresh invoice.
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_exception.dart';
import '../../core/net/stream_client.dart';
import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/app_event.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import '../auth/auth_providers.dart';
import '../comparison/comparison_screen.dart';

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

final aiReportProvider = FutureProvider.family<AiReport?,
    ({Lottery lottery, String period, String promptId})>((ref, key) async {
  return ref.read(collectorRepositoryProvider).aiReport(
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
  String? _period;

  /// Text accumulated from the current streaming run, if any.
  String? _streamBuffer;
  String? _streamStatus;
  bool _streaming = false;

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
  }

  @override
  Widget build(BuildContext context) {
    final lottery = ref.watch(selectedLotteryProvider);
    final promptId = ref.watch(selectedPromptProvider);
    final canOperate = ref.watch(canOperateProvider);

    if (_period == null) {
      final latest = ref.watch(latestPeriodProvider(lottery));
      return Scaffold(
        appBar: AppBar(title: const Text('AI 研判')),
        body: latest.when(
          loading: () => const SkeletonList(),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(latestPeriodProvider(lottery)),
          ),
          data: (period) {
            if (period == null) return const EmptyState(message: '暂无开奖期号');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _period = period);
            });
            return const SkeletonList();
          },
        ),
      );
    }

    final key = (lottery: lottery, period: _period!, promptId: promptId);
    final async = ref.watch(aiReportProvider(key));

    return Scaffold(
      appBar: AppBar(
        title: Text('AI 研判 ${Period.compact(_period)}'),
        actions: [
          if (canOperate && !_streaming)
            IconButton(
              tooltip: '流式重新生成',
              icon: const Icon(Icons.auto_awesome),
              onPressed: () => _startStream(promptId),
            ),
        ],
      ),
      body: Column(
        children: [
          _PromptSelector(promptId: promptId),
          Expanded(
            child: _streamBuffer != null
                ? _StreamingView(
                    text: _streamBuffer!,
                    status: _streamStatus,
                    streaming: _streaming,
                    onDismiss: () => setState(() {
                      _streamBuffer = null;
                      _streamStatus = null;
                    }),
                  )
                : AsyncView<AiReport?>(
                    value: async,
                    loading: const SkeletonList(itemHeight: 24, itemCount: 12),
                    onRetry: () => ref.invalidate(aiReportProvider(key)),
                    builder: (report) {
                      if (report == null) {
                        return EmptyState(
                          message: '本期暂无 AI 报告',
                          icon: Icons.auto_awesome_outlined,
                          detail: canOperate
                              ? '点击右上角生成（会调用外部模型）'
                              // A plain user cannot generate, so telling them to
                              // "try again" would be useless advice.
                              : '报告由运营人员生成后即可查看',
                        );
                      }
                      return _ReportView(report: report);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _startStream(String promptId) async {
    final token = ref.read(authControllerProvider).accessToken;
    if (token == null) return;

    setState(() {
      _streaming = true;
      _streamBuffer = '';
      _streamStatus = '正在准备…';
    });

    try {
      final stream = ref.read(streamClientProvider).analyze(
            accessToken: token,
            promptId: promptId,
            period: Period.short(_period),
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
            case 'error':
              _streamStatus = event.error ?? '生成失败';
              _streaming = false;
          }
        });
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
}

class _PromptSelector extends ConsumerWidget {
  const _PromptSelector({required this.promptId});

  final String promptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(aiPromptsProvider);
    return Material(
      color: context.colors.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: async.when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (_, _) => const SizedBox.shrink(),
          data: (prompts) {
            if (prompts.isEmpty) return const SizedBox.shrink();
            // Fall back to the first prompt if the remembered id is gone.
            final value =
                prompts.any((p) => p.id == promptId) ? promptId : prompts.first.id;
            return DropdownButtonFormField<String>(
              initialValue: value,
              isDense: true,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '提示词模板'),
              items: [
                for (final prompt in prompts)
                  DropdownMenuItem(
                    value: prompt.id,
                    child: Text(
                      prompt.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (next) {
                if (next != null) {
                  ref.read(selectedPromptProvider.notifier).set(next);
                }
              },
            );
          },
        ),
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({required this.report});

  final AiReport report;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AttributionBar(report: report),
        const SizedBox(height: 12),
        MarkdownBody(
          data: report.content.isEmpty ? '_（报告内容为空）_' : report.content,
          selectable: true,
        ),
        const SizedBox(height: 24),
        const _AiDisclaimer(),
      ],
    );
  }
}

class _AttributionBar extends StatelessWidget {
  const _AttributionBar({required this.report});

  final AiReport report;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.smart_toy_outlined, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                // Model and timestamp matter: a report generated before the draw
                // is a different artefact from one generated after it.
                '${report.modelLabel}'
                '${report.generatedAt == null ? '' : ' · 生成于 ${report.generatedAt}'}',
                style: context.texts.labelSmall,
              ),
            ),
          ],
        ),
      );
}

class _StreamingView extends StatelessWidget {
  const _StreamingView({
    required this.text,
    required this.status,
    required this.streaming,
    required this.onDismiss,
  });

  final String text;
  final String? status;
  final bool streaming;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            if (streaming)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (streaming) const SizedBox(width: 8),
            Expanded(
              child: Text(
                status ?? (streaming ? '正在生成…' : '生成结束'),
                style: context.texts.labelMedium,
              ),
            ),
            if (!streaming)
              TextButton(onPressed: onDismiss, child: const Text('关闭')),
          ],
        ),
        const SizedBox(height: 12),
        if (text.isEmpty && streaming)
          const Text('等待模型输出…')
        else
          // Rendered as Markdown as it arrives, so partial headings and lists
          // still read correctly.
          MarkdownBody(data: text, selectable: true),
        const SizedBox(height: 24),
        const _AiDisclaimer(),
      ],
    );
  }
}

class _AiDisclaimer extends StatelessWidget {
  const _AiDisclaimer();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: DuiliaoColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: DuiliaoColors.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 15, color: DuiliaoColors.warning),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'AI 生成内容，仅供数据参考，不构成任何预测结论或投注建议。'
                '所有命中判定以后端判定结果为准。',
                style: context.texts.bodySmall
                    ?.copyWith(color: DuiliaoColors.warning),
              ),
            ),
          ],
        ),
      );
}
