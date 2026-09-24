/// Runtime composition for the mobile application.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/navigation.dart';
import 'core/providers.dart';
import 'core/storage/secure_store.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_providers.dart';
import 'features/auth/login_screen.dart';
import 'features/collect/collect_screen.dart';
import 'features/comparison/comparison_screen.dart';
import 'features/draws/draws_screen.dart';
import 'features/home/home_screen.dart';
import 'features/notifications/notification_service.dart';
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
    final biometric = await ref.read(secureStoreProvider).read(SecureKeys.biometricEnabled) == '1';
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
      WidgetsBinding.instance.addPostFrameCallback((_) => flushPendingDeepLink());
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
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
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
      return await ref.read(collectorRepositoryProvider).version(
            platform: ref.read(platformNameProvider),
            current: current,
          );
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
                    child: const Icon(Icons.system_update, size: 40, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  const Text('需要更新应用', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('当前版本已不再支持，请安装 ${info.latest ?? '最新版本'}。', textAlign: TextAlign.center),
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
        body: GlassBackground(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
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
    if (state == AppLifecycleState.paused && ref.read(displayPreferencesProvider).biometricEnabled) {
      ref.read(authControllerProvider).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(eventPollerProvider);
    final canOperate = ref.watch(canOperateProvider);
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

    return Scaffold(
      extendBody: true,
      body: GlassBackground(
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: GlassFloatingNavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        items: navItems,
      ),
    );
  }
}
