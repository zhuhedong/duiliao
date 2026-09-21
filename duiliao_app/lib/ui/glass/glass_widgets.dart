/// iOS 27 Liquid Glass Foundation Widgets.
///
/// Provides ambient aurora backgrounds, frosted glass cards, glass containers,
/// glass pills, and specular highlight treatments.
library;

import 'package:flutter/material.dart';

/// Ambient canvas with glowing aurora orbs beneath a frosted glass layer.
///
/// In iOS 27 glassmorphism, frosted glass requires vibrant underlying light
/// sources to refract; without ambient glowing orbs, blur over flat surfaces
/// loses depth.
class GlassBackground extends StatelessWidget {
  const GlassBackground({
    super.key,
    required this.child,
    this.showOrbs = true,
  });

  final Widget child;
  final bool showOrbs;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF090D16) : const Color(0xFFF3F6FD);

    return ColoredBox(
      color: bgColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showOrbs) ...[
            // Top-right electric blue / indigo glow
            Positioned(
              top: -80,
              right: -60,
              child: _AmbientOrb(
                size: 320,
                color: isDark
                    ? const Color(0xFF3B82F6).withValues(alpha: 0.22)
                    : const Color(0xFF007AFF).withValues(alpha: 0.16),
              ),
            ),
            // Middle-left nebula violet / magenta glow
            Positioned(
              top: 260,
              left: -90,
              child: _AmbientOrb(
                size: 280,
                color: isDark
                    ? const Color(0xFF8B5CF6).withValues(alpha: 0.18)
                    : const Color(0xFFC084FC).withValues(alpha: 0.14),
              ),
            ),
            // Bottom-right cyan / emerald glow
            Positioned(
              bottom: 80,
              right: -70,
              child: _AmbientOrb(
                size: 300,
                color: isDark
                    ? const Color(0xFF06B6D4).withValues(alpha: 0.16)
                    : const Color(0xFF2DD4BF).withValues(alpha: 0.13),
              ),
            ),
          ],
          child,
        ],
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: color.a * 0.4),
              Colors.transparent,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }
}

/// A liquid frosted glass container with real backdrop blur, specular edge
/// highlight, and soft ambient drop shadow.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.blur = 18.0,
    this.borderGradient,
    this.fillColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.onTap,
    this.width,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final double blur;
  final Gradient? borderGradient;
  final Color? fillColor;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(20);

    // Liquid glass gradient surface
    final defaultBg = isDark
        ? const Color(0xFF141A28).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.72);

    final effectiveBg = fillColor ?? defaultBg;

    // Specular highlight border color
    final defaultBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.70);

    final effectiveBorderColor = borderColor ?? defaultBorderColor;

    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.38)
        : const Color(0xFF475569).withValues(alpha: 0.08);

    Widget content = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: radius,
        border: Border.all(
          color: effectiveBorderColor,
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
          // Subtle inner top specular highlight
          BoxShadow(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.white.withValues(alpha: 0.45),
            blurRadius: 1,
            spreadRadius: 0.5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          splashColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          highlightColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
          child: content,
        ),
      );
    }

    final frosted = ClipRRect(
      borderRadius: radius,
      child: content,
    );

    if (margin != null) {
      return Padding(padding: margin!, child: frosted);
    }
    return frosted;
  }
}

/// A drop-in replacement or wrapper for [Card] using the iOS 27 glass styling.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    this.padding,
    this.borderRadius,
    this.onTap,
    this.blur = 18.0,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      margin: margin,
      padding: padding,
      borderRadius: borderRadius ?? BorderRadius.circular(20),
      onTap: onTap,
      blur: blur,
      child: child,
    );
  }
}

/// A liquid frosted segmented pill selector.
class GlassSegmentedControl<T> extends StatelessWidget {
  const GlassSegmentedControl({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    required this.labelBuilder,
    this.iconBuilder,
  });

  final List<T> items;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T item) labelBuilder;
  final IconData? Function(T item)? iconBuilder;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return GlassContainer(
      blur: 14,
      borderRadius: BorderRadius.circular(16),
      borderWidth: 1.0,
      fillColor: isDark
          ? const Color(0xFF131926).withValues(alpha: 0.55)
          : Colors.white.withValues(alpha: 0.60),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: _GlassSegmentItem<T>(
                item: item,
                isSelected: item == selected,
                label: labelBuilder(item),
                icon: iconBuilder?.call(item),
                primary: primary,
                isDark: isDark,
                onTap: () => onChanged(item),
              ),
            ),
        ],
      ),
    );
  }
}

class _GlassSegmentItem<T> extends StatelessWidget {
  const _GlassSegmentItem({
    required this.item,
    required this.isSelected,
    required this.label,
    required this.icon,
    required this.primary,
    required this.isDark,
    required this.onTap,
  });

