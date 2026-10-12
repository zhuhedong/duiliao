/// The lottery number ball — Aurora Glass edition.
library;

import 'package:flutter/material.dart';

import '../../domain/lottery.dart';
import '../../domain/models/draw.dart';
import '../theme.dart';

/// A single number, coloured by 波色 as a 3D translucent liquid crystal glass sphere.
///
/// Colour alone is never the only channel: the 波色 name is rendered as text
/// beneath the ball (unless [showColorName] is off) and the full attribute set is
/// attached as a semantics label. Roughly 1 in 12 men has a red-green colour
/// vision deficiency, and 红波 vs 绿波 is exactly that pairing — an operator
/// deciding whether a 波色 prediction hit cannot be asked to rely on hue.
/// Lookup table for 2026 wave colors and zodiacs when backend attr is absent.
abstract final class Lottery2026Lookup {
  static const Set<int> redNums = {
    1, 2, 7, 8, 12, 13, 18, 19, 23, 24, 29, 30, 34, 35, 40, 45, 46,
  };
  static const Set<int> blueNums = {
    3, 4, 9, 10, 14, 15, 20, 25, 26, 31, 36, 37, 41, 42, 47, 48,
  };
  static const List<String> xiaoList = [
    '鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪',
  ];
  static const Set<String> jiaXiao = {'牛', '马', '羊', '鸡', '狗', '猪'};

  static String boseForNumber(Object raw) {
    final n = raw is int ? raw : int.tryParse(raw.toString().trim());
    if (n == null || n < 1 || n > 49) return '';
    if (redNums.contains(n)) return '红波';
    if (blueNums.contains(n)) return '蓝波';
    return '绿波';
  }

  static String xiaoForNumber(Object raw, {int year = 2026}) {
    final n = raw is int ? raw : int.tryParse(raw.toString().trim());
    if (n == null || n < 1 || n > 49) return '';
    final idx = (((year - 4) % 12 - (n - 1)) % 12 + 12) % 12;
    return xiaoList[idx];
  }

  static List<String> numbersForXiao(String xiao, {int year = 2026}) {
    final target = xiao.trim();
    if (target.isEmpty) return const <String>[];
    final out = <String>[];
    for (var n = 1; n <= 49; n++) {
      if (xiaoForNumber(n, year: year) == target) {
        out.add(n.toString().padLeft(2, '0'));
      }
    }
    return out;
  }
}

class NumberBall extends StatelessWidget {
  const NumberBall({
    super.key,
    required this.number,
    this.bose,
    this.attr,
    this.isSpecial = false,
    this.isGold = false,
    this.goldBorder = false,
    this.hitHighlight = false,
    this.size = 34,
    this.showColorName = false,
    this.showCaption,
    this.caption,
    this.xiao,
    this.captionColor,
    this.captionBold = false,
    this.badge,
    this.dimmed = false,
    this.onTap,
  });

  /// Zero-padded number, e.g. `08`.
  final String number;

  /// 波色 string; taken from [attr] or inferred from [number] when omitted.
  final String? bose;

  /// Full attributes, used for the semantics label and the 波色.
  final NumberAttr? attr;

  /// 特码 gets a gold sphere or radiant halo ring so it is distinguishable from the six 正码.
  final bool isSpecial;

  /// Renders with the `.ball.gold` radial gradient from `app-design/assets/app.css`.
  final bool isGold;

  /// Renders a 2px gold border around a wave-colored ball (used in `ai-report.html`).
  final bool goldBorder;

  /// Renders a glowing green ring around a hit ball (used in `record-detail.html`).
  final bool hitHighlight;

  final double size;

  /// Whether to render the 波色 name under the ball when [caption] is not provided.
  final bool showColorName;
  final bool? showCaption;

  /// Explicit under-ball caption (e.g. zodiac `蛇` or `中`). Overrides [showColorName].
  final String? caption;
  final String? xiao;

  final Color? captionColor;
  final bool captionBold;

  /// Small corner marker, e.g. the 连肖 indicator.
  final Widget? badge;

  /// Renders muted, for numbers excluded by a filter.
  final bool dimmed;

  final VoidCallback? onTap;

