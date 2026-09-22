/// Service for checking and downloading updates via GitHub Releases.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../auth/auth_providers.dart';
import 'github_release.dart';

/// Default GitHub repository.
const String kDefaultGitHubRepo = 'zhuhedong/duiliao';

/// Acceleration proxies for regions where raw github.com is throttled.
const List<String> kGitHubMirrors = [
  'https://ghproxy.net/',
  'https://mirror.ghproxy.com/',
];

/// Maximum artifact size accepted by the in-app installer.
const int kMaxApkBytes = 200 * 1024 * 1024;

/// A deliberately small allowlist for update metadata, artifacts and mirrors.
/// The APK is still verified against GitHub's SHA-256 asset digest before it is
/// ever handed to the platform installer.
const Set<String> kAllowedUpdateHosts = {
  'api.github.com',
  'github.com',
  'ghproxy.net',
  'mirror.ghproxy.com',
};

class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

bool isAllowedUpdateUri(Uri uri, {bool allowMirrors = false}) {
  if (uri.scheme.toLowerCase() != 'https' || uri.userInfo.isNotEmpty) {
    return false;
  }
  if (uri.hasPort && uri.port != 443) return false;

  final host = uri.host.toLowerCase();
  if (host.endsWith('.githubusercontent.com')) return true;
  if (host == 'ghproxy.net' || host == 'mirror.ghproxy.com') {
    return allowMirrors;
  }
  return kAllowedUpdateHosts.contains(host);
}

bool _isValidRepository(String value) => RegExp(
      r'^[A-Za-z0-9_.-]{1,100}/[A-Za-z0-9_.-]{1,100}$',
    ).hasMatch(value);

String _normalizeSha256(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.startsWith('sha256:')
      ? normalized.substring('sha256:'.length)
      : normalized;
}

String _safeApkFileName(String raw) {
  final basename = raw.replaceAll('\\', '/').split('/').last;
  if (!RegExp(r'^[A-Za-z0-9._-]+\.apk$', caseSensitive: false).hasMatch(basename)) {
    throw const UpdateDownloadException('更新包文件名无效');
  }
  return basename;
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.hasUpdate,
    required this.currentVersion,
    this.latestRelease,
    this.apkAsset,
    this.error,
  });

  final bool hasUpdate;
  final String currentVersion;
  final GitHubRelease? latestRelease;
  final GitHubReleaseAsset? apkAsset;
  final String? error;
}

