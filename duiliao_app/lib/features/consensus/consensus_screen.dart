/// Consensus board screen & provider aligned with consensus-board.html.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/lottery.dart';
import '../../domain/models/consensus.dart';
import '../design/design_screens.dart';

final consensusProvider = FutureProvider.family<
  ({ConsensusResult result, bool isStale, String? storedAt}),
  ({Lottery lottery, String period, String playType})
>((ref, key) async {
  final fetched = await ref
      .read(collectorRepositoryProvider)
      .consensus(
        lottery: key.lottery.code,
        period: key.period,
        playType: key.playType,
      );
  return (
    result: fetched.value,
    isStale: fetched.isStale,
    storedAt: fetched.storedAtLabel,
  );
});

class ConsensusScreen extends StatelessWidget {
  const ConsensusScreen({super.key, this.lottery, this.initialPeriod});

  final Lottery? lottery;
  final String? initialPeriod;

  @override
  Widget build(BuildContext context) {
    return const ConsensusBoardScreen();
  }
}
