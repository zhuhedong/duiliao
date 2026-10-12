/// Aurora Glass Foundation Widgets.
///
/// Provides the ambient aurora background (slowly drifting violet / fuchsia /
/// indigo / sky orbs), frosted glass cards with real backdrop blur, specular
/// 1px highlight borders, and soft brand-tinted shadows.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
    this.showGrid = true,
  });

  final Widget child;
  final bool showOrbs;
  final bool showGrid;

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
      duration: const Duration(seconds: 36),
    );
    if (widget.showOrbs &&
        !kIsWeb &&
        !WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations) {
      _drift.repeat();
    }
  }

  @override
  void didUpdateWidget(GlassBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showOrbs &&
        !_drift.isAnimating &&
        !kIsWeb &&
        !WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations) {
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
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final bgColor = isDark
        ? DuiliaoColors.backgroundDark
        : DuiliaoColors.backgroundLight;

    return ColoredBox(
      color: bgColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.showGrid)
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _AuroraGridPainter()),
              ),
            ),
          if (widget.showOrbs && !reduceMotion)
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
                        color: DuiliaoColors.auroraViolet.withValues(
                          alpha: isDark ? 0.26 : 0.18,
                        ),
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
                        color: DuiliaoColors.auroraFuchsia.withValues(
                          alpha: isDark ? 0.22 : 0.15,
                        ),
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
                        color: DuiliaoColors.auroraIndigo.withValues(
                          alpha: isDark ? 0.24 : 0.15,
                        ),
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
                        color: DuiliaoColors.auroraSky.withValues(
                          alpha: isDark ? 0.18 : 0.12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.showOrbs && reduceMotion)
            const Positioned(
              top: -70,
              left: -50,
              child: _AmbientOrb(size: 330, color: DuiliaoColors.auroraViolet),
            ),
          widget.child,
        ],
      ),
    );
  }
}

class _AuroraGridPainter extends CustomPainter {
  const _AuroraGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = DuiliaoColors.primary.withValues(alpha: 0.035)
      ..strokeWidth = 0.6;
    const gap = 44.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    final radius = borderRadius ?? BorderRadius.circular(20);

    // Aurora glass surface — semi-transparent material that lets the
    // ambient orbs refract through.
    final defaultBg = isDark
        ? const Color(0xFF2E2946).withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.62);

    final effectiveBg = fillColor ?? defaultBg;

    // 1px specular highlight border
    final defaultBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.70);

    final effectiveBorderColor = borderColor ?? defaultBorderColor;

    Widget inner = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    if (onTap != null) {
      inner = InkWell(
        borderRadius: radius,
        onTap: onTap,
        splashColor: Theme.of(context).colorScheme.primary
            .withValues(alpha: 0.12),
        highlightColor: Theme.of(context).colorScheme.primary
            .withValues(alpha: 0.06),
        child: inner,
      );
    }

    final Widget content = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: radius,
        border: Border.all(color: effectiveBorderColor, width: borderWidth),
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
      child: Material(
        type: MaterialType.transparency,
        child: inner,
      ),
    );

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
      borderRadius: borderRadius ?? BorderRadius.circular(20),
      onTap: onTap,
      blur: blur,
      borderColor: borderColor,
      fillColor: fillColor,
      child: child,
    );
  }
}

/// A frosted segmented pill selector matching `.segmented` & `.seg-on` in `app.css`.
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
      blur: 12,
      borderRadius: BorderRadius.circular(13),
      borderWidth: 1.0,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.white.withValues(alpha: 0.65),
      borderColor: isDark
          ? Colors.white.withValues(alpha: 0.07)
          : Colors.white.withValues(alpha: 0.80),
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
    const activeTextColor = Colors.white;
    final inactiveTextColor = isDark
        ? Colors.white.withValues(alpha: 0.62)
        : const Color(0xFF5A5670);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: isSelected ? DuiliaoColors.auroraGradient : null,
        borderRadius: BorderRadius.circular(10),
        border: isSelected
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 0.9,
              )
            : null,
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: DuiliaoColors.auroraViolet.withValues(alpha: 0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected ? activeTextColor : inactiveTextColor,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? activeTextColor : inactiveTextColor,
                    ),
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
              Color.lerp(
                baseColor,
                DuiliaoColors.auroraFuchsia,
                0.25,
              )!.withValues(alpha: 0.95),
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