  String? get _bose {
    final raw = attr?.bose ?? bose;
    if (raw != null && raw.isNotEmpty) return raw;
    final inferred = Lottery2026Lookup.boseForNumber(number);
    return inferred.isEmpty ? null : inferred;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final useGold = isGold;
    final (stopA, stopB) = DuiliaoColors.waveStopsFor(_bose, isGold: useGold);
    final effectiveA = dimmed ? stopA.withValues(alpha: 0.25) : stopA;
    final effectiveB = dimmed ? stopB.withValues(alpha: 0.25) : stopB;
    final label = attr?.semanticLabel ?? _fallbackLabel();

    Border? ballBorder;
    if (hitHighlight) {
      ballBorder = Border.all(color: DuiliaoColors.hit, width: 2.0);
    } else if (goldBorder || (isSpecial && !useGold)) {
      ballBorder = Border.all(color: DuiliaoColors.waveGoldA, width: 2.0);
    }

    // Matches `.ball` in `app-design/assets/app.css`
    final ball = Opacity(
      opacity: dimmed ? 0.35 : 1.0,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.36, -0.44),
            radius: 0.92,
            colors: [effectiveA, effectiveB],
          ),
          border: ballBorder,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dimmed ? 0.15 : 0.42),
              blurRadius: 8,
              spreadRadius: -2,
              offset: const Offset(0, 3),
            ),
            if (useGold || isSpecial)
              BoxShadow(
                color: DuiliaoColors.waveGoldA.withValues(
                  alpha: dimmed ? 0.12 : (isDark ? 0.55 : 0.40),
                ),
                blurRadius: 14,
                spreadRadius: -2,
              ),
            if (hitHighlight)
              BoxShadow(
                color: DuiliaoColors.hit.withValues(alpha: 0.45),
                blurRadius: 14,
                spreadRadius: 0,
              ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Subtle top-left inner highlight matching `inset 0 2px 3px oklch(1 0 0 / 35%)`
            Positioned(
              top: size * 0.08,
              left: size * 0.18,
              child: Container(
                width: size * 0.38,
                height: size * 0.16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(
                    Radius.elliptical(size * 0.38, size * 0.16),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: useGold ? 0.30 : 0.45),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Text(
              number,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: size <= 26 ? 11.5 : (size >= 40 ? 16.0 : 14.0),
                letterSpacing: -0.2,
                shadows: const [
                  Shadow(
                    color: Color(0x55000000),
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );

    final explicitCaption = caption ?? xiao;
    final String? effectiveCaption;
    if (showCaption == false) {
      effectiveCaption = null;
    } else if (explicitCaption != null && explicitCaption.isNotEmpty) {
      effectiveCaption = explicitCaption;
    } else if ((showCaption ?? showColorName) &&
        _bose != null &&
        _bose!.isNotEmpty) {
      effectiveCaption = _boseShort;
    } else {
      effectiveCaption = null;
    }

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
        if (effectiveCaption != null && effectiveCaption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              effectiveCaption,
              style: TextStyle(
                fontSize: 11,
                fontWeight: captionBold ? FontWeight.w700 : FontWeight.w500,
                color: captionColor ??
                    (captionBold
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );

    return Semantics(
      label: label,
      button: onTap != null,
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

/// A row of balls for a draw: the six 正码 in drop order, `+`, then the gold 特码,
/// with aligned zodiac labels directly underneath each ball matching `app-design`.
class DrawBallRow extends StatelessWidget {
  const DrawBallRow({
    super.key,
    required this.draw,
    this.ballSize = 34,
    this.showColorNames = false,
    this.showXiaoSubRow = true,
    this.goldSpecial = true,
    this.spaceBetween = true,
    this.onBallTap,
  });

  final DrawRow draw;
  final double ballSize;
  final bool showColorNames;
  final bool showXiaoSubRow;
  final bool goldSpecial;
  final bool spaceBetween;

  /// Called with the index into [DrawRow.allNumbers]; index 6 is the 特码.
  final void Function(int index)? onBallTap;

  String _xiaoAt(int index, String numStr, NumberAttr? attr) {
    final x = attr?.xiao;
    if (x != null && x.isNotEmpty) return x;
    final year = Period.year(draw.period) ?? 2026;
    return Lottery2026Lookup.xiaoForNumber(numStr, year: year);
  }

  @override
  Widget build(BuildContext context) {
    final details = draw.ballsDetail;
    final items = <Widget>[
      for (var i = 0; i < draw.balls.length; i++)
        NumberBall(
          number: draw.balls[i],
          attr: i < details.length ? details[i] : null,
          size: ballSize,
          showColorName: !showXiaoSubRow && showColorNames,
          caption: showXiaoSubRow
              ? _xiaoAt(i, draw.balls[i], i < details.length ? details[i] : null)
              : null,
          badge: _lianxiaoBadge(context, i < details.length ? details[i] : null),
          onTap: onBallTap == null ? null : () => onBallTap!(i),
        ),
      Padding(
        padding: EdgeInsets.only(bottom: (showXiaoSubRow || showColorNames) ? 16 : 0),
        child: Text(
          '+',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      NumberBall(
        number: draw.tema,
        attr: draw.temaDetail,
        isSpecial: true,
        isGold: goldSpecial,
        size: ballSize,
        showColorName: !showXiaoSubRow && showColorNames,
        caption: showXiaoSubRow ? _xiaoAt(6, draw.tema, draw.temaDetail) : null,
        captionBold: showXiaoSubRow,
        captionColor: showXiaoSubRow ? Theme.of(context).colorScheme.primary : null,
        badge: _lianxiaoBadge(context, draw.temaDetail),
        onTap: onBallTap == null ? null : () => onBallTap!(draw.balls.length),
      ),
    ];

    if (spaceBetween) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items,
      );
    }

    return Wrap(
      spacing: 7,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items,
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
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

