/// Sign-in screen.
///
/// There is deliberately **no registration link and no password-reset link**.
/// Accounts are provisioned by an administrator in the web console: this is an
/// internal operations tool, and self-service sign-up on a sideloaded APK would
/// let anyone with the file create an account.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../../core/providers.dart';
import '../../ui/glass/glass_widgets.dart';
import '../../ui/theme.dart';
import 'auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _rememberAccount = true;

  @override
  void initState() {
    super.initState();
    _prefillIdentifier();
  }

  Future<void> _prefillIdentifier() async {
    // Convenience only: the identifier is not a secret, and re-typing it on every
    // sign-in is a real annoyance on a phone.
    final last = await ref.read(authRepositoryProvider).readLastIdentifier();
    if (last != null && mounted && _identifier.text.isEmpty) {
      _identifier.text = last;
    }
  }

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authStateProvider);
    final config = ref.watch(appConfigProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand header outside the glass panel matching login.html
                    Center(
                      child: Column(
                        children: [
                          const BrandLogoBox(
                            text: '对',
                            size: 76,
                            borderRadius: 22,
                            fontSize: 34,
                          ),
                          const SizedBox(height: 18),
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                DuiliaoColors.auroraGradient.createShader(
                                  bounds,
                                ),
                            child: const Text(
                              '对料',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '加密数据采集控制台',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 0.8,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Login Glass Panel
                    GlassContainer(
                      borderRadius: BorderRadius.circular(20),
                      blur: 24,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 22,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '欢迎回来',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: context.colors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '登录后进入你的专属数据工作台',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              '账号',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 7),
                            TextFormField(
                              controller: _identifier,
                              autofillHints: const [AutofillHints.username],
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                hintText: '请输入账号',
                                prefixIcon: Icon(Icons.person_outline, size: 18),
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? '请输入账号'
                                      : null,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '密码',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 7),
                            TextFormField(
                              controller: _password,
                              obscureText: _obscure,
                              autofillHints: const [AutofillHints.password],
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                hintText: '请输入密码',
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  size: 18,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: _obscure ? '显示密码' : '隐藏密码',
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (value) =>
                                  (value == null || value.isEmpty)
                                      ? '请输入密码'
                                      : null,
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                GestureDetector(
                                  onTap: () => setState(
                                    () => _rememberAccount = !_rememberAccount,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      GlassSwitch(
                                        value: _rememberAccount,
                                        compact: true,
                                        onChanged: (v) => setState(
                                          () => _rememberAccount = v,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '记住账号',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: context.colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          '请联系系统管理员在 Web 后台重置密码',
                                        ),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      '忘记密码?',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: context.colors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (state.errorMessage != null) ...[
                              const SizedBox(height: 14),
                              _ErrorBox(message: state.errorMessage!),
                            ],
                            const SizedBox(height: 18),
                            GlassButton(
                              onPressed: state.isSubmitting ? null : _submit,
                              isLoading: state.isSubmitting,
                              borderRadius: BorderRadius.circular(14),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('安全登录'),
                                  SizedBox(width: 6),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '账号由管理员在 Web 后台创建',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _ConnectionFooter(host: config.displayHost),
                            if (config.hasPlaceholderSecret) ...[
                              const SizedBox(height: 12),
                              const _ErrorBox(
                                message: '当前构建使用占位签名密钥，所有请求都会被服务端拒绝。'
                                    '请使用 CI 注入 APP_SIGNING_SECRET 的正式包。',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Bottom security footer matching login.html
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            '多源对料 · 一体研判',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 1.0,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        GlassChipTag(
                          icon: Icons.verified_user_outlined,
                          label: '端到端加密',
                        ),
                        GlassChipTag(
                          icon: Icons.storage_outlined,
                          label: '私有化部署',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '首次部署? ',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '初始化管理员请在服务端运行 manage_admin.py 或通过 Web 后台完成',
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Text(
                                '初始化管理员',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await ref.read(authControllerProvider).login(
          identifier: _identifier.text,
          password: _password.text,
        );
    // Navigation is driven by AuthGate watching the auth state, so there is
    // nothing to push here.
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: context.colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: context.texts.bodySmall
                  ?.copyWith(color: context.colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows which backend this build talks to, and the encrypted-session state.
/// Useful when several environments are in circulation as sideloaded APKs.
class _ConnectionFooter extends ConsumerWidget {
  const _ConnectionFooter({required this.host});

  final String host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(sessionStatusProvider).value;
    final (icon, label, color) = switch (status) {
      SessionStatus.connected => (
          Icons.lock_outline,
          '加密会话已建立',
          DuiliaoColors.hit,
        ),
      SessionStatus.connecting => (
          Icons.sync,
          '正在建立加密会话…',
          DuiliaoColors.warning,
        ),
      _ => (Icons.lock_open_outlined, '未连接', context.colors.onSurfaceVariant),
    };

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: context.texts.labelSmall?.copyWith(color: color)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          host,
          style: context.texts.labelSmall
              ?.copyWith(color: context.colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Biometric lock screen shown when the app is locked.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlock});

  final Future<bool> Function() onUnlock;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _attempting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Prompt immediately so the common case is a single tap of the sensor.
    WidgetsBinding.instance.addPostFrameCallback((_) => _attempt());
  }

  Future<void> _attempt() async {
    if (_attempting) return;
    setState(() {
      _attempting = true;
      _message = null;
    });
    final ok = await widget.onUnlock();
    if (!mounted) return;
    setState(() {
      _attempting = false;
      // On cancellation the user stays on this screen; no content is revealed.
      _message = ok ? null : '验证未通过，请重试';
    });
    if (ok) ref.read(authControllerProvider).completeUnlock();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
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
                child: const Icon(Icons.fingerprint, size: 52, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text('已锁定', style: context.texts.titleLarge),
              const SizedBox(height: 6),
              Text(
                '请通过生物识别解锁',
                style: context.texts.bodyMedium
                    ?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, style: TextStyle(color: context.colors.error)),
              ],
              const SizedBox(height: 24),
              GlassButton(
                onPressed: _attempting ? null : _attempt,
                isLoading: _attempting,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_open, size: 18, color: Colors.white),
                    SizedBox(width: 8),
                    Text('解锁'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.read(authControllerProvider).logout(),
                child: const Text('退出登录'),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