/// A compact panel matching the web dashboard's SectionCard/PanelShell.
class GlassSectionCard extends StatelessWidget {
  const GlassSectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.action,
    this.padding = const EdgeInsets.all(18),
    this.margin,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Widget? action;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      margin: margin,
      borderRadius: BorderRadius.circular(24),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || action != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: context.colors.primary),
                  const SizedBox(width: 7),
                ],
                if (title != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title!, style: context.texts.titleSmall),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              subtitle!,
                              style: context.texts.labelSmall,
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  const Spacer(),
                ?action,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

enum GlassPillTone { primary, success, warning, danger, neutral }

class GlassStatusPill extends StatelessWidget {
  const GlassStatusPill({
    super.key,
    required this.label,
    this.color,
    this.tone,
    this.icon,
    this.dot = true,
    this.showDot,
    this.pulse = false,
    this.compact = false,
  });

  final String label;
  final Color? color;
  final GlassPillTone? tone;
  final IconData? icon;
  final bool dot;
  final bool? showDot;
  final bool pulse;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ??
        switch (tone) {
          GlassPillTone.primary => context.colors.primary,
          GlassPillTone.success => DuiliaoColors.hit,
          GlassPillTone.warning => DuiliaoColors.warning,
          GlassPillTone.danger => DuiliaoColors.miss,
          GlassPillTone.neutral => context.colors.onSurfaceVariant,
          null => context.colors.primary,
        };
    final effectiveDot = showDot ?? dot;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2 : 3.5,
      ),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: context.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: effectiveColor.withValues(alpha: context.isDark ? 0.35 : 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (effectiveDot)
            pulse
                ? _PulsingDot(color: effectiveColor)
                : Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: effectiveColor,
                      shape: BoxShape.circle,
                    ),
                  ),
          if (icon != null) Icon(icon, size: 12, color: effectiveColor),
          if (effectiveDot || icon != null) const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.labelSmall?.copyWith(
                color: effectiveColor,
                fontSize: compact ? 10.0 : 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (!kIsWeb &&
        !WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final alpha = 1.0 - (_controller.value * 0.65);
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: alpha),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

class GlassToolbar extends StatelessWidget {
  const GlassToolbar({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(14, 8, 14, 8),
  });

  final Widget child;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      margin: margin,
      borderRadius: BorderRadius.circular(16),
      blur: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: child,
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
    this.borderColor,
    this.dividerIndent = 16.0,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final BorderRadius? borderRadius;
  final Color? borderColor;
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
      borderColor: borderColor,
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
        : (isDark
              ? Colors.white.withValues(alpha: 0.70)
              : const Color(0xFF5A5670));

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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
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
    this.height = 6,
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
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    final effectiveGradient =
        gradient ??
        (color == null
            ? DuiliaoColors.auroraGradient
            : LinearGradient(
                colors: [
                  primary.withValues(alpha: 0.90),
                  Color.lerp(primary, Colors.white, 0.18)!,
                ],
              ));

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: trackBg,
        borderRadius: radius,
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------- //
// app-design Shared Components (.ztag, .chip, .btn-icon, .btn-ghost, .switch,
// .section-title, .app-header, .glass-subtle, .brand-logo, .hit-mark)
// --------------------------------------------------------------------------- //

enum ZTagVariant { neutral, primary, success, hit, warning, danger, miss }

/// Matches `.ztag` in `app-design/assets/app.css`:
/// `padding: 2px 8px; border-radius: 7px; font-size: 10.5px; font-weight: 600`
class ZTag extends StatelessWidget {
  const ZTag({
    super.key,
    required this.label,
    this.isPrimary = false,
    this.variant,
    this.color,
    this.fontSize = 10.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
    this.onTap,
  });

  final String label;
  final bool isPrimary;
  final ZTagVariant? variant;
  final Color? color;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final variantColor = switch (variant) {
      ZTagVariant.primary => Theme.of(context).colorScheme.primary,
      ZTagVariant.success || ZTagVariant.hit => DuiliaoColors.hit,
      ZTagVariant.warning => DuiliaoColors.warning,
      ZTagVariant.danger || ZTagVariant.miss => DuiliaoColors.miss,
      ZTagVariant.neutral || null => null,
    };
    final tone =
        color ??
        variantColor ??
        (isPrimary ? Theme.of(context).colorScheme.primary : null);
    final bgColor = tone != null
        ? tone.withValues(alpha: isDark ? 0.14 : 0.10)
        : (isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.04));
    final borderColor = tone != null
        ? tone.withValues(alpha: 0.35)
        : (isDark
              ? Colors.white.withValues(alpha: 0.09)
              : Colors.black.withValues(alpha: 0.10));
    final textColor =
        tone ?? Theme.of(context).colorScheme.onSurfaceVariant;

    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );

    if (onTap == null) return box;
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: box,
    );
  }
}

