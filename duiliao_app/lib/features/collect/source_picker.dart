/// Source selection sheet, with search, filters, and a long-press test run.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_exception.dart';
import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/source.dart';
import '../../domain/play_type.dart';
import '../../ui/glass/glass_widgets.dart';
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

        return GlassContainer(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          blur: 35,
          fillColor: context.colors.surface.withValues(alpha: 0.92),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
              Container(
                color: context.colors.surfaceContainerHighest.withValues(alpha: 0.35),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      '已选 ${draft.sourceIds.length} / 可见 ${visible.length}',
                      style: context.texts.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    TextButton(
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
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (source.isBroken)
                            const GlassBadge(
                              label: '脚本缺失',
                              color: DuiliaoColors.miss,
                              icon: Icons.error_outline,
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '${PlayTypes.labelFor(source.playType)} · ${source.siteFamily}'
                        ' · ${source.timeoutSec}s',
                        style: context.texts.labelSmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
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
                  child: GlassButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('完成', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Run one source in isolation and show its raw output.
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
        backgroundColor: Colors.transparent,
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
    return GlassContainer(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      blur: 35,
      fillColor: context.colors.surface.withValues(alpha: 0.92),
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  source.sourceName,
                  style: context.texts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              GlassBadge(
                label: result.ok ? '成功' : '失败',
                color: result.ok ? DuiliaoColors.hit : DuiliaoColors.miss,
                icon: result.ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: context.colors.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: StatTile(label: '条目数', value: '${result.itemCount}'),
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(label: '耗时', value: result.elapsedLabel),
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                const SizedBox(width: 8),
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
          Text('stdout', style: context.texts.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _OutputBlock(
            text: result.stdout.isEmpty ? '（无输出）' : result.stdout,
          ),
          if (result.stderr.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('stderr', style: context.texts.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            _OutputBlock(text: result.stderr, isError: !result.ok),
          ],
        ],
      ),
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError
              ? DuiliaoColors.miss.withValues(alpha: 0.1)
              : context.colors.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isError
                ? DuiliaoColors.miss.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: context.texts.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      );
}