  final T item;
  final bool isSelected;
  final String label;
  final IconData? icon;
  final Color primary;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeTextColor = isDark ? Colors.white : primary;
    final inactiveTextColor = isDark
        ? Colors.white.withValues(alpha: 0.60)
        : const Color(0xFF475569);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark
                ? primary.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.90))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(
                color: isDark
                    ? primary.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.85),
                width: 1,
              )
            : null,
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: isDark
                      ? primary.withValues(alpha: 0.25)
                      : const Color(0xFF007AFF).withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 15,
                    color: isSelected ? activeTextColor : inactiveTextColor,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? activeTextColor : inactiveTextColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A liquid glass pill badge for status flags (Hit, Miss, Pending, Bose, etc.).
class GlassBadge extends StatelessWidget {
  const GlassBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.small = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 7 : 10,
        vertical: small ? 2.5 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.20 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.45 : 0.35),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: small ? 11 : 13, color: color),
            const SizedBox(width: 3.5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: small ? 11 : 12,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// An iOS 27 Liquid Glass Button with glossy sheen and specular gradient.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.color,
    this.textColor,
    this.isLoading = false,
    this.height = 48,
    this.borderRadius,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Color? color;
  final Color? textColor;
  final bool isLoading;
  final double height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final baseColor = color ?? themePrimary;
    final radius = borderRadius ?? BorderRadius.circular(16);

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            baseColor.withValues(alpha: 0.92),
            Color.lerp(baseColor, Colors.indigoAccent, 0.25)!.withValues(alpha: 0.95),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: baseColor.withValues(alpha: 0.38),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isLoading ? null : onPressed,
            borderRadius: radius,
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : DefaultTextStyle(
                      style: TextStyle(
                        color: textColor ?? Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                      child: child,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An iOS Settings-style grouped glass card.
///
/// Wraps children (such as [ListTile]s) in a frosted glass card and automatically
/// places a semi-transparent specular divider between items.
class GlassGroup extends StatelessWidget {
  const GlassGroup({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    this.borderRadius,
    this.dividerIndent = 16.0,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final BorderRadius? borderRadius;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFF007AFF).withValues(alpha: 0.08);

    return GlassCard(
      margin: margin,
      borderRadius: borderRadius,
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                thickness: 0.8,
                indent: dividerIndent,
                endIndent: 16,
                color: dividerColor,
              ),
          ],
        ],
      ),
    );
  }
}

/// A liquid crystal filter pill for filters, chips, and segment toggles.
class GlassFilterPill extends StatelessWidget {
  const GlassFilterPill({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
    this.count,
    this.color,
    this.small = false,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;
  final Color? color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = color ?? Theme.of(context).colorScheme.primary;

    final activeBg = isDark
        ? primary.withValues(alpha: 0.28)
        : primary.withValues(alpha: 0.16);
    final inactiveBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.55);

    final activeBorder = isDark
        ? primary.withValues(alpha: 0.60)
        : primary.withValues(alpha: 0.50);
    final inactiveBorder = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.80);

    final textColor = isSelected
        ? (isDark ? Colors.white : primary)
        : (isDark ? Colors.white.withValues(alpha: 0.70) : const Color(0xFF475569));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: isSelected ? activeBg : inactiveBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isSelected ? activeBorder : inactiveBorder,
          width: isSelected ? 1.2 : 0.9,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: primary.withValues(alpha: 0.22),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: small ? 9 : 13,
              vertical: small ? 4.5 : 7,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: small ? 12 : 14, color: textColor),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: small ? 11.5 : 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: textColor,
                    letterSpacing: 0.1,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 4.5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? primary.withValues(alpha: 0.20)
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.10)
                              : Colors.black.withValues(alpha: 0.05)),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: small ? 10 : 11,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A liquid crystal linear progress bar with specular highlight and ambient glow.
class GlassLinearProgress extends StatelessWidget {
  const GlassLinearProgress({
    super.key,
    required this.value,
    this.height = 10,
    this.color,
    this.gradient,
    this.borderRadius,
  });

  final double value;
  final double height;
  final Color? color;
  final Gradient? gradient;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = color ?? Theme.of(context).colorScheme.primary;
    final radius = borderRadius ?? BorderRadius.circular(999);
    final clamped = value.clamp(0.0, 1.0);

    final trackBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: trackBg,
        borderRadius: radius,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.60),
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            FractionallySizedBox(
              widthFactor: clamped,
              heightFactor: 1.0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: gradient ??
                      LinearGradient(
                        colors: [
                          primary.withValues(alpha: 0.85),
                          Color.lerp(primary, Colors.cyanAccent, 0.35)!,
                        ],
                      ),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.35),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
