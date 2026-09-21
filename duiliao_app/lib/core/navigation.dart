/// Navigation entry points shared by the app shell and notification taps.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/lottery.dart';
import '../features/collect/collect_providers.dart';
import '../features/collect/collect_screen.dart';
import '../features/comparison/comparison_screen.dart';
import '../features/consensus/consensus_screen.dart';
import '../features/draws/draw_detail_screen.dart';
import '../features/draws/draws_screen.dart';
import '../features/ratings/ratings_screen.dart';
import '../features/ratings/source_detail_screen.dart';
import '../features/auth/auth_providers.dart';
import 'providers.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Resolve the compact links stored in local notifications.
void openAppDeepLink(String? value) {
  if (value == null || value.isEmpty) return;
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) return;
  final uri = Uri.tryParse(value);
  final parts = uri?.pathSegments ?? const <String>[];
  if (parts.isEmpty) return;
  final container = ProviderScope.containerOf(navigator.context);
  Widget? page;
  switch (parts.first) {
    case 'draws':
      if (parts.length >= 3) {
        page = DrawDetailScreen(
          lottery: Lottery.parse(parts[1]),
          period: parts[2],
        );
      } else {
        page = const DrawsScreen();
      }
      break;
    case 'consensus':
      page = ConsensusScreen(
        lottery: parts.length >= 2 ? Lottery.parse(parts[1]) : null,
        initialPeriod: parts.length >= 3 ? parts[2] : null,
      );
      break;
    case 'ratings':
      if (parts.length >= 3 && parts[1] == 'source') {
        page = SourceDetailScreen(
          sourceId: parts[2],
          lottery: container.read(selectedLotteryProvider),
        );
      } else {
        page = const RatingsScreen();
      }
      break;
    case 'collect':
      if (!container.read(canOperateProvider)) return;
      if (parts.length >= 3 && parts[1] == 'job') {
        final id = int.tryParse(parts[2]);
        if (id != null) container.read(activeJobIdProvider.notifier).set(id);
      }
      page = const CollectScreen();
      break;
    case 'comparison':
      page = const ComparisonScreen();
      break;
  }
  if (page != null) {
    navigator.push(MaterialPageRoute(builder: (_) => page!));
  }
}
