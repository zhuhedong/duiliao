/// Source selection sheet, with search, filters, and a long-press test run.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_exception.dart';
import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/source.dart';
import '../../domain/play_type.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/async_view.dart';
import 'collect_providers.dart';

class SourcePicker extends ConsumerStatefulWidget {
  const SourcePicker({
    super.key,
    required this.lottery,
    required this.scrollController,
  });

  final Lottery lottery;
  final ScrollController scrollController;

  @override
  ConsumerState<SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends ConsumerState<SourcePicker> {
  String _query = '';
  String? _playFilter;
  String? _familyFilter;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sourcesForLotteryProvider(widget.lottery));
    final draft = ref.watch(collectDraftProvider);
    final controller = ref.read(collectDraftProvider.notifier);

    return AsyncView<List<CollectorSource>>(
      value: async,
      loading: const SkeletonList(itemHeight: 56),
      onRetry: () => ref.invalidate(sourcesForLotteryProvider(widget.lottery)),
      emptyCheck: (sources) => sources.isEmpty,
      emptyMessage: '该彩种没有启用的数据源',
      builder: (sources) {
        final plays = sources.map((s) => s.playType).toSet().toList()..sort();
        final families = sources.map((s) => s.siteFamily).toSet().toList()..sort();

        final visible = sources.where((source) {
          if (!source.matches(_query)) return false;
          if (_playFilter != null && source.playType != _playFilter) return false;
          if (_familyFilter != null && source.siteFamily != _familyFilter) {
            return false;
          }
          return true;
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: '搜索源名 / ID / 站族',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterDropdown(
                          hint: '玩法',
                          value: _playFilter,
                          items: {
                            for (final play in plays) play: PlayTypes.labelFor(play),
                          },
                          onChanged: (value) => setState(() => _playFilter = value),
                        ),
                        const SizedBox(width: 8),
                        _FilterDropdown(
                          hint: '站族',
                          value: _familyFilter,
                          items: {for (final family in families) family: family},
                          onChanged: (value) =>
                              setState(() => _familyFilter = value),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: context.colors.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      '已选 ${draft.sourceIds.length} / 可见 ${visible.length}',
                      style: context.texts.labelMedium,
                    ),
                    const Spacer(),
                    TextButton(
                      // Selects only what is currently visible, so a filtered
                      // "select all" does not silently include hidden sources.
                      onPressed: () => controller.selectAll(
                        {...draft.sourceIds, ...visible.map((s) => s.sourceId)},
                      ),
                      child: const Text('全选可见'),
                    ),
                    TextButton(
                      onPressed: controller.clearSources,
                      child: const Text('清空'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: widget.scrollController,
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final source = visible[index];
                  final selected = draft.sourceIds.contains(source.sourceId);
                  return CheckboxListTile(
                    dense: true,
                    value: selected,
                    onChanged: (_) => controller.toggleSource(source.sourceId),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            source.sourceName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (source.isBroken)
                          const StatusChip(
                            label: '脚本缺失',
                            color: DuiliaoColors.miss,
                            icon: Icons.error_outline,
                            compact: true,
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '${PlayTypes.labelFor(source.playType)} · ${source.siteFamily}'
                      ' · ${source.timeoutSec}s',
                      style: context.texts.labelSmall,
                    ),
                    secondary: IconButton(
                      tooltip: '单源试跑',
                      icon: const Icon(Icons.play_circle_outline),
                      onPressed: () => _testSource(source),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('完成'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Run one source in isolation and show its raw output.
  ///
  /// This is the field-diagnosis path: it is the only view that surfaces the
  /// script's stdout and stderr, which is what identifies whether a source is
  /// failing because the site changed, timed out, or the script itself is broken.
  Future<void> _testSource(CollectorSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final result = await ref.read(collectorRepositoryProvider).testSource(
            sourceId: source.sourceId,
            lottery: widget.lottery.code,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          builder: (_, scroll) => _TestResultSheet(
            source: source,
            result: result,
            controller: scroll,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(e.displayMessage)));
    } on NetworkException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(e.displayMessage)));
    }
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String hint;
  final String? value;
  final Map<String, String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        isDense: true,
        isExpanded: true,
        decoration: InputDecoration(labelText: hint),
        items: [
          DropdownMenuItem<String?>(value: null, child: Text('全部$hint')),
          for (final entry in items.entries)
            DropdownMenuItem<String?>(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _TestResultSheet extends StatelessWidget {
  const _TestResultSheet({
    required this.source,
    required this.result,
    required this.controller,
  });

  final CollectorSource source;
  final ScriptRunResult result;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(source.sourceName, style: context.texts.titleMedium),
            ),
            StatusChip(
              label: result.ok ? '成功' : '失败',
              color: result.ok ? DuiliaoColors.hit : DuiliaoColors.miss,
              icon: result.ok ? Icons.check_circle : Icons.cancel,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatTile(label: '条目数', value: '${result.itemCount}'),
            ),
            Expanded(
              child: StatTile(label: '耗时', value: result.elapsedLabel),
            ),
            Expanded(
              child: StatTile(
                label: '退出码',
                value: result.exitCode?.toString() ?? '—',
                valueColor:
                    (result.exitCode ?? 0) != 0 ? DuiliaoColors.miss : null,
              ),
            ),
          ],
        ),
        if (result.errorCode != null) ...[
          const SizedBox(height: 10),
          WarningNote(
            message: '错误码 ${result.errorCode}'
                '${result.errorMsg == null ? '' : '：${result.errorMsg}'}',
            icon: Icons.error_outline,
            color: DuiliaoColors.miss,
          ),
        ],
        const Divider(height: 24),
        Text('stdout', style: context.texts.labelLarge),
        const SizedBox(height: 4),
        _OutputBlock(
          text: result.stdout.isEmpty ? '（无输出）' : result.stdout,
        ),
        // stderr is only shown when it matters: a successful run often writes
        // harmless warnings there.
        if (result.stderr.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('stderr', style: context.texts.labelLarge),
          const SizedBox(height: 4),
          _OutputBlock(text: result.stderr, isError: !result.ok),
        ],
      ],
    );
  }
}

class _OutputBlock extends StatelessWidget {
  const _OutputBlock({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 320),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isError
              ? DuiliaoColors.miss.withValues(alpha: 0.08)
              : context.colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: context.texts.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      );
}