class GitHubUpdateService {
  GitHubUpdateService({
    http.Client? client,
    this.repo = kDefaultGitHubRepo,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String repo;

  /// Check GitHub Releases for the newest published release.
  Future<UpdateCheckResult> checkUpdate({
    required String currentVersion,
    String? customRepo,
    bool allowPrerelease = false,
  }) async {
    final targetRepo = customRepo ?? repo;
    try {
      final release = await fetchLatestRelease(
        targetRepo: targetRepo,
        allowPrerelease: allowPrerelease,
      );
      if (release == null) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: currentVersion,
          error: '未能从 GitHub 获取到发布版本信息',
        );
      }

      final hasUpdate = release.isNewerThan(currentVersion);
      final apk = release.findApkAsset();
      final assetError = hasUpdate ? _assetSafetyError(apk) : null;

      return UpdateCheckResult(
        hasUpdate: hasUpdate,
        currentVersion: currentVersion,
        latestRelease: release,
        apkAsset: apk,
        error: assetError,
      );
    } catch (e) {
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: currentVersion,
        error: '检查更新失败：$e',
      );
    }
  }

  /// Fetch the latest GitHub Release metadata.
  Future<GitHubRelease?> fetchLatestRelease({
    String? targetRepo,
    bool allowPrerelease = false,
  }) async {
    final r = targetRepo ?? repo;
    if (!_isValidRepository(r)) {
      throw const UpdateDownloadException('更新仓库配置无效');
    }

    final primaryUri = Uri.parse('https://api.github.com/repos/$r/releases/latest');
    final headers = {
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'Duiliao-App-Updater',
    };

    GitHubRelease? parseResponse(http.Response response) {
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final release = GitHubRelease.fromJson(decoded);
      if (release.prerelease && !allowPrerelease) return null;
      return release;
    }

    // Attempt direct GitHub API request first.
    try {
      final response = await _client.get(primaryUri, headers: headers).timeout(
            const Duration(seconds: 8),
          );
      final release = parseResponse(response);
      if (release != null || response.statusCode == 200) return release;
    } catch (_) {
      // Fall through to the allowlisted mirror proxies.
    }

    for (final mirror in kGitHubMirrors) {
      try {
        final mirrorUri = Uri.parse('${mirror}https://api.github.com/repos/$r/releases/latest');
        if (!isAllowedUpdateUri(mirrorUri, allowMirrors: true)) continue;
        final response = await _client.get(mirrorUri, headers: headers).timeout(
              const Duration(seconds: 10),
            );
        final release = parseResponse(response);
        if (release != null || response.statusCode == 200) return release;
      } catch (_) {
        // Try the next allowlisted mirror.
      }
    }
    return null;
  }

  String? _assetSafetyError(GitHubReleaseAsset? asset) {
    if (asset == null) return '发布版本没有可用的 APK';
    if (!asset.hasIntegrityDigest) return '更新包缺少可信 SHA-256 摘要，已禁用自动安装';
    if (!asset.hasSupportedContentType) return '更新包类型不受支持，已禁用自动安装';
    final uri = Uri.tryParse(asset.downloadUrl);
    if (uri == null || !isAllowedUpdateUri(uri)) {
      return '更新包下载地址不受信任，已禁用自动安装';
    }
    try {
      _safeApkFileName(asset.name);
    } on UpdateDownloadException catch (error) {
      return error.message;
    }
    if (asset.size < 0 || asset.size > kMaxApkBytes) {
      return '更新包大小超过安全限制，已禁用自动安装';
    }
    return null;
  }

  /// Download and verify an APK artifact with progress streaming.
  ///
  /// Installation is fail-closed: a caller must provide the SHA-256 digest
  /// advertised by the trusted release metadata. The response is streamed to
  /// a temporary file, size and content type are checked, and only then is it
  /// atomically moved to the final cache path.
  Future<File> downloadApk({
    required String downloadUrl,
    required String fileName,
    required String expectedSha256,
    required void Function(int receivedBytes, int totalBytes) onProgress,
    int expectedSize = 0,
    bool useMirror = false,
  }) async {
    final sourceUri = Uri.tryParse(downloadUrl);
    if (sourceUri == null || !isAllowedUpdateUri(sourceUri)) {
      throw const UpdateDownloadException('更新包下载地址不受信任');
    }

    final normalizedHash = _normalizeSha256(expectedSha256);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedHash)) {
      throw const UpdateDownloadException('更新包缺少有效的 SHA-256 摘要');
    }
    if (expectedSize < 0 || expectedSize > kMaxApkBytes) {
      throw const UpdateDownloadException('更新包大小超过安全限制');
    }

    final safeName = _safeApkFileName(fileName);
    final targetUri = useMirror
        ? Uri.parse('${kGitHubMirrors.first}$sourceUri')
        : sourceUri;
    if (!isAllowedUpdateUri(targetUri, allowMirrors: useMirror)) {
      throw const UpdateDownloadException('更新镜像地址不受信任');
    }

    final request = http.Request('GET', targetUri);
    request.headers['User-Agent'] = 'Duiliao-App-Downloader';
    final response = await _client.send(request);
    final finalUri = response.request?.url;
    if (finalUri != null && !isAllowedUpdateUri(finalUri, allowMirrors: useMirror)) {
      await response.stream.drain<void>();
      throw const UpdateDownloadException('下载被重定向到不受信任的地址');
    }
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      throw HttpException('下载失败，HTTP 状态码: ${response.statusCode}');
    }

    final contentType = response.headers['content-type']?.split(';').first.trim().toLowerCase();
    if (contentType != 'application/octet-stream' &&
        contentType != 'application/vnd.android.package-archive') {
      await response.stream.drain<void>();
      throw const UpdateDownloadException('服务器返回的内容不是 APK');
    }

    final contentLength = response.contentLength;
    final total = contentLength != null && contentLength > 0
        ? contentLength
        : expectedSize > 0
            ? expectedSize
            : 0;
    if ((contentLength != null && contentLength > kMaxApkBytes) ||
        (expectedSize > 0 &&
            contentLength != null &&
            contentLength > 0 &&
            contentLength != expectedSize)) {
      await response.stream.drain<void>();
      throw const UpdateDownloadException('下载包大小与发布信息不一致');
    }

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tempDir.path}/.duiliao-update-${DateTime.now().microsecondsSinceEpoch}.part',
    );
    final finalFile = File('${tempDir.path}/$safeName');
    IOSink? sink;
    var received = 0;
    var digestClosed = false;
    final digestSink = _DigestSink();
    final digestInput = sha256.startChunkedConversion(digestSink);

    try {
      sink = tempFile.openWrite();
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > kMaxApkBytes || (expectedSize > 0 && received > expectedSize)) {
          throw const UpdateDownloadException('下载包大小超过发布信息');
        }
        sink.add(chunk);
        digestInput.add(chunk);
        onProgress(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      digestInput.close();
      digestClosed = true;

      if (expectedSize > 0 && received != expectedSize) {
        throw const UpdateDownloadException('下载包大小与发布信息不一致');
      }
      final actualHash = digestSink.value?.toString().toLowerCase();
      if (actualHash != normalizedHash) {
        throw const UpdateDownloadException('更新包 SHA-256 校验失败，已拒绝安装');
      }

      if (await finalFile.exists()) await finalFile.delete();
      return await tempFile.rename(finalFile.path);
    } catch (_) {
      if (sink != null) await sink.close();
      rethrow;
    } finally {
      if (!digestClosed) digestInput.close();
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  void dispose() {
    _client.close();
  }
}

final githubUpdateServiceProvider = Provider<GitHubUpdateService>((ref) {
  final service = GitHubUpdateService();
  ref.onDispose(service.dispose);
  return service;
});

/// Controller for checking updates on demand or from profile screen.
final updateCheckProvider = FutureProvider.autoDispose<UpdateCheckResult>((ref) async {
  final current = await ref.watch(appVersionProvider.future);
  final service = ref.watch(githubUpdateServiceProvider);
  return service.checkUpdate(currentVersion: current);
});

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

