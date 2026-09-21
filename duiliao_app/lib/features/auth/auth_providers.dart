/// Auth providers and the role-gating derived state.
library;

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/providers.dart';
import '../../core/storage/secure_store.dart';
import '../../data/auth_repository.dart';
import '../../domain/models/user.dart';
import 'auth_controller.dart';

/// Device metadata, resolved once at startup.
///
/// A stable per-installation id keeps the web console's session list to one row
/// per handset instead of a new row per sign-in.
final deviceDescriptorProvider = FutureProvider<DeviceDescriptor>((ref) async {
  final store = ref.watch(secureStoreProvider);
  var deviceId = await store.read(SecureKeys.deviceId);
  if (deviceId == null || deviceId.isEmpty) {
    deviceId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await store.write(SecureKeys.deviceId, deviceId);
  }

  final packageInfo = await PackageInfo.fromPlatform();
  final appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

  String deviceName = '未知设备';
  String platform = 'android';
  try {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      deviceName = '${android.manufacturer} ${android.model}'.trim();
      platform = 'android';
    } else if (Platform.isIOS) {
      final ios = await info.iosInfo;
      deviceName = ios.utsname.machine;
      platform = 'ios';
    }
  } catch (_) {
    // Plugin unavailable (e.g. a test host). A generic name is better than
    // failing the sign-in.
  }

  return DeviceDescriptor(
    deviceId: deviceId,
    deviceName: deviceName,
    platform: platform,
    appVersion: appVersion,
  );
});

/// The running build version, for the update check and the profile screen.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// Current platform string for `/app/version`.
final platformNameProvider = Provider<String>(
  (ref) => Platform.isIOS ? 'ios' : 'android',
);

/// Auth state, and the notifier that owns the access token.
///
/// `ChangeNotifierProvider` was removed in Riverpod 3, so this is a plain
/// `NotifierProvider`; the notifier registers itself as the [ApiClient]'s token
/// provider from its `build`.
final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(
  () => AuthNotifier(deviceProvider: _fallbackDevice),
);

/// Device metadata used when the plugin lookup has not completed yet.
DeviceDescriptor _fallbackDevice() => const DeviceDescriptor(
      deviceId: 'unknown',
      deviceName: '未知设备',
      platform: 'android',
      appVersion: '0.0.0',
    );

/// The notifier itself, for calling actions such as login and logout.
final authControllerProvider = Provider<AuthNotifier>(
  (ref) => ref.read(authStateProvider.notifier),
);

/// Role of the signed-in user, or null.
final userRoleProvider = Provider<UserRole?>(
  (ref) => ref.watch(authStateProvider).role,
);

/// Whether the collection tab and mutating actions should be offered.
///
/// False while restoring and while signed out, so a privileged control never
/// flashes into view before the role is known. The server enforces the boundary
/// regardless; this only controls what is shown.
final canOperateProvider = Provider<bool>(
  (ref) => ref.watch(authStateProvider).canOperate,
);

/// The signed-in user's device sessions.
final deviceSessionsProvider = FutureProvider<List<DeviceSession>>((ref) async {
  // Rebuild when the user changes, so one account never shows another's sessions.
  ref.watch(authStateProvider);
  return ref.read(authRepositoryProvider).listSessions();
});
