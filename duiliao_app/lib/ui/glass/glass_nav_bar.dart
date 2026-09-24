/// Aurora Glass floating navigation bar.
///
/// A sleek, floating frosted glass pill navigation capsule suspended above
/// the bottom edge, allowing scrolled content to flow and refract beneath it.
library;

import 'dart:ui';
import 'package:flutter/material.dart';

import '../theme.dart';

class GlassNavItem {
  const GlassNavItem({
    required this.icon,
    required this.label,
    this.activeIcon,
  });

  final IconData icon;
  final String label;
  final IconData? activeIcon;
}

class GlassFloatingNavigationBar extends StatelessWidget {
  const GlassFloatingNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<GlassNavItem> items;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 18, right: 18, bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1C1C2E).withValues(alpha: 0.78)
                    : Colors.white.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.85),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.45)
                        : DuiliaoColors.auroraViolet.withValues(alpha: 0.16),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white.withValues(alpha: 0.6),
                    blurRadius: 1,
                    spreadRadius: 0.5,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _GlassNavItemButton(
                        item: items[i],
                        isSelected: i == selectedIndex,
                        primary: primary,
                        isDark: isDark,
                        onTap: () => onDestinationSelected(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavItemButton extends StatelessWidget {
  const _GlassNavItemButton({
    required this.item,
    required this.isSelected,
    required this.primary,
    required this.isDark,
    required this.onTap,
  });

  final GlassNavItem item;
  final bool isSelected;
  final Color primary;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = isDark ? DuiliaoColors.primaryDark : primary;
    final inactiveColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFF5A5670);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        splashColor: primary.withValues(alpha: 0.15),
        highlightColor: primary.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? primary.withValues(alpha: 0.22)
                    : primary.withValues(alpha: 0.12))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  isSelected ? (item.activeIcon ?? item.icon) : item.icon,
                  size: 22,
                  color: isSelected ? activeColor : inactiveColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? activeColor : inactiveColor,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
