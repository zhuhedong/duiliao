/// The lottery number ball.
library;

import 'package:flutter/material.dart';

import '../../domain/models/draw.dart';
import '../theme.dart';

/// A single number, coloured by 波色.
///
/// Colour alone is never the only channel: the 波色 name is rendered as text
/// beneath the ball (unless [showColorName] is off) and the full attribute set is
/// attached as a semantics label. Roughly 1 in 12 men has a red-green colour
/// vision deficiency, and 红波 vs 绿波 is exactly that pairing — an operator
/// deciding whether a 波色 prediction hit cannot be asked to rely on hue.
class NumberBall extends StatelessWidget {
  const NumberBall({
    super.key,
    required this.number,
    this.bose,
    this.attr,
    this.isSpecial = false,
    this.size = 40,
    this.showColorName = true,
    this.badge,
    this.dimmed = false,
    this.onTap,
  });

  /// Zero-padded number, e.g. `08`.
  final String number;

  /// 波色 string; taken from [attr] when that is supplied.
  final String? bose;

  /// Full attributes, used for the semantics label and the 波色.
  final NumberAttr? attr;

  /// 特码 gets a ring so it is distinguishable from the six 正码 at a glance.
  final bool isSpecial;

  final double size;

  /// Whether to render the 波色 name under the ball.
  final bool showColorName;

  /// Small corner marker, e.g. the 连肖 indicator.
  final Widget? badge;

  /// Renders muted, for numbers excluded by a filter.
  final bool dimmed;

  final VoidCallback? onTap;

  String? get _bose => attr?.bose ?? bose;

  @override
  Widget build(BuildContext context) {
    final color = DuiliaoColors.forBose(_bose);
    final effective = dimmed ? color.withValues(alpha: 0.28) : color;
    final label = attr?.semanticLabel ?? _fallbackLabel();

    final ball = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: effective,
        shape: BoxShape.circle,
        border: isSpecial
            ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2.5)
            : null,
      ),
      child: Text(
        number,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.42,
          // Keeps a column of balls optically aligned.
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge == null)
          ball
        else
          Stack(
            clipBehavior: Clip.none,
            children: [
              ball,
              Positioned(right: -2, top: -2, child: badge!),
            ],
          ),
        if (showColorName && _bose != null && _bose!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _boseShort,
              style: TextStyle(
                fontSize: size * 0.26,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );

    return Semantics(
      label: label,
      button: onTap != null,
      // The visual text is redundant with the label, so hide it from a11y to
      // avoid the colour name being announced twice.
      excludeSemantics: true,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(size),
              child: content,
            ),
    );
  }

  /// `红波` -> `红`, so the caption stays narrow under the ball.
  String get _boseShort {
    final value = _bose ?? '';
    return value.endsWith('波') && value.length > 1
        ? value.substring(0, value.length - 1)
        : value;
  }

  String _fallbackLabel() {
    final parts = <String>['号码 $number'];
    if (_bose != null && _bose!.isNotEmpty) parts.add(_bose!);
    if (isSpecial) parts.add('特码');
    return parts.join('，');
  }
}

/// A row of balls for a draw: the six 正码 in drop order, then the 特码.
class DrawBallRow extends StatelessWidget {
  const DrawBallRow({
    super.key,
    required this.draw,
    this.ballSize = 40,
    this.showColorNames = true,
    this.onBallTap,
  });

  final DrawRow draw;
  final double ballSize;
  final bool showColorNames;

  /// Called with the index into [DrawRow.allNumbers]; index 6 is the 特码.
  final void Function(int index)? onBallTap;

  @override
  Widget build(BuildContext context) {
    final details = draw.ballsDetail;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < draw.balls.length; i++)
          NumberBall(
            number: draw.balls[i],
            attr: i < details.length ? details[i] : null,
            size: ballSize,
            showColorName: showColorNames,
            badge: _lianxiaoBadge(context, i < details.length ? details[i] : null),
            onTap: onBallTap == null ? null : () => onBallTap!(i),
          ),
        // A separator makes the 正码 / 特码 split explicit rather than relying on
        // the ring alone.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '+',
            style: TextStyle(
              fontSize: ballSize * 0.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        NumberBall(
          number: draw.tema,
          attr: draw.temaDetail,
          isSpecial: true,
          size: ballSize,
          showColorName: showColorNames,
          badge: _lianxiaoBadge(context, draw.temaDetail),
          onTap: onBallTap == null ? null : () => onBallTap!(draw.balls.length),
        ),
      ],
    );
  }

  /// A dot marking a ball that shares its zodiac with another in the same draw.
  Widget? _lianxiaoBadge(BuildContext context, NumberAttr? attr) {
    if (attr?.isLianxiao != true) return null;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: attr?.isAdjacentLianxiao == true
            ? DuiliaoColors.warning
            : Theme.of(context).colorScheme.tertiary,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
      ),
    );
  }
}
