/// Stable identifiers for the operator shell destinations.
library;

import 'package:flutter/material.dart';

import '../collect/collect_screen.dart';
import '../comparison/comparison_screen.dart';
import '../draws/draws_screen.dart';
import '../home/home_screen.dart';
import '../ratings/ratings_screen.dart';

enum ShellDestinationId {
  workbench,
  draws,
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

const shellDestinations = <ShellDestination>[
  ShellDestination(
    id: ShellDestinationId.workbench,
    label: '工作台',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard_rounded,
  ),
  ShellDestination(
    id: ShellDestinationId.draws,
    label: '开奖',
    icon: Icons.confirmation_number_outlined,
    selectedIcon: Icons.confirmation_number_rounded,
  ),
  ShellDestination(
    id: ShellDestinationId.comparison,
    label: '对照',
    icon: Icons.compare_arrows_outlined,
    selectedIcon: Icons.compare_arrows_rounded,
  ),
  ShellDestination(
    id: ShellDestinationId.ratings,
    label: '评级',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights_rounded,
  ),
  ShellDestination(
    id: ShellDestinationId.collect,
    label: '采集',
    icon: Icons.cloud_download_outlined,
    selectedIcon: Icons.cloud_download_rounded,
    requiresOperator: true,
  ),
];

List<ShellDestination> visibleShellDestinations(bool canOperate) =>
    shellDestinations
        .where((item) => !item.requiresOperator || canOperate)
        .toList(growable: false);

Widget shellPageFor(ShellDestinationId id) {
  return switch (id) {
    ShellDestinationId.workbench => const HomeScreen(),
    ShellDestinationId.draws => const DrawsScreen(),
    ShellDestinationId.comparison => const ComparisonScreen(),
    ShellDestinationId.ratings => const RatingsScreen(),
    ShellDestinationId.collect => const CollectScreen(),
  };
}
