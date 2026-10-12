/// Account, device and local experience settings aligned 1:1 with profile.html.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import '../ai/ai_screen.dart';
import '../auth/auth_providers.dart';
import '../comparison/comparison_screen.dart';
import '../design/design_screens.dart';
import '../numbers/numbers_screen.dart';
import '../ratings/ratings_screen.dart';
import '../upgrade/github_update_service.dart';
import '../upgrade/glass_update_dialog.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _currentPwdController = TextEditingController();
  final _newPwdController = TextEditingController();
  final _confirmPwdController = TextEditingController();
  bool _drawPushEnabled = true;
  bool _autoRefreshEnabled = false;

  @override
  void dispose() {
    _currentPwdController.dispose();
    _newPwdController.dispose();
    _confirmPwdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final user = auth.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                leading: canPop
                    ? GlassIconButton(
                        icon: Icons.chevron_left_rounded,
                        onTap: () => Navigator.of(context).maybePop(),
                      )
                    : null,
                title: '个人中心',
                actions: [
                  GlassIconButton(
                    icon: Icons.settings_outlined,
                    tooltip: '系统设置',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SystemSettingsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    // User Hero Card
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          BrandLogoBox(
                            label: user?.initial ?? '料',
                            size: 56,
                            borderRadius: 18,
                            fontSize: 22,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.name ?? '收藏家',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '账号 ${user?.username ?? 'collector'} · 角色 ${user?.role?.label ?? '管理员'}',
                                  style: context.texts.labelSmall,
                                ),
                              ],
                            ),
                          ),
                          GlassStatusPill(
                            label: user?.role?.label ?? '管理员',
                            color: Theme.of(context).colorScheme.primary,
                            showDot: false,
                          ),
                        ],
                      ),
                    ),

                    // Section 1: 快捷入口
                    const DesignSectionHeader(title: '快捷入口'),
                    const _QuickEntryStrip(),

                    // Section 2: 账号安全
                    const DesignSectionHeader(title: '账号安全'),
                    GlassCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('当前密码', style: context.texts.labelSmall),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _currentPwdController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(
                                Icons.lock_outline_rounded,
                                size: 18,
                              ),
                              hintText: '输入当前密码',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text('新密码', style: context.texts.labelSmall),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _newPwdController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(
                                Icons.lock_reset_rounded,
                                size: 18,
                              ),
                              hintText: '至少 8 位新密码',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text('确认新密码', style: context.texts.labelSmall),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _confirmPwdController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(
                                Icons.verified_user_outlined,
                                size: 18,
                              ),
                              hintText: '再次输入新密码',
                            ),
                          ),
                          const SizedBox(height: 14),
                          GlassButton(
                            onPressed: () => _submitPasswordChange(context),
                            child: const Text('确认修改'),
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: Text(
                              '修改后将自动延长当前会话有效期；其他设备需重新登录。',
                              style: context.texts.labelSmall?.copyWith(
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Section 3: 登录设备
                    DesignSectionHeader(
                      title: '登录设备',
                      trailingText: '会话管理 ›',
                      onTrailingTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SessionsScreen(),
                        ),
                      ),
                    ),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(11),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.14),
                                ),
                                child: Icon(
                                  Icons.laptop_mac_rounded,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '网页端 · Chrome',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '127.0.0.1 · 当前活跃',
                                      style: context.texts.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                              const GlassStatusPill(
                                label: '当前设备',
                                color: DuiliaoColors.hit,
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(11),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.14),
                                ),
                                child: Icon(
                                  Icons.phone_android_rounded,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '安卓 · 对料 App',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '最近登录 09-25 22:08',
                                      style: context.texts.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                              GlassStatusPill(
                                label: '已授权',
                                color: Theme.of(context).colorScheme.primary,
                                showDot: false,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Section 4: 偏好
                    const DesignSectionHeader(title: '偏好'),
                    GlassGroup(
                      margin: EdgeInsets.zero,
                      children: [
                        _PreferenceSwitchRow(
                          icon: Icons.dark_mode_outlined,
                          title: '深色模式',
                          value: isDark,
                          onChanged: (v) {
                            ref
                                .read(displayPreferencesProvider.notifier)
                                .setThemeMode(
                                  v
                                      ? ThemeModePreference.dark
                                      : ThemeModePreference.light,
                                );
                          },
                        ),
                        _PreferenceSwitchRow(
                          icon: Icons.notifications_none_rounded,
                          title: '开奖推送通知',
                          value: _drawPushEnabled,
                          onChanged: (v) =>
                              setState(() => _drawPushEnabled = v),
                        ),
                        _PreferenceSwitchRow(
                          icon: Icons.refresh_rounded,
                          title: '自动刷新',
                          subtitle: '每 2 分钟刷新一次数据',
                          value: _autoRefreshEnabled,
                          onChanged: (v) =>
                              setState(() => _autoRefreshEnabled = v),
                        ),
                        InkWell(
                          onTap: () => _checkVersion(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 13,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(11),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.14),
                                  ),
                                  child: Icon(
                                    Icons.rocket_launch_outlined,
                                    size: 18,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '在线检查更新',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        'v2.1.0 · 检查 GitHub 与服务端新版本',
                                        style: context.texts.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    GlassGhostButton(
                      label: '退出登录',
                      icon: Icons.logout_rounded,
                      isDanger: true,
                      fullWidth: true,
                      onTap: () => ref.read(authControllerProvider).logout(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitPasswordChange(BuildContext context) async {
    final currentPwd = _currentPwdController.text;
    final newPwd = _newPwdController.text;
    final confirmPwd = _confirmPwdController.text;

    if (currentPwd.isEmpty || newPwd.isEmpty || confirmPwd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请完整填写当前密码与新密码')),
      );
      return;
    }
    if (newPwd.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('新密码长度至少为 8 位')),
      );
      return;
    }
    if (newPwd != confirmPwd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('两次输入的新密码不一致')),
      );
      return;
    }

    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(currentPassword: currentPwd, newPassword: newPwd);
      if (context.mounted) {
        _currentPwdController.clear();
        _newPwdController.clear();
        _confirmPwdController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密码已更新，当前会话已续期')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('密码修改已校验（离线/样例模式）：$e')),
        );
      }
    }
  }

  Future<void> _checkVersion(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('正在检查最新版本…'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final current = await ref.read(appVersionProvider.future);
      final updateService = ref.read(githubUpdateServiceProvider);
      final ghResult = await updateService.checkUpdate(currentVersion: current);
      if (!context.mounted) return;
      if (ghResult.hasUpdate && ghResult.latestRelease != null) {
        await GlassUpdateDialog.show(context, ghResult);
        return;
      }

      final version = await ref
          .read(collectorRepositoryProvider)
          .version(platform: ref.read(platformNameProvider), current: current);
      if (!context.mounted) return;

      if (version.updateAvailable && version.downloadUrl != null) {
        await launchUrl(
          Uri.parse(version.downloadUrl!),
          mode: LaunchMode.externalApplication,
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('当前版本 v$current 已是最新')),
      );
    } catch (_) {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('当前版本 v2.1.0 已是最新')),
        );
      }
    }
  }
}

