/// Aurora Glass Foundation Widgets.
///
/// Provides the ambient aurora background (slowly drifting violet / fuchsia /
/// indigo / sky orbs), frosted glass cards with real backdrop blur, specular
/// 1px highlight borders, and soft brand-tinted shadows.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Ambient canvas with glowing aurora orbs beneath the frosted glass layer.
///
/// In Aurora Glass design, frosted glass requires vibrant underlying light
/// sources to refract; without ambient glowing orbs, blur over flat surfaces
/// loses depth. The orbs drift very slowly (one full loop every ~28s), like
/// the Web端的 auroraDrift animation.
class GlassBackground extends StatefulWidget {
  const GlassBackground({
    super.key,
    required this.child,
    this.showOrbs = true,
  });

  final Widget child;
  final bool showOrbs;

  @override
  State<GlassBackground> createState() => _GlassBackgroundState();
}

class _GlassBackgroundState extends State<GlassBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 28),
    );
    if (widget.showOrbs) _drift.repeat();
  }

  @override
  void didUpdateWidget(GlassBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showOrbs && !_drift.isAnimating) {
      _drift.repeat();
    } else if (!widget.showOrbs && _drift.isAnimating) {
      _drift.stop();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  /// Elliptical drift offset for an orb. [phase] spreads the orbs around the
  /// loop so they never move in lockstep; sin/cos over a repeating 0→1
  /// controller keeps the motion perfectly smooth (no turnaround snap).
  Offset _offset(double phase, double radiusX, double radiusY) {
    final t = (_drift.value + phase) * 2 * math.pi;
    return Offset(math.sin(t) * radiusX, math.cos(t) * radiusY);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor =
        isDark ? DuiliaoColors.backgroundDark : DuiliaoColors.backgroundLight;

    return ColoredBox(
      color: bgColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.showOrbs)
            AnimatedBuilder(
              animation: _drift,
              builder: (context, _) => Stack(
                fit: StackFit.expand,
                children: [
                  // Top-left violet glow
                  Positioned(
                    top: -70,
                    left: -50,
                    child: Transform.translate(
                      offset: _offset(0.0, 22, 16),
                      child: _AmbientOrb(
                        size: 330,
                        color: DuiliaoColors.auroraViolet
                            .withValues(alpha: isDark ? 0.26 : 0.18),
                      ),
                    ),
                  ),
                  // Top-right fuchsia glow
                  Positioned(
                    top: -40,
                    right: -80,
                    child: Transform.translate(
                      offset: _offset(0.25, 18, 24),
                      child: _AmbientOrb(
                        size: 290,
                        color: DuiliaoColors.auroraFuchsia
                            .withValues(alpha: isDark ? 0.22 : 0.15),
                      ),
                    ),
                  ),
                  // Bottom-right indigo glow
                  Positioned(
                    bottom: 60,
                    right: -70,
                    child: Transform.translate(
                      offset: _offset(0.5, 24, 18),
                      child: _AmbientOrb(
                        size: 310,
                        color: DuiliaoColors.auroraIndigo
                            .withValues(alpha: isDark ? 0.24 : 0.15),
                      ),
                    ),
                  ),
                  // Bottom-left sky glow
                  Positioned(
                    bottom: -60,
                    left: -80,
                    child: Transform.translate(
                      offset: _offset(0.75, 16, 22),
                      child: _AmbientOrb(
                        size: 280,
                        color: DuiliaoColors.auroraSky
                            .withValues(alpha: isDark ? 0.18 : 0.12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          widget.child,
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

/// An aurora frosted glass container with real backdrop blur, a 1px specular
/// edge highlight, and a soft brand-tinted ambient shadow.
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
    final radius = borderRadius ?? BorderRadius.circular(24);

    // Aurora glass surface — semi-transparent material that lets the
    // ambient orbs refract through.
    final defaultBg = isDark
        ? const Color(0xFF1C1C2E).withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.62);

    final effectiveBg = fillColor ?? defaultBg;

    // 1px specular highlight border
    final defaultBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.70);

    final effectiveBorderColor = borderColor ?? defaultBorderColor;

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
          // Soft ambient shadow, tinted with the brand violet in light mode
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.45)
                : DuiliaoColors.auroraViolet.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 10),
            spreadRadius: -4,
          ),
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : DuiliaoColors.auroraViolet.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
            spreadRadius: -2,
          ),
          // Subtle inner top specular highlight
          BoxShadow(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.55),
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
      child: blur > 0
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: content,
            )
          : content,
    );

    if (margin != null) {
      return Padding(padding: margin!, child: frosted);
    }
    return frosted;
  }
}

/// A drop-in replacement or wrapper for [Card] using the Aurora Glass styling.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    this.padding,
    this.borderRadius,
    this.onTap,
    this.blur = 18.0,
    this.borderColor,
    this.fillColor,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final double blur;
  final Color? borderColor;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      margin: margin,
      padding: padding,
      borderRadius: borderRadius ?? BorderRadius.circular(24),
      onTap: onTap,
      blur: blur,
      borderColor: borderColor,
      fillColor: fillColor,
      child: child,
    );
  }
}

/// A frosted segmented pill selector.
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
          ? const Color(0xFF1A1A2E).withValues(alpha: 0.55)
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
        : const Color(0xFF5A5670);

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
                  color: primary.withValues(alpha: isDark ? 0.25 : 0.16),
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

/// A glass pill badge for status flags (Hit, Miss, Pending, Bose, etc.).
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

/// An Aurora Glass Button with the signature indigo → violet → fuchsia
/// brand gradient, glossy border, and colored ambient shadow.
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

    final gradient = color == null
        ? DuiliaoColors.auroraGradient
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              baseColor.withValues(alpha: 0.92),
              Color.lerp(baseColor, DuiliaoColors.auroraFuchsia, 0.25)!
                  .withValues(alpha: 0.95),
            ],
          );

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: gradient,
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

/// A Settings-style grouped glass card.
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
        : DuiliaoColors.auroraViolet.withValues(alpha: 0.10);

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

/// A crystal filter pill for filters, chips, and segment toggles.
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
        : (isDark ? Colors.white.withValues(alpha: 0.70) : const Color(0xFF5A5670));

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

/// An aurora linear progress bar with specular highlight and ambient glow.
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

    final effectiveGradient = gradient ??
        (color == null
            ? DuiliaoColors.auroraGradient
            : LinearGradient(
                colors: [
                  primary.withValues(alpha: 0.85),
                  Color.lerp(primary, DuiliaoColors.auroraFuchsia, 0.35)!,
                ],
              ));

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
                  gradient: effectiveGradient,
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
