/// Stable identifiers for the application shell destinations aligned with app-design.
library;

import 'package:flutter/material.dart';

import '../collect/collect_screen.dart';
import '../comparison/comparison_screen.dart';
import '../design/design_screens.dart';
import '../draws/draws_screen.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../ratings/ratings_screen.dart';

enum ShellDestinationId {
  workbench,
  consensus,
  draws,
  records,
  profile,
  comparison,
  ratings,
  collect,
}

class ShellDestination {
  const ShellDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.requiresOperator = false,
  });

  final ShellDestinationId id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool requiresOperator;
}

/// Primary 5-tab bar matching app-design (.tabbar: 工作台 / 共识 / 开奖 / 记录 / 我的).
const shellDestinations = <ShellDestination>[
  ShellDestination(
    id: ShellDestinationId.workbench,
    label: '工作台',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard_rounded,
  ),
  ShellDestination(
    id: ShellDestinationId.consensus,
    label: '共识',
    icon: Icons.auto_awesome_outlined,
    selectedIcon: Icons.auto_awesome_rounded,
  ),
  ShellDestination(
    id: ShellDestinationId.draws,
    label: '开奖',
    icon: Icons.emoji_events_outlined,
    selectedIcon: Icons.emoji_events_rounded,
  ),
  ShellDestination(
    id: ShellDestinationId.records,
    label: '记录',
    icon: Icons.assignment_turned_in_outlined,
    selectedIcon: Icons.assignment_turned_in_rounded,
  ),
  ShellDestination(
    id: ShellDestinationId.profile,
    label: '我的',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
  ),
];

List<ShellDestination> visibleShellDestinations(bool canOperate) =>
    shellDestinations
        .where((item) => !item.requiresOperator || canOperate)
        .toList(growable: false);

Widget shellPageFor(ShellDestinationId id) {
  return switch (id) {
    ShellDestinationId.workbench => const HomeScreen(),
    ShellDestinationId.consensus => const ConsensusBoardScreen(),
    ShellDestinationId.draws => const DrawsScreen(),
    ShellDestinationId.records => const RecordsScreen(),
    ShellDestinationId.profile => const ProfileScreen(),
    ShellDestinationId.comparison => const ComparisonScreen(),
    ShellDestinationId.ratings => const RatingsScreen(),
    ShellDestinationId.collect => const CollectScreen(),
  };
}
