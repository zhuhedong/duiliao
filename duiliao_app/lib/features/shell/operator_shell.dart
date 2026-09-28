/// Mobile-first authenticated application shell.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/net/api_client.dart';
import '../auth/auth_providers.dart';
import '../notifications/notification_service.dart';
import '../../features/ai/ai_screen.dart';
import '../../features/consensus/consensus_screen.dart';
import '../../features/notifications/messages_screen.dart';
import '../../features/numbers/numbers_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/rules/rules_screen.dart';
import '../../features/design/design_screens.dart';
import '../../ui/mobile/mobile_components.dart';
import '../../ui/glass/glass_nav_bar.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import 'shell_destination.dart';

class OperatorShell extends ConsumerStatefulWidget {
  const OperatorShell({super.key});

  @override
  ConsumerState<OperatorShell> createState() => _OperatorShellState();
}

class _OperatorShellState extends ConsumerState<OperatorShell>
    with WidgetsBindingObserver {
  ShellDestinationId _selected = ShellDestinationId.workbench;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        ref.read(displayPreferencesProvider).biometricEnabled) {
      ref.read(authControllerProvider).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(eventPollerProvider);
    final canOperate = ref.watch(canOperateProvider);
    final session =
        ref.watch(sessionStatusProvider).value ?? SessionStatus.disconnected;
    final wide =
        MediaQuery.sizeOf(context).width >= DuiliaoTokens.tabletBreakpoint;
    final extended =
        MediaQuery.sizeOf(context).width >= DuiliaoTokens.desktopBreakpoint;
    final destinations = visibleShellDestinations(canOperate);

    final effectiveSelected = destinations.any((item) => item.id == _selected)
        ? _selected
        : ShellDestinationId.workbench;
    // Every role-visible destination is a first-class tab on a phone. The
    // previous four-tab-plus-more layout could select 采集 in the sheet but
    // immediately render 工作台.
    final contentSelected = effectiveSelected;
    final selectedIndex = destinations.indexWhere(
      (item) => item.id == contentSelected,
    );
    final currentIndex = selectedIndex < 0 ? 0 : selectedIndex;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Row(
            children: [
              if (wide)
                _ShellRail(
                  destinations: destinations,
                  selectedIndex: currentIndex,
                  extended: extended,
                  onSelected: (index) =>
                      setState(() => _selected = destinations[index].id),
                  onMore: () => _openMore(context),
                  session: session,
                ),
              Expanded(
                child: IndexedStack(
                  index: currentIndex,
                  children: [
                    for (final item in destinations) shellPageFor(item.id),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Aurora Glass uses a floating tab bar and keeps every role-visible
        // destination directly reachable.
        bottomNavigationBar: wide
            ? null
            : _MobileNavigation(
                destinations: destinations,
                selected: contentSelected,
                onSelected: (id) => setState(() => _selected = id),
                onMore: () => _openMore(context),
              ),
      ),
    );
  }

  void _openMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _MoreSheet(
        onSelectDestination: (id) {
          Navigator.of(sheetContext).pop();
          if (!mounted) return;
          setState(() => _selected = id);
        },
        onOpen: (page) {
          Navigator.of(sheetContext).pop();
          if (!mounted) return;
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
        },
      ),
    );
  }
}

class _MobileNavigation extends StatelessWidget {
  const _MobileNavigation({
    required this.destinations,
    required this.selected,
    required this.onSelected,
    required this.onMore,
  });

  final List<ShellDestination> destinations;
  final ShellDestinationId selected;
  final ValueChanged<ShellDestinationId> onSelected;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = destinations.indexWhere(
      (item) => item.id == selected,
    );
    return Semantics(
      container: true,
      label: '主导航',
      child: GlassFloatingNavigationBar(
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        onDestinationSelected: (index) => onSelected(destinations[index].id),
        onMore: onMore,
        items: [
          for (final item in destinations)
            GlassNavItem(
              icon: item.icon,
              activeIcon: item.selectedIcon,
              label: item.label,
            ),
        ],
      ),
    );
  }
}

