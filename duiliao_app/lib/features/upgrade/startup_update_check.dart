/// Automatic (throttled) and manual update checks, ported from deeix-client.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'github_update_service.dart';
import 'glass_update_dialog.dart';
import 'update_policy.dart';

/// Runs a check and shows [GlassUpdateDialog] when an update is offered.
///
/// Automatic checks ([manual] false) are throttled, silent on errors and
/// respect a skipped version. Manual checks always report the outcome,
/// including the real error message.
Future<void> runUpdateCheck(
  BuildContext context,
  WidgetRef ref, {
  bool manual = false,
}) async {
  final messenger = manual ? ScaffoldMessenger.maybeOf(context) : null;
  UpdatePrefs? prefs;
  try {
    prefs = await UpdatePrefs.load();
  } catch (_) {
    prefs = null;
  }
  final now = DateTime.now();
  if (!manual &&
      (prefs == null || !shouldAutoCheck(now: now, lastCheck: prefs.lastCheck))) {
    return;
  }

  final String current;
  try {
    current = await ref.read(appVersionProvider.future);
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('无法读取当前版本：$e')));
    return;
  }
  final result = await ref
      .read(githubUpdateServiceProvider)
      .checkUpdate(currentVersion: current);
  final fetched = result.latestRelease != null || result.error == null;
  if (fetched) await prefs?.markChecked(now);
  if (!context.mounted) return;

  final release = result.latestRelease;
  if (result.hasUpdate && release != null) {
    if (!shouldPrompt(
      latestVersion: release.versionString,
      ignoredVersion: prefs?.ignoredVersion,
      manual: manual,
    )) {
      return;
    }
    await GlassUpdateDialog.show(
      context,
      result,
      onIgnore: prefs == null ? null : () => prefs!.ignore(release.versionString),
    );
    return;
  }
  messenger?.showSnackBar(
    SnackBar(
      content: Text(
        result.error ?? '当前版本 v${result.currentVersion} 已是最新',
      ),
    ),
  );
}

/// Wraps the signed-in shell: one throttled automatic check per launch,
/// shortly after the first frame. Android only (iOS cannot side-load).
class StartupUpdateCheck extends ConsumerStatefulWidget {
  const StartupUpdateCheck({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<StartupUpdateCheck> createState() => _StartupUpdateCheckState();
}

class _StartupUpdateCheckState extends ConsumerState<StartupUpdateCheck> {
  static bool _ranThisLaunch = false;

  @override
  void initState() {
    super.initState();
    if (_ranThisLaunch || !Platform.isAndroid) return;
    _ranThisLaunch = true;
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) runUpdateCheck(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
