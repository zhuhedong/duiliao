/// Shared loading / empty / error / stale presentation.
///
/// Every data screen routes through these so the app behaves consistently: a
/// skeleton while loading, a retry button on error, an explicit empty state, and
/// a visible banner whenever cached data is being shown because the network was
/// unavailable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_exception.dart';
import '../theme.dart';

/// Renders an [AsyncValue] with consistent states.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.loading,
    this.emptyCheck,
    this.emptyMessage = '暂无数据',
    this.emptyIcon = Icons.inbox_outlined,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  /// Invoked by the error state's retry button. Without it, an error is a dead
  /// end for the user.
  final VoidCallback? onRetry;

  /// Skeleton shown while loading. Defaults to a spinner.
  final Widget? loading;

  /// Returns true when [T] holds no rows, so an empty state is shown instead of
  /// a blank screen.
  final bool Function(T data)? emptyCheck;

  final String emptyMessage;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => loading ?? const _CenteredSpinner(),
      error: (error, stack) => ErrorState(error: error, onRetry: onRetry),
      data: (data) {
        if (emptyCheck?.call(data) == true) {
          return EmptyState(message: emptyMessage, icon: emptyIcon, onRetry: onRetry);
        }
        return builder(data);
      },
      // Keep showing the last good data while refreshing rather than flashing a
      // spinner over content the user is reading.
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
    );
  }
}

class _CenteredSpinner extends StatelessWidget {
  const _CenteredSpinner();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
}

/// Error state with a cause-specific message and a retry action.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final (message, hint) = _describe(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: context.colors.error),
            const SizedBox(height: 12),
            Text(
              message,
              style: context.texts.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint,
                style: context.texts.bodySmall
                    ?.copyWith(color: context.colors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Map an error to a message and, where useful, an actionable hint.
  static (String, String?) _describe(Object error) {
    if (error is ApiException) {
      // A signing or clock problem is a build/device issue the user can act on,
      // so it gets a specific hint rather than a generic failure message.
      if (error.code == ApiErrorCode.badSignature) {
        return (error.displayMessage, '客户端与服务端的签名密钥不一致');
      }
      if (error.code == ApiErrorCode.badTimestamp) {
        return (error.displayMessage, '请开启系统自动校准时间');
      }
      return (error.displayMessage, null);
    }
    if (error is NetworkException) {
      return (error.displayMessage, '请确认网络后重试');
    }
    return ('加载失败', error.toString());
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.onRetry,
    this.detail,
  });

  final String message;
  final IconData icon;
  final VoidCallback? onRetry;
  final String? detail;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 44, color: context.colors.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(message, style: context.texts.titleMedium),
              if (detail != null) ...[
                const SizedBox(height: 6),
                Text(
                  detail!,
                  style: context.texts.bodySmall
                      ?.copyWith(color: context.colors.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新'),
                ),
              ],
            ],
          ),
        ),
      );
}

/// Banner shown when the content below is cached rather than live.
///
/// Always visible when stale: presenting yesterday's ratings as current would be
/// worse than showing nothing, because decisions are made from these numbers.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.storedAtLabel, this.onRetry});

  /// `HH:mm` the cached copy was stored.
  final String? storedAtLabel;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DuiliaoColors.offline.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                storedAtLabel == null
                    ? '离线数据'
                    : '离线数据 · 更新于 $storedAtLabel',
                style: context.texts.bodySmall,
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('重试'),
              ),
          ],
        ),
      ),
    );
  }
}

/// A shimmer-free skeleton: grey blocks sized like the eventual content.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.itemCount = 6, this.itemHeight = 72});

  final int itemCount;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.surfaceContainerHighest;
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: itemCount,
      itemBuilder: (context, index) => Container(
        height: itemHeight,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

/// A labelled statistic, used across the summary cards.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
    this.hint,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: context.colors.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: context.texts.bodySmall
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: context.texts.titleMedium?.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (hint != null)
          Text(
            hint!,
            style: context.texts.labelSmall
                ?.copyWith(color: context.colors.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// A small status chip with an icon and text.
///
/// Both channels are always used: hit and miss must not be distinguishable by
/// colour alone.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.compact = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 11 : 13, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: (compact ? context.texts.labelSmall : context.texts.labelMedium)
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// A warning row used for integrity and small-sample notices.
class WarningNote extends StatelessWidget {
  const WarningNote({
    super.key,
    required this.message,
    this.icon = Icons.warning_amber_rounded,
    this.color,
  });

  final String message;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effective = color ?? DuiliaoColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: effective.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: effective.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: effective),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: context.texts.bodySmall?.copyWith(color: effective),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled section header used inside scroll views.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing, this.subtitle});

  final String title;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.texts.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: context.texts.bodySmall
                          ?.copyWith(color: context.colors.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      );
}
