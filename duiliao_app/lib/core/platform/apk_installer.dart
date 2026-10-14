/// Android-only helper to open a verified APK via FileProvider.
library;

import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('com.duiliao.duiliao_app/installer');

/// Prompt the system package installer for [apkFile].
///
/// Returns false when the platform is not Android or the channel call fails.
Future<bool> installApkFile(File apkFile) async {
  if (!Platform.isAndroid) return false;
  try {
    final ok = await _channel.invokeMethod<bool>('installApk', {
      'path': apkFile.absolute.path,
    });
    return ok ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