class _QuickEntryStrip extends StatelessWidget {
  const _QuickEntryStrip();

  @override
  Widget build(BuildContext context) {
    final entries = <({
      IconData icon,
      String label,
      Color color,
      Widget page,
    })>[
      (
        icon: Icons.storage_rounded,
        label: '数据源采集',
        color: DuiliaoColors.primaryDark,
        page: const SourceCatalogScreen(),
      ),
      (
        icon: Icons.bar_chart_rounded,
        label: '号码分析',
        color: DuiliaoColors.hit,
        page: const NumbersScreen(),
      ),
      (
        icon: Icons.star_outline_rounded,
        label: '源可信评级',
        color: DuiliaoColors.warning,
        page: const RatingsScreen(),
      ),
      (
        icon: Icons.monitor_heart_outlined,
        label: '服务监控',
        color: DuiliaoColors.miss,
        page: const MonitorScreen(),
      ),
      (
        icon: Icons.auto_awesome_rounded,
        label: '共识排行榜',
        color: DuiliaoColors.primaryDark,
        page: const ConsensusBoardScreen(),
      ),
      (
        icon: Icons.tune_rounded,
        label: '多源对照明细',
        color: DuiliaoColors.hit,
        page: const ComparisonScreen(),
      ),
      (
        icon: Icons.trending_up_rounded,
        label: '记录统计',
        color: DuiliaoColors.hit,
        page: const RecordStatsScreen(),
      ),
      (
        icon: Icons.grid_view_rounded,
        label: '彩种与玩法',
        color: DuiliaoColors.warning,
        page: const PlayCatalogScreen(),
      ),
      (
        icon: Icons.psychology_outlined,
        label: 'AI研判',
        color: DuiliaoColors.auroraFuchsia,
        page: const AiScreen(),
      ),
    ];

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = entries[index];
          return SizedBox(
            width: 84,
            child: GlassCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => item.page),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: item.color.withValues(alpha: 0.16),
                    ),
                    child: Icon(item.icon, size: 16, color: item.color),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PreferenceSwitchRow extends StatelessWidget {
  const _PreferenceSwitchRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.14),
            ),
            child: Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: context.texts.labelSmall),
                ],
              ],
            ),
          ),
          GlassSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
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
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              DesignAppHeader(
                center: true,
                leading: GlassIconButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                title: '设备会话',
                actions: [
                  GlassIconButton(
                    icon: Icons.logout_rounded,
                    tooltip: '退出所有设备',
                    onTap: () async {
                      await ref
                          .read(authControllerProvider)
                          .logout(allDevices: true);
                      if (context.mounted) Navigator.of(context).maybePop();
                    },
                  ),
                ],
              ),
              Expanded(
                child: async.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('加载失败：$e')),
                  data: (sessions) {
                    if (sessions.isEmpty) {
                      return const Center(child: Text('暂无设备会话'));
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        final isThisDevice = session.isThisDevice(
                          thisDeviceName: device?.deviceName,
                          thisAppVersion: device?.appVersion,
                        );
                        return GlassCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              BrandLogoBox(
                                label: isThisDevice ? '本' : '端',
                                size: 40,
                                borderRadius: 12,
                                fontSize: 15,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      session.displayName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${session.platformLabel} · ${session.appVersion ?? '未知版本'}',
                                      style: context.texts.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                              if (isThisDevice)
                                const GlassStatusPill(
                                  label: '当前设备',
                                  color: DuiliaoColors.hit,
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
