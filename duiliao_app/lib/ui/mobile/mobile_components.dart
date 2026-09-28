/// Reusable, mobile-first presentation primitives.
library;

import 'package:flutter/material.dart';

import '../glass/glass_widgets.dart';
import '../theme.dart';
import '../tokens.dart';

class MobileSurface extends StatelessWidget {
  const MobileSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DuiliaoTokens.space4),
    this.margin,
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Use one glass surface primitive across the native app so the Flutter
    // pages keep the same material language as app-design.
    final glassColor = color?.withValues(alpha: context.isDark ? 0.58 : 0.74);
    return GlassContainer(
      padding: padding,
      margin: margin,
      onTap: onTap,
      fillColor: glassColor,
      borderRadius: BorderRadius.circular(DuiliaoTokens.radiusLarge),
      child: child,
    );
  }
}

class MobilePageHeader extends StatelessWidget {
  const MobilePageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DuiliaoTokens.space4,
        DuiliaoTokens.space3,
        DuiliaoTokens.space4,
        DuiliaoTokens.space2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: DuiliaoTokens.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.texts.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class MobileHeroHeader extends StatelessWidget {
  const MobileHeroHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return MobileSurface(
      padding: const EdgeInsets.all(DuiliaoTokens.space6),
      color: context.colors.primaryContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: context.texts.labelSmall?.copyWith(
                    color: context.colors.primary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: DuiliaoTokens.space2),
                Text(title, style: context.texts.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: DuiliaoTokens.space2),
                  Text(
                    subtitle!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: DuiliaoTokens.space3),
            action!,
          ],
        ],
      ),
    );
  }
}

class MobileSection extends StatelessWidget {
  const MobileSection({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.action,
    this.padding = const EdgeInsets.symmetric(
      horizontal: DuiliaoTokens.space4,
      vertical: DuiliaoTokens.space3,
    ),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final actionItems = action == null ? const <Widget>[] : <Widget>[action!];
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || action != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(title!, style: context.texts.titleMedium),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                ...actionItems,
              ],
            ),
          if (title != null || action != null)
            const SizedBox(height: DuiliaoTokens.space3),
          child,
        ],
      ),
    );
  }
}

class MobileStatCard extends StatelessWidget {
  const MobileStatCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.color,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? context.colors.primary;
    return MobileSurface(
      padding: const EdgeInsets.all(DuiliaoTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: context.texts.bodySmall)),
              if (icon != null) Icon(icon, size: 18, color: tone),
            ],
          ),
          const SizedBox(height: DuiliaoTokens.space2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.headlineSmall?.copyWith(
              color: tone,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

class MobileStatusChip extends StatelessWidget {
  const MobileStatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: context.texts.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class MobileMetricRow extends StatelessWidget {
  const MobileMetricRow({super.key, required this.items});

  final List<({String label, String value, Color? color})> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: DuiliaoTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  items[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  items[i].value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleMedium?.copyWith(
                    color: items[i].color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class MobileEmptyState extends StatelessWidget {
  const MobileEmptyState({
    super.key,
    required this.title,
    this.detail,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? detail;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DuiliaoTokens.space7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: context.colors.onSurfaceVariant),
          const SizedBox(height: DuiliaoTokens.space3),
          Text(
            title,
            style: context.texts.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (detail != null) ...[
            const SizedBox(height: DuiliaoTokens.space2),
            Text(
              detail!,
              style: context.texts.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: DuiliaoTokens.space4),
            action!,
          ],
        ],
      ),
    );
  }
}
