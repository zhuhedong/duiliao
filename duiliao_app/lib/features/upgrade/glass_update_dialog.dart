/// iOS 27 Liquid Glass Update Dialog.
///
/// Features release note presentation, real-time chunked download progress,
/// mirror acceleration, and dual-mode upgrade options (in-app download & browser).
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/glass/glass_widgets.dart';
import 'github_release.dart';
import 'github_update_service.dart';

enum _DownloadStatus { idle, downloading, completed, error }

class GlassUpdateDialog extends ConsumerStatefulWidget {
  const GlassUpdateDialog({
    super.key,
    required this.result,
  });

  final UpdateCheckResult result;

  static Future<void> show(BuildContext context, UpdateCheckResult result) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => GlassUpdateDialog(result: result),
    );
  }

  @override
  ConsumerState<GlassUpdateDialog> createState() => _GlassUpdateDialogState();
}

class _GlassUpdateDialogState extends ConsumerState<GlassUpdateDialog> {
  _DownloadStatus _status = _DownloadStatus.idle;
  double _progress = 0.0;
  int _received = 0;
  int _total = 0;
  String? _errorMsg;
  File? _downloadedFile;
  bool _useMirror = false;

  GitHubRelease get _release => widget.result.latestRelease!;
  GitHubReleaseAsset? get _apk => widget.result.apkAsset;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassContainer(
          borderRadius: BorderRadius.circular(28),
          blur: 28,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with glowing icon badge and title
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          primary.withValues(alpha: 0.3),
                          primary.withValues(alpha: 0.1),
                        ],
                      ),
                      border: Border.all(
                        color: primary.withValues(alpha: 0.5),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.rocket_launch_rounded,
                      size: 24,
                      color: isDark ? const Color(0xFF60A5FA) : primary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '发现新版本',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: primary.withValues(alpha: 0.35),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                _release.tagName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? const Color(0xFF93C5FD) : primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '当前版本: v${widget.result.currentVersion}'
                          '${_apk != null ? ' · 大小: ${_apk!.formattedSize}' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Changelog / Release notes scrollable panel
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFF007AFF).withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFCBD5E1).withValues(alpha: 0.5),
                      width: 0.8,
                    ),
                  ),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: _release.body.trim().isNotEmpty
                          ? MarkdownBody(
                              data: _release.body,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(
                                  fontSize: 13,
                                  height: 1.45,
                                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                                ),
                                h1: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                h2: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                listBullet: TextStyle(
                                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                                ),
                              ),
                            )
                          : Text(
                              _release.name.isNotEmpty
                                  ? _release.name
                                  : '优化应用性能与毛玻璃界面体验。',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : const Color(0xFF334155),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Mirror acceleration toggle
              if (widget.result.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    widget.result.error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.orange.shade200 : Colors.orange.shade900,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _status == _DownloadStatus.downloading
                    ? null
                    : () => setState(() => _useMirror = !_useMirror),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        _useMirror ? Icons.check_circle : Icons.circle_outlined,
                        size: 16,
                        color: _useMirror ? primary : (isDark ? Colors.white38 : Colors.grey),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '使用国内镜像加速下载 (ghproxy)',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // State-dependent content (Download progress / Actions)
              if (_status == _DownloadStatus.downloading) ...[
                _buildProgressBar(context),
                const SizedBox(height: 14),
              ] else if (_status == _DownloadStatus.completed) ...[
                _buildCompletedView(context),
                const SizedBox(height: 14),
              ] else if (_status == _DownloadStatus.error) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _errorMsg ?? '下载出错，请使用浏览器下载',
                    style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Action buttons
              if (_status != _DownloadStatus.downloading) ...[
                if (_apk != null && widget.result.error == null)
                  GlassButton(
                    onPressed: _startDownload,
                    child: Text(_status == _DownloadStatus.completed ? '重新下载' : '在线立即升级'),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        icon: const Icon(Icons.open_in_browser, size: 16),
                        label: const Text('浏览器下载'),
                        onPressed: _openInBrowser,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('稍后'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    final receivedMb = (_received / (1024 * 1024)).toStringAsFixed(1);
    final totalMb = (_total / (1024 * 1024)).toStringAsFixed(1);
    final pct = (_progress * 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '正在下载更新包…',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color(0xFF334155),
              ),
            ),
            Text(
              '$receivedMb MB / $totalMb MB ($pct%)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            minHeight: 8,
            backgroundColor: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
            color: primary,
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedView(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 20, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '下载完成！已保存至缓存目录。',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.green.shade700,
              ),
            ),
          ),
          TextButton(
            onPressed: _openDownloadedFile,
            child: Text(
              '打开安装',
              style: TextStyle(fontWeight: FontWeight.bold, color: primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startDownload() async {
    final apk = _apk;
    final digest = apk?.sha256Digest;
    if (apk == null || digest == null) {
      if (mounted) {
        setState(() {
          _status = _DownloadStatus.error;
          _errorMsg = '更新包缺少可信 SHA-256 摘要，已拒绝安装';
        });
      }
      return;
    }
    setState(() {
      _status = _DownloadStatus.downloading;
      _progress = 0.0;
      _received = 0;
      _total = apk.size;
      _errorMsg = null;
    });

    final service = ref.read(githubUpdateServiceProvider);
    try {
      final file = await service.downloadApk(
        downloadUrl: apk.downloadUrl,
        fileName: apk.name,
        expectedSha256: digest,
        expectedSize: apk.size,
        useMirror: _useMirror,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _received = received;
              if (total > 0) {
                _total = total;
                _progress = (received / total).clamp(0.0, 1.0);
              }
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _status = _DownloadStatus.completed;
          _downloadedFile = file;
        });
        // Prompt to open/install
        await _openDownloadedFile();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _DownloadStatus.error;
          _errorMsg = '下载出错: $e';
        });
      }
    }
  }

  Future<void> _openDownloadedFile() async {
    if (_downloadedFile == null) return;
    final uri = Uri.file(_downloadedFile!.path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Fallback: launch external browser download
      await _openInBrowser();
    }
  }

  Future<void> _openInBrowser() async {
    final apkUri = _apk == null ? null : Uri.tryParse(_apk!.downloadUrl);
    final releaseUri = Uri.tryParse(_release.htmlUrl);
    final trustedApk = _apk != null &&
        _apk!.hasIntegrityDigest &&
        apkUri != null &&
        isAllowedUpdateUri(apkUri);
    Uri? targetUri = trustedApk ? apkUri : releaseUri;
    if (targetUri == null || !isAllowedUpdateUri(targetUri)) {
      if (mounted) {
        setState(() {
          _status = _DownloadStatus.error;
          _errorMsg = '没有可验证的安全下载地址';
        });
      }
      return;
    }
    if (_useMirror && trustedApk) {
      targetUri = Uri.parse('${kGitHubMirrors.first}$targetUri');
    }
    await launchUrl(targetUri, mode: LaunchMode.externalApplication);
  }
}