/// Matches `.chip` in `app-design/assets/app.css`:
/// `padding: 4px 10px; border-radius: 99px; font-size: 11px; font-weight: 500`
class GlassChipTag extends StatelessWidget {
  const GlassChipTag({
    super.key,
    required this.label,
    this.icon,
    this.trailingText,
    this.trailingColor,
    this.selected = false,
    this.active,
    this.compact = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final String? trailingText;
  final Color? trailingColor;
  final bool selected;
  final bool? active;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final isSelected = active ?? selected;
    final bg = isSelected
        ? primary.withValues(alpha: isDark ? 0.24 : 0.14)
        : (isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04));
    final border = isSelected
        ? primary.withValues(alpha: 0.48)
        : (isDark
              ? Colors.white.withValues(alpha: 0.09)
              : Colors.black.withValues(alpha: 0.10));
    final fg = isSelected
        ? primary
        : Theme.of(context).colorScheme.onSurfaceVariant;

    final pill = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4.5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10.5 : 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: fg,
            ),
          ),
          if (trailingText != null) ...[
            const SizedBox(width: 4),
            Text(
              trailingText!,
              style: TextStyle(
                fontSize: compact ? 10.5 : 11,
                fontWeight: FontWeight.w600,
                color: trailingColor ?? fg,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return pill;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: pill,
    );
  }
}

/// Matches `.btn-icon` in `app-design/assets/app.css`:
/// `width: 36px; height: 36px; border-radius: 12px; border: 1px solid var(--border)`
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.size = 36,
    this.iconSize = 18,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.09)
                  : Colors.black.withValues(alpha: 0.10),
            ),
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Matches `.btn-ghost` in `app-design/assets/app.css`:
/// `padding: 9px 14px; border-radius: 12px; border: 1px solid var(--border-strong); background: var(--glass-bg-subtle)`
class GlassGhostButton extends StatelessWidget {
  const GlassGhostButton({
    super.key,
    required this.label,
    this.onTap,
    this.onPressed,
    this.icon,
    this.isDanger = false,
    this.fullWidth = false,
    this.compact = false,
    this.padding,
    this.fontSize,
  });

  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isDanger;
  final bool fullWidth;
  final bool compact;
  final EdgeInsetsGeometry? padding;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDanger
        ? DuiliaoColors.miss
        : Theme.of(context).colorScheme.onSurface;
    final effectivePadding =
        padding ??
        EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 6 : 9,
        );
    final effectiveFontSize = fontSize ?? (compact ? 11.5 : 13.0);
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap ?? onPressed,
          child: Container(
            padding: effectivePadding,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.16)
                    : Colors.black.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: compact ? 12 : 14, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: effectiveFontSize,
                    fontWeight: FontWeight.w500,
                    color: fg,
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

/// Matches `.switch` in `app-design/assets/app.css`:
/// `width: 44px; height: 26px; border-radius: 99px` with aurora gradient when `.on`.
class GlassSwitch extends StatelessWidget {
  const GlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = compact ? 34.0 : 44.0;
    final height = compact ? 20.0 : 26.0;
    final thumbSize = compact ? 14.0 : 20.0;

    return Semantics(
      toggled: value,
      button: true,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: width,
          height: height,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: value ? DuiliaoColors.auroraGradient : null,
            color: value
                ? null
                : (isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.12)),
            border: Border.all(
              color: value
                  ? Colors.transparent
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.black.withValues(alpha: 0.15)),
            ),
          ),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: thumbSize,
            height: thumbSize,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Matches `.section-title` in `app-design/assets/app.css`:
/// `<span class="st-dot"></span>Title <a class="st-link">Action ›</a>`
class DesignSectionHeader extends StatelessWidget {
  const DesignSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.trailingText,
    this.onActionTap,
    this.onTrailingTap,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(2, 18, 2, 10),
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final String? trailingText;
  final VoidCallback? onActionTap;
  final VoidCallback? onTrailingTap;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final effectiveLabel = actionLabel ?? trailingText;
    final effectiveTap = onActionTap ?? onTrailingTap;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: DuiliaoColors.auroraGradient,
              boxShadow: [
                BoxShadow(
                  color: DuiliaoColors.auroraViolet.withValues(alpha: 0.60),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            fit: (subtitle != null && subtitle!.isNotEmpty)
                ? FlexFit.loose
                : FlexFit.tight,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          if (trailing != null)
            trailing!
          else if (effectiveLabel != null)
            effectiveTap != null
                ? InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: effectiveTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            effectiveLabel,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: primary,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.chevron_right, size: 14, color: primary),
                        ],
                      ),
                    ),
                  )
                : Text(
                    effectiveLabel,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
        ],
      ),
    );
  }
}

