/// Runtime composition for the mobile application.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/navigation.dart';
import 'core/net/api_client.dart';
import 'core/providers.dart';
import 'core/storage/secure_store.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_providers.dart';
import 'features/auth/login_screen.dart';
import 'features/ai/ai_screen.dart';
import 'features/collect/collect_screen.dart';
import 'features/comparison/comparison_screen.dart';
import 'features/consensus/consensus_screen.dart';
import 'features/notifications/messages_screen.dart';
import 'features/numbers/numbers_screen.dart';
import 'features/rules/rules_screen.dart';
import 'features/draws/draws_screen.dart';
import 'features/home/home_screen.dart';
import 'features/notifications/notification_service.dart';
import 'features/profile/profile_screen.dart';
import 'features/ratings/ratings_screen.dart';
import 'features/upgrade/github_update_service.dart';
import 'domain/models/app_event.dart';
import 'ui/glass/glass_nav_bar.dart';
import 'ui/glass/glass_widgets.dart';
import 'ui/theme.dart';

class DuiliaoApp extends ConsumerWidget {
  const DuiliaoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(displayPreferencesProvider);
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Duiliao 运营端',
      theme: DuiliaoTheme.light(),
      darkTheme: DuiliaoTheme.dark(),
      themeMode: switch (preferences.themeMode) {
        ThemeModePreference.system => ThemeMode.system,
        ThemeModePreference.light => ThemeMode.light,
        ThemeModePreference.dark => ThemeMode.dark,
      },
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(
              media.textScaler.scale(1.0) * preferences.textScale,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_restore);
  }

  Future<void> _restore() async {
    await ref.read(displayPreferencesProvider.notifier).hydrate();
    // Device metadata is diagnostic and must never hold the login gate open if
    // a platform plugin is unavailable (which also happens in widget tests).
    // It is normally ready before the user submits the form; otherwise the
    // notifier's safe fallback is used for this sign-in.
    unawaited(_loadDeviceDescriptor());
    final biometric =
        await ref.read(secureStoreProvider).read(SecureKeys.biometricEnabled) ==
        '1';
    await ref.read(authControllerProvider).restore(requireBiometric: biometric);
  }

  Future<void> _loadDeviceDescriptor() async {
    try {
      final device = await ref.read(deviceDescriptorProvider.future);
      ref.read(authControllerProvider).setDeviceDescriptor(device);
    } catch (_) {
      // Device metadata is diagnostic only; a plugin failure must not block
      // authentication.
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    if (auth.phase == AuthPhase.authenticated) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => flushPendingDeepLink(),
      );
      return const VersionGate();
    }
    return switch (auth.phase) {
      AuthPhase.restoring => const _RestoringView(),
      AuthPhase.unauthenticated => const LoginScreen(),
      AuthPhase.locked => LockScreen(onUnlock: _unlock),
      AuthPhase.authenticated => const VersionGate(),
    };
  }

  Future<bool> _unlock() async {
    try {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) return false;
      return await auth.authenticate(
        localizedReason: '请验证身份以解锁 Duiliao',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

class VersionGate extends ConsumerStatefulWidget {
  const VersionGate({super.key});

  @override
  ConsumerState<VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends ConsumerState<VersionGate> {
  late final Future<VersionInfo?> _check = _load();

  Future<VersionInfo?> _load() async {
    try {
      final current = await ref.read(appVersionProvider.future);
      return await ref
          .read(collectorRepositoryProvider)
          .version(platform: ref.read(platformNameProvider), current: current);
    } catch (_) {
      // A failed update check must not strand operators when the backend is
      // temporarily unavailable. The normal authenticated shell can retry.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<VersionInfo?>(
    future: _check,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const _RestoringView();
      }
      final info = snapshot.data;
      if (info?.updateRequired == true) {
        return _ForceUpdateView(info: info!);
      }
      return const AppShell();
    },
  );
}

class _ForceUpdateView extends StatelessWidget {
  const _ForceUpdateView({required this.info});
  final VersionInfo info;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: GlassBackground(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: DuiliaoColors.auroraGradient,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: DuiliaoColors.auroraViolet.withValues(alpha: 0.35),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.system_update,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '需要更新应用',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '当前版本已不再支持，请安装 ${info.latest ?? '最新版本'}。',
                textAlign: TextAlign.center,
              ),
              if (info.releaseNotes != null) ...[
                const SizedBox(height: 10),
                Text(info.releaseNotes!, textAlign: TextAlign.center),
              ],
              if (info.downloadUrl != null) ...[
                const SizedBox(height: 18),
                GlassButton(
                  onPressed: () {
                    final uri = Uri.tryParse(info.downloadUrl!);
                    if (uri != null &&
                        isAllowedUpdateUri(uri, allowMirrors: true)) {
                      launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Text('打开下载地址'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(info.downloadUrl!, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _RestoringView extends StatelessWidget {
  const _RestoringView();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: GlassBackground(child: Center(child: CircularProgressIndicator())),
  );
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.selectedIndex,
    required this.onSelected,
    required this.canOperate,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool canOperate;

  @override
  Widget build(BuildContext context) {
    final items = <GlassNavItem>[
      const GlassNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: '工作台',
      ),
      const GlassNavItem(
        icon: Icons.confirmation_number_outlined,
        activeIcon: Icons.confirmation_number_rounded,
        label: '开奖',
      ),
      const GlassNavItem(
        icon: Icons.compare_arrows_outlined,
        activeIcon: Icons.compare_arrows_rounded,
        label: '对照',
      ),
      const GlassNavItem(
        icon: Icons.insights_outlined,
        activeIcon: Icons.insights_rounded,
        label: '评级',
      ),
      if (canOperate)
        const GlassNavItem(
          icon: Icons.download_outlined,
          activeIcon: Icons.download_rounded,
          label: '采集',
        ),
    ];
    return Container(
      width: 92,
      margin: const EdgeInsets.fromLTRB(12, 0, 0, 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: context.isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.72),
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _RailButton(
              item: items[i],
              active: i == selectedIndex,
              onTap: () => onSelected(i),
            ),
            if (i == 0 || i == 3) const Divider(height: 16),
          ],
          const Spacer(),
          _RailButton(
            item: const GlassNavItem(
              icon: Icons.person_outline,
              activeIcon: Icons.person,
              label: '账户',
            ),
            active: false,
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.item,
    required this.active,
    required this.onTap,
  });
  final GlassNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? context.colors.primary
        : context.colors.onSurfaceVariant;
    return Material(
      color: active
          ? context.colors.primary.withValues(alpha: 0.14)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          height: 68,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                active ? (item.activeIcon ?? item.icon) : item.icon,
                color: color,
                size: 20,
              ),
              const SizedBox(height: 5),
              Text(
                item.label,
                style: context.texts.labelSmall?.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({
    required this.title,
    required this.session,
    required this.onProfile,
  });

  final String title;
  final SessionStatus? session;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final connected = session == SessionStatus.connected;
    final connecting = session == SessionStatus.connecting;
    final statusColor = connected
        ? DuiliaoColors.hit
        : connecting
        ? DuiliaoColors.warning
        : DuiliaoColors.offline;
    final statusText = connected
        ? '链路正常'
        : connecting
        ? '连接中'
        : '链路断开';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: GlassContainer(
        height: 54,
        borderRadius: BorderRadius.circular(18),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: DuiliaoColors.auroraGradient,
              ),
              alignment: Alignment.center,
              child: const Text(
                '对',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Duiliao · $title', style: context.texts.titleSmall),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        statusText,
                        style: context.texts.labelSmall?.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onProfile,
              tooltip: '个人中心',
              icon: const Icon(Icons.person_outline_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;

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
    final session = ref.watch(sessionStatusProvider).value;
    final pages = <Widget>[
      const HomeScreen(),
      const DrawsScreen(),
      const ComparisonScreen(),
      const RatingsScreen(),
      if (canOperate) const CollectScreen(),
    ];
    if (_index >= pages.length) _index = 0;

    final navItems = <GlassNavItem>[
      const GlassNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: '首页',
      ),
      const GlassNavItem(
        icon: Icons.confirmation_number_outlined,
        activeIcon: Icons.confirmation_number_rounded,
        label: '开奖',
      ),
      const GlassNavItem(
        icon: Icons.compare_arrows_outlined,
        activeIcon: Icons.compare_arrows_rounded,
        label: '对照',
      ),
      const GlassNavItem(
        icon: Icons.insights_outlined,
        activeIcon: Icons.insights_rounded,
        label: '评级',
      ),
      if (canOperate)
        const GlassNavItem(
          icon: Icons.download_outlined,
          activeIcon: Icons.download_rounded,
          label: '采集',
        ),
    ];

    final labels = <String>['工作台', '开奖', '对照', '评级', if (canOperate) '采集'];
    final currentLabel = labels[_index.clamp(0, labels.length - 1)];
    final wide = MediaQuery.sizeOf(context).width >= 760;

    final content = Expanded(
      child: IndexedStack(index: _index, children: pages),
    );
    return Scaffold(
      extendBody: !wide,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _MobileTopBar(
                title: currentLabel,
                session: session,
                onProfile: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (wide)
                      _DesktopRail(
                        selectedIndex: _index,
                        onSelected: (value) => setState(() => _index = value),
                        canOperate: canOperate,
                      ),
                    content,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : GlassFloatingNavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (value) => setState(() => _index = value),
              items: navItems,
              onMore: () => _openMore(context, canOperate),
            ),
    );
  }

  void _openMore(BuildContext context, bool canOperate) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
        child: GlassContainer(
          borderRadius: BorderRadius.circular(28),
          padding: const EdgeInsets.all(16),
          child: SafeArea(
            top: false,
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                _MoreAction(
                  icon: Icons.auto_awesome,
                  label: 'AI研判',
                  onTap: () => _push(sheetContext, const AiScreen()),
                ),
                _MoreAction(
                  icon: Icons.pie_chart_outline,
                  label: '共识',
                  onTap: () => _push(sheetContext, const ConsensusScreen()),
                ),
                _MoreAction(
                  icon: Icons.grid_view_rounded,
                  label: '号码',
                  onTap: () => _push(sheetContext, const NumbersScreen()),
                ),
                _MoreAction(
                  icon: Icons.rule_rounded,
                  label: '玩法规则',
                  onTap: () => _push(sheetContext, const RulesScreen()),
                ),
                _MoreAction(
                  icon: Icons.notifications_none_rounded,
                  label: '消息',
                  onTap: () => _push(sheetContext, const MessagesScreen()),
                ),
                _MoreAction(
                  icon: Icons.person_outline_rounded,
                  label: '个人中心',
                  onTap: () => _push(sheetContext, const ProfileScreen()),
                ),
                if (canOperate)
                  _MoreAction(
                    icon: Icons.download_outlined,
                    label: '采集',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      setState(() => _index = 4);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _push(BuildContext sheetContext, Widget page) {
    Navigator.of(sheetContext).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _MoreAction extends StatelessWidget {
  const _MoreAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: context.colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: context.colors.primary.withValues(alpha: 0.24),
              ),
            ),
            child: Icon(icon, color: context.colors.primary, size: 21),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: context.texts.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
