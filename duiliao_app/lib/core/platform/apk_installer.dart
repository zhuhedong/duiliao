/// Android-only helper to open a verified APK via FileProvider.
library;

import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('com.duiliao.duiliao_app/installer');

enum InstallOutcome {
  /// The system installer was opened.
  started,

  /// "Install unknown apps" is off; the settings page was opened.
  needsPermission,

  /// The APK is signed with a different key than the installed app, so the
  /// system would refuse an in-place update.
  signatureMismatch,

  /// Not Android, or the platform call failed.
  failed,
}

/// Prompt the system package installer for [apkFile].
Future<InstallOutcome> installApkFile(File apkFile) async {
  if (!Platform.isAndroid) return InstallOutcome.failed;
  try {
    final r = await _channel.invokeMethod<Object?>('installApk', {
      'path': apkFile.absolute.path,
    });
    return switch (r) {
      true || 'started' => InstallOutcome.started,
      'needs_permission' => InstallOutcome.needsPermission,
      'signature_mismatch' => InstallOutcome.signatureMismatch,
      _ => InstallOutcome.failed,
    };
  } on PlatformException {
    return InstallOutcome.failed;
  } on MissingPluginException {
    return InstallOutcome.failed;
  }
}
