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
import 'features/shell/operator_shell.dart';
import 'features/upgrade/github_update_service.dart';
import 'domain/models/app_event.dart';
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
            // The preference is an app-level multiplier layered over the
            // platform setting. We normalize the result to keep the 0.9–1.4
            // control predictable across Android and iOS text scalers.
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
    try {
      await ref.read(displayPreferencesProvider.notifier).hydrate();
    } catch (_) {
      // Preferences are optional; use the in-memory defaults when storage fails.
    }
    if (!mounted) return;

    unawaited(_loadDeviceDescriptor());

    var biometric = false;
    try {
      biometric =
          await ref.read(secureStoreProvider).read(SecureKeys.biometricEnabled) ==
          '1';
    } catch (_) {
      // A storage plugin failure must not leave the auth gate restoring forever.
    }
    if (!mounted) return;

    await ref.read(authControllerProvider).restore(requireBiometric: biometric);
  }

  Future<void> _loadDeviceDescriptor() async {
    try {
      final device = await ref.read(deviceDescriptorProvider.future);
      if (!mounted) return;
      ref.read(authControllerProvider).setDeviceDescriptor(device);
    } catch (_) {
      // Diagnostic metadata must never block authentication.
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    if (auth.phase == AuthPhase.authenticated) {
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
      final ok = await auth.authenticate(
        localizedReason: '请验证身份以解锁 Duiliao',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      return ok;
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
  bool _didFlushDeepLink = false;

  Future<VersionInfo?> _load() async {
    try {
      final current = await ref.read(appVersionProvider.future);
      return await ref
          .read(collectorRepositoryProvider)
          .version(platform: ref.read(platformNameProvider), current: current);
    } catch (_) {
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
      if (!_didFlushDeepLink) {
        _didFlushDeepLink = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) flushPendingDeepLink();
        });
      }
      return const OperatorShell();
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
                  border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 1.2),
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
                    if (uri != null && isAllowedUpdateUri(uri, allowMirrors: true)) {
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