class _ShellRail extends StatelessWidget {
  const _ShellRail({
    required this.destinations,
    required this.selectedIndex,
    required this.extended,
    required this.onSelected,
    required this.onMore,
    required this.session,
  });

  final List<ShellDestination> destinations;
  final int selectedIndex;
  final bool extended;
  final ValueChanged<int> onSelected;
  final VoidCallback onMore;
  final SessionStatus session;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (session) {
      SessionStatus.connected => '链路正常',
      SessionStatus.connecting => '连接中',
      SessionStatus.disconnected => '链路断开',
    };
    return NavigationRail(
      extended: extended,
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      groupAlignment: -0.8,
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
        child: Column(
          children: [
            Semantics(
              label: '对料工作台',
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.colors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '对',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            if (extended) ...[
              const SizedBox(height: 10),
              Text('对料', style: context.texts.titleSmall),
              const SizedBox(height: 5),
              Text(statusLabel, style: context.texts.labelSmall),
            ],
          ],
        ),
      ),
      trailing: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: IconButton(
          tooltip: '更多功能',
          onPressed: onMore,
          icon: const Icon(Icons.more_horiz),
        ),
      ),
      destinations: [
        for (final item in destinations)
          NavigationRailDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
            label: Text(item.label),
          ),
      ],
    );
  }
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.onSelectDestination, required this.onOpen});

  final ValueChanged<ShellDestinationId> onSelectDestination;
  final void Function(Widget page) onOpen;

  @override
  Widget build(BuildContext context) {
    final items =
        <
          ({
            IconData icon,
            String label,
            Widget? page,
            ShellDestinationId? destination,
          })
        >[
          (
            icon: Icons.auto_awesome,
            label: 'AI研判',
            page: const AiScreen(),
            destination: null,
          ),
          (
            icon: Icons.pie_chart_outline,
            label: '共识',
            page: const ConsensusScreen(),
            destination: null,
          ),
          (
            icon: Icons.leaderboard_outlined,
            label: '共识榜',
            page: const ConsensusBoardScreen(),
            destination: null,
          ),
          (
            icon: Icons.grid_view_rounded,
            label: '号码',
            page: const NumbersScreen(),
            destination: null,
          ),
          (
            icon: Icons.rule_rounded,
            label: '玩法规则',
            page: const RulesScreen(),
            destination: null,
          ),
          (
            icon: Icons.notifications_none_rounded,
            label: '消息',
            page: const MessagesScreen(),
            destination: null,
          ),
          (
            icon: Icons.person_outline_rounded,
            label: '个人中心',
            page: const ProfileScreen(),
            destination: null,
          ),
          (
            icon: Icons.storage_outlined,
            label: '数据源',
            page: const SourceCatalogScreen(),
            destination: null,
          ),
          (
            icon: Icons.monitor_heart_outlined,
            label: '服务监控',
            page: const MonitorScreen(),
            destination: null,
          ),
          (
            icon: Icons.receipt_long_outlined,
            label: '记录',
            page: const RecordsScreen(),
            destination: null,
          ),
          (
            icon: Icons.tune_rounded,
            label: '系统设置',
            page: const SystemSettingsScreen(),
            destination: null,
          ),
        ];

    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: MobileSurface(
            padding: const EdgeInsets.all(DuiliaoTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('更多功能', style: context.texts.titleMedium),
                const SizedBox(height: DuiliaoTokens.space3),
                Expanded(
                  child: GridView.builder(
                    itemCount: items.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          mainAxisExtent: 78,
                        ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Semantics(
                        button: true,
                        label: item.label,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            final destination = item.destination;
                            if (destination != null) {
                              onSelectDestination(destination);
                            } else if (item.page != null) {
                              onOpen(item.page!);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(item.icon, color: context.colors.primary),
                                const SizedBox(height: 6),
                                Text(
                                  item.label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.texts.labelSmall,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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
