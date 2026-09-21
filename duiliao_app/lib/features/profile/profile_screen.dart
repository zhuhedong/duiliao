/// Account, device and local experience settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/storage/secure_store.dart';
import '../../domain/models/user.dart';
import '../../ui/glass/glass_widgets.dart';
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
      return const Scaffold(
        body: GlassBackground(child: Center(child: Text('未登录'))),
      );
    }
    final preferences = ref.watch(displayPreferencesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: GlassContainer(
                    height: 54,
                    borderRadius: BorderRadius.circular(999),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Text(
                            '控制中心与设置',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            SliverToBoxAdapter(
              child: _ProfileHeroHeader(user: user),
            ),
            
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          _SettingsIsland(
                            title: '账号与安全',
                            icon: Icons.shield_outlined,
                            children: [
                              _SettingsTile(
                                icon: Icons.edit_outlined,
                                title: '编辑资料',
                                subtitle: user.email ?? user.phone ?? user.username ?? user.id,
                                onTap: () => _editProfile(context, ref, user),
                              ),
                              _SettingsTile(
                                icon: Icons.password_outlined,
                                title: '修改密码',
                                onTap: () => _changePassword(context, ref),
                              ),
                              _SettingsTile(
                                icon: Icons.devices_outlined,
                                title: '设备会话',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const SessionsScreen()),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _SettingsIsland(
                            title: '系统与维护',
                            icon: Icons.memory_outlined,
                            children: [
                              _SettingsTile(
                                icon: Icons.rocket_launch_outlined,
                                title: '在线升级',
                                subtitle: '获取最新版本',
                                onTap: () => _checkVersion(context, ref),
                              ),
                              _SettingsTile(
                                icon: Icons.info_outline,
                                title: '连接与版本',
                                onTap: () => _showConnection(context, ref),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        children: [
                          _SettingsIsland(
                            title: '显示与偏好',
                            icon: Icons.palette_outlined,
                            children: [
                              _SettingsToggleTile(
                                icon: Icons.fingerprint,
                                title: '生物识别',
                                value: preferences.biometricEnabled,
                                onChanged: (value) => _setBiometric(context, ref, value),
                              ),
                              const SizedBox(height: 12),
                              const Text('深色模式', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              GlassSegmentedControl<ThemeModePreference>(
                                items: const [ThemeModePreference.system, ThemeModePreference.light, ThemeModePreference.dark],
                                selected: preferences.themeMode,
                                labelBuilder: (mode) => switch (mode) {
                                  ThemeModePreference.system => '跟随',
                                  ThemeModePreference.light => '浅色',
                                  ThemeModePreference.dark => '深色',
                                },
                                onChanged: (value) => ref.read(displayPreferencesProvider.notifier).setThemeMode(value),
                              ),
                              const SizedBox(height: 16),
                              const Text('字体缩放', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              Slider(
                                value: preferences.textScale,
                                min: 0.9,
                                max: 1.4,
                                divisions: 10,
                                label: '${(preferences.textScale * 100).round()}%',
                                onChanged: (value) => ref.read(displayPreferencesProvider.notifier).setTextScale(value),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          GlassContainer(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () => ref.read(authControllerProvider).logout(),
                            fillColor: DuiliaoColors.miss.withValues(alpha: 0.1),
                            borderColor: DuiliaoColors.miss.withValues(alpha: 0.3),
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.logout_rounded, size: 20, color: DuiliaoColors.miss),
                                  SizedBox(width: 8),
                                  Text('退出登录', style: TextStyle(fontWeight: FontWeight.w800, color: DuiliaoColors.miss)),
                                ],
                              ),
                            ),
                          ),
                          if (auth.canOperate)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                '当前角色：${user.role?.label ?? '未知'}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.withValues(alpha: 0.8)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
          ],
        ),
      ),
    );
  }

  // Implementation of helper methods like _setBiometric, _editProfile etc. omitted for brevity since they are identical logic
  // but included fully below.
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

class _ProfileHeroHeader extends StatelessWidget {
  const _ProfileHeroHeader({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark 
              ? [const Color(0xFF1E293B).withValues(alpha: 0.8), const Color(0xFF0F172A).withValues(alpha: 0.8)]
              : [const Color(0xFFEFF6FF).withValues(alpha: 0.8), const Color(0xFFDBEAFE).withValues(alpha: 0.8)],
        ),
        boxShadow: [
          BoxShadow(
            color: context.colors.primary.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Icon(Icons.stars_rounded, size: 140, color: context.colors.primary.withValues(alpha: 0.05)),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [context.colors.primary, Colors.purpleAccent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(color: context.colors.primary.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 8)),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    user.initial,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  user.name,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
                const SizedBox(height: 8),
                GlassBadge(label: user.role?.label ?? '未知角色', color: context.colors.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsIsland extends StatelessWidget {
  const _SettingsIsland({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.icon, required this.title, this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Text(subtitle!, style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsToggleTile extends StatelessWidget {
  const _SettingsToggleTile({required this.icon, required this.title, required this.value, required this.onChanged});
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}

// SessionsScreen remains as it was but embedded in GlassBackground. I'll just leave it mostly as-is.
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
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: GlassContainer(
                    height: 54,
                    borderRadius: BorderRadius.circular(999),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
                        const SizedBox(width: 4),
                        const Expanded(child: Text('设备会话', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                        IconButton(
                          tooltip: '退出所有设备',
                          icon: const Icon(Icons.logout_outlined),
                          onPressed: () => _logoutAll(context, ref),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            async.when(
              loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
              error: (e, _) => SliverFillRemaining(child: Center(child: Text('加载失败：$e'))),
              data: (sessions) => SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final session = sessions[index];
                    final isThisDevice = session.isThisDevice(
                      thisDeviceName: device?.deviceName,
                      thisAppVersion: device?.appVersion,
                    );
                    return GlassCard(
                      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: context.colors.primary.withValues(alpha: 0.12),
                              border: Border.all(color: context.colors.primary.withValues(alpha: 0.25)),
                            ),
                            child: Icon(
                              session.platform == 'ios' ? Icons.phone_iphone : Icons.phone_android,
                              color: context.colors.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        session.displayName,
                                        style: context.texts.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isThisDevice) ...[
                                      const SizedBox(width: 6),
                                      const GlassBadge(label: '当前设备', color: DuiliaoColors.hit, small: true),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${session.platformLabel} · ${session.appVersion ?? '未知版本'}'
                                  '${session.ipAddress == null ? '' : ' · ${session.ipAddress}'}',
                                  style: context.texts.labelSmall?.copyWith(color: context.colors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '下线',
                            icon: const Icon(Icons.logout_rounded, color: DuiliaoColors.miss, size: 22),
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
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下线失败：$e')));
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                  childCount: sessions.length,
                ),
              ),
            ),
          ],
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
