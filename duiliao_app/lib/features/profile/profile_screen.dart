/// Account, device and local experience settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/storage/secure_store.dart';
import '../../domain/models/user.dart';
import '../../ui/theme.dart';
import '../auth/auth_providers.dart';
import '../upgrade/github_update_service.dart';
import '../upgrade/glass_update_dialog.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final user = auth.user;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('未登录')));
    }
    final preferences = ref.watch(displayPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 96),
        children: [
          _ProfileHeader(user: user),
          const _SectionTitle('账号'),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('编辑资料'),
            subtitle: Text(user.email ?? user.phone ?? user.username ?? user.id),
            onTap: () => _editProfile(context, ref, user),
          ),
          ListTile(
            leading: const Icon(Icons.password_outlined),
            title: const Text('修改密码'),
            onTap: () => _changePassword(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: const Text('设备会话'),
            subtitle: const Text('查看并下线其他设备'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SessionsScreen()),
            ),
          ),
          const _SectionTitle('安全与显示'),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('生物识别解锁'),
            subtitle: const Text('重新打开应用时验证指纹或面容'),
            value: preferences.biometricEnabled,
            onChanged: (value) => _setBiometric(context, ref, value),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('主题'),
            trailing: DropdownButton<ThemeModePreference>(
              value: preferences.themeMode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: ThemeModePreference.system, child: Text('跟随系统')),
                DropdownMenuItem(value: ThemeModePreference.light, child: Text('浅色')),
                DropdownMenuItem(value: ThemeModePreference.dark, child: Text('深色')),
              ],
              onChanged: (value) {
                if (value != null) {
                  ref.read(displayPreferencesProvider.notifier).setThemeMode(value);
                }
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('字号'),
            subtitle: Slider(
              value: preferences.textScale,
              min: 0.9,
              max: 1.4,
              divisions: 10,
              label: '${(preferences.textScale * 100).round()}%',
              onChanged: (value) => ref
                  .read(displayPreferencesProvider.notifier)
                  .setTextScale(value),
            ),
          ),
          const _SectionTitle('应用'),
          ListTile(
            leading: const Icon(Icons.rocket_launch_outlined),
            title: const Text('在线升级 (GitHub)'),
            subtitle: FutureBuilder<String>(
              future: ref.watch(appVersionProvider.future),
              builder: (_, snap) => Text('当前版本: v${snap.data ?? '1.0.0'} · 基于 GitHub Releases'),
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _checkVersion(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('连接与规则版本'),
            subtitle: Text('服务端规则版本可在首页刷新后查看'),
            onTap: () => _showConnection(context, ref),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => ref.read(authControllerProvider).logout(),
              icon: const Icon(Icons.logout),
              label: const Text('退出登录'),
            ),
          ),
          if (auth.canOperate)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                '当前角色：${user.role?.label ?? '未知'}',
                textAlign: TextAlign.center,
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _setBiometric(BuildContext context, WidgetRef ref, bool enabled) async {
    if (enabled) {
      final auth = LocalAuthentication();
      try {
        final supported = await auth.isDeviceSupported();
        if (!supported || !await auth.authenticate(
          localizedReason: '请验证身份以开启应用锁',
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
          ),
        )) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('验证未通过，未开启生物识别')),
            );
          }
          return;
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前设备不支持生物识别')),
          );
        }
        return;
      }
    }
    ref.read(displayPreferencesProvider.notifier).setBiometricEnabled(enabled);
    await ref.read(secureStoreProvider).write(
          SecureKeys.biometricEnabled,
          enabled ? '1' : '0',
        );
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref, AppUser user) async {
    final controller = TextEditingController(text: user.displayName ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('编辑资料'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          decoration: const InputDecoration(labelText: '显示名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !context.mounted) return;
    try {
      final updated = await ref.read(authRepositoryProvider).updateProfile(displayName: value);
      ref.read(authControllerProvider).updateUser(updated);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final current = TextEditingController();
    final next = TextEditingController();
    final value = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: '当前密码')),
            const SizedBox(height: 12),
            TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: '新密码')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存')),
        ],
      ),
    );
    if (value != true) {
      current.dispose();
      next.dispose();
      return;
    }
    try {
      await ref.read(authRepositoryProvider).changePassword(
            currentPassword: current.text,
            newPassword: next.text,
          );
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密码已修改')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('修改失败：$e')));
    } finally {
      current.dispose();
      next.dispose();
    }
  }

  Future<void> _checkVersion(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('正在连接 GitHub 检查最新版本…'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final current = await ref.read(appVersionProvider.future);
      final updateService = ref.read(githubUpdateServiceProvider);

      // 1. Try GitHub Releases check first
      final ghResult = await updateService.checkUpdate(currentVersion: current);
      if (!context.mounted) return;

      if (ghResult.hasUpdate && ghResult.latestRelease != null) {
        await GlassUpdateDialog.show(context, ghResult);
        return;
      }

      // 2. If GitHub does not have a newer release, fallback to server version check
      final version = await ref.read(collectorRepositoryProvider).version(
            platform: ref.read(platformNameProvider),
            current: current,
          );
      if (!context.mounted) return;

      if (version.updateAvailable) {
        final message =
            '发现新版本 ${version.latest ?? ''}${version.releaseNotes == null ? '' : '\n${version.releaseNotes}'}';
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('版本检查'),
            content: Text(message),
            actions: [
              if (version.downloadUrl != null)
                FilledButton(
                  onPressed: () => launchUrl(
                    Uri.parse(version.downloadUrl!),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('打开下载地址'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }

      // 3. Already up to date
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('已是最新版本'),
          content: Text('当前版本 v$current 已是最新，暂无更新。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('好的'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('检查失败：$e')));
      }
    }
  }

  Future<void> _showConnection(BuildContext context, WidgetRef ref) async {
    final status = ref.read(apiClientProvider).status;
    final config = ref.read(appConfigProvider);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('连接状态'),
        content: Text('加密会话：${status.name}\n服务地址：${config.displayHost}\n规则版本：请在首页查看'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(radius: 26, child: Text(user.initial)),
          title: Text(user.name, style: context.texts.titleMedium),
          subtitle: Text('${user.role?.label ?? '未知角色'} · ${user.status?.label ?? ''}'),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(text, style: context.texts.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
      );
}

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(deviceSessionsProvider);
    final device = switch (ref.watch(deviceDescriptorProvider)) {
      AsyncData(value: final value) => value,
      _ => null,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('设备会话'),
        actions: [
          IconButton(
            tooltip: '退出所有设备',
            icon: const Icon(Icons.logout_outlined),
            onPressed: () => _logoutAll(context, ref),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (sessions) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(deviceSessionsProvider),
          child: ListView.builder(
            itemCount: sessions.length,
            itemBuilder: (_, index) {
              final session = sessions[index];
              final isThisDevice = session.isThisDevice(
                thisDeviceName: device?.deviceName,
                thisAppVersion: device?.appVersion,
              );
              return ListTile(
                leading: Icon(session.platform == 'ios' ? Icons.phone_iphone : Icons.phone_android),
                title: Text('${session.displayName}${isThisDevice ? '（当前设备）' : ''}'),
                subtitle: Text('${session.platformLabel} · ${session.appVersion ?? '未知版本'}\n${session.ipAddress ?? ''}'),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: '下线',
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                    final confirmed = await _confirm(
                      context,
                      title: isThisDevice ? '下线当前设备？' : '下线设备？',
                      message: '下线后，该设备需要重新登录。',
                    );
                    if (!confirmed || !context.mounted) return;
                    try {
                      await ref.read(authRepositoryProvider).revokeSession(session.id);
                      if (isThisDevice) {
                        await ref.read(authControllerProvider).logout();
                        if (context.mounted) Navigator.pop(context);
                      } else {
                        ref.invalidate(deviceSessionsProvider);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('下线失败：$e')),
                        );
                      }
                    }
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _logoutAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirm(
      context,
      title: '退出所有设备？',
      message: '所有已登录设备都会失效，包括当前设备。',
    );
    if (!confirmed || !context.mounted) return;
    await ref.read(authControllerProvider).logout(allDevices: true);
    if (context.mounted) Navigator.pop(context);
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认')),
            ],
          ),
        ) ??
        false;
  }
}
