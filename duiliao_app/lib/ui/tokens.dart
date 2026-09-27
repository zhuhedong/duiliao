/// Shared spacing, sizing and responsive tokens for the mobile client.
library;

import 'package:flutter/material.dart';

abstract final class DuiliaoTokens {
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space7 = 32;

  static const double radiusSmall = 10;
  static const double radiusMedium = 14;
  static const double radiusLarge = 20;
  static const double radiusXLarge = 28;

  static const double minTouchTarget = 48;
  static const double contentMaxWidth = 1180;
  static const double tabletBreakpoint = 700;
  static const double desktopBreakpoint = 1080;

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
}

class DuiliaoPage extends StatelessWidget {
  const DuiliaoPage({super.key, required this.child, this.maxWidth = DuiliaoTokens.contentMaxWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