/// Matches `.app-header` and `.app-header.center` in `app-design/assets/app.css`.
class DesignAppHeader extends StatelessWidget {
  const DesignAppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingSubtitle,
    this.center = false,
    this.centerTitle,
    this.showBack = false,
    this.onBack,
    this.leading,
    this.trailing,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 12),
  });

  final String title;
  final String? subtitle;
  final String? leadingSubtitle;
  final bool center;
  final bool? centerTitle;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? leading;
  final Widget? trailing;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isCenter = centerTitle ?? center;
    final allActions = <Widget>[
      ...actions,
      ?trailing,
    ];

    if (isCenter) {
      return Padding(
        padding: padding,
        child: SizedBox(
          height: subtitle != null ? 42 : 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (leading != null)
                Align(alignment: Alignment.centerLeft, child: leading!)
              else if (showBack || Navigator.of(context).canPop())
                Align(
                  alignment: Alignment.centerLeft,
                  child: GlassIconButton(
                    icon: Icons.chevron_left_rounded,
                    iconSize: 22,
                    tooltip: '返回',
                    onTap: onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              if (allActions.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < allActions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        allActions[i],
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 10),
          ] else if (showBack) ...[
            GlassIconButton(
              icon: Icons.chevron_left_rounded,
              iconSize: 22,
              tooltip: '返回',
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leadingSubtitle != null && leadingSubtitle!.isNotEmpty)
                  Text(
                    leadingSubtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < allActions.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            allActions[i],
          ],
        ],
      ),
    );
  }
}

/// Matches `.glass-subtle` in `app-design/assets/app.css`.
class GlassSubtleBox extends StatelessWidget {
  const GlassSubtleBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.margin,
    this.borderRadius,
    this.borderColor,
    this.selected = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Object? borderRadius;
  final Color? borderColor;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final radius = switch (borderRadius) {
      final BorderRadius r => r,
      final num n => BorderRadius.circular(n.toDouble()),
      _ => BorderRadius.circular(14),
    };

    Widget box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: radius,
        border: Border.all(
          color: borderColor ??
              (selected
                  ? primary.withValues(alpha: 0.60)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.08))),
          width: selected ? 1.2 : 1.0,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: primary.withValues(alpha: 0.18),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (onTap != null) {
      box = Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: radius, onTap: onTap, child: box),
      );
    }

    if (margin != null) {
      return Padding(padding: margin!, child: box);
    }
    return box;
  }
}

/// Matches `.brand-logo` in `app-design/assets/app.css`.
class BrandLogoBox extends StatelessWidget {
  const BrandLogoBox({
    super.key,
    this.text,
    this.label,
    this.size = 38,
    this.borderRadius = 12,
    this.fontSize = 16,
  });

  final String? text;
  final String? label;
  final double size;
  final double borderRadius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final effectiveText = text ?? label ?? '对';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: DuiliaoColors.auroraGradient,
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: DuiliaoColors.auroraViolet.withValues(alpha: 0.50),
            blurRadius: 18,
            offset: const Offset(0, 6),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Text(
        effectiveText,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

enum HitMarkStatus { hit, miss, neutral, pending, fake }

/// Matches `.hit-mark` in `app-design/assets/app.css`:
/// `20x20px` circular badge for hit (`✓`/`中`), miss (`✕`/`挂`), or neutral (`–`).
class HitMarkBadge extends StatelessWidget {
  const HitMarkBadge({
    super.key,
    this.isHit,
    this.hit,
    this.status,
    this.label,
    this.size = 20,
  });

  /// `true` = hit (green), `false` = miss (red), `null` = neutral (`–`).
  final bool? isHit;
  final bool? hit;
  final HitMarkStatus? status;
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final effectiveIsHit = status != null
        ? switch (status!) {
            HitMarkStatus.hit => true,
            HitMarkStatus.miss => false,
            HitMarkStatus.neutral ||
            HitMarkStatus.pending ||
            HitMarkStatus.fake => null,
          }
        : (isHit ?? hit);
    final tone = status == HitMarkStatus.fake
        ? DuiliaoColors.warning
        : switch (effectiveIsHit) {
            true => DuiliaoColors.hit,
            false => DuiliaoColors.miss,
            null => Theme.of(context).colorScheme.onSurfaceVariant,
          };
    final text =
        label ??
        (status == HitMarkStatus.fake
            ? '!'
            : switch (effectiveIsHit) {
                true => '✓',
                false => '✕',
                null => '–',
              });
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tone.withValues(alpha: 0.16),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: size * 0.55,
          fontWeight: FontWeight.w700,
          color: tone,
        ),
      ),
    );
  }
}

