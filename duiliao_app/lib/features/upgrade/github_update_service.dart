/// Service for checking and downloading updates via GitHub Releases.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  }) async {
    final targetRepo = customRepo ?? repo;
    try {
      final release = await fetchLatestRelease(targetRepo: targetRepo);
      if (release == null) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: currentVersion,
          error: '未能从 GitHub 获取到发布版本信息',
        );
      }

      final hasUpdate = release.isNewerThan(currentVersion);
      final apk = release.findApkAsset();

      return UpdateCheckResult(
        hasUpdate: hasUpdate,
        currentVersion: currentVersion,
        latestRelease: release,
        apkAsset: apk,
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
  Future<GitHubRelease?> fetchLatestRelease({String? targetRepo}) async {
    final r = targetRepo ?? repo;
    final primaryUri = Uri.parse('https://api.github.com/repos/$r/releases/latest');

    // Attempt direct GitHub API request
    try {
      final response = await _client.get(
        primaryUri,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Duiliao-App-Updater',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return GitHubRelease.fromJson(data);
      }
    } catch (_) {
      // Fall through to mirror proxy
    }

    // Try mirror proxy if direct API fails
    for (final mirror in kGitHubMirrors) {
      try {
        final mirrorUri = Uri.parse('${mirror}https://api.github.com/repos/$r/releases/latest');
        final response = await _client.get(
          mirrorUri,
          headers: {
            'Accept': 'application/vnd.github.v3+json',
            'User-Agent': 'Duiliao-App-Updater',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          return GitHubRelease.fromJson(data);
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Download an APK file with progress streaming.
  ///
  /// Returns the local downloaded [File].
  Future<File> downloadApk({
    required String downloadUrl,
    required String fileName,
    required void Function(int receivedBytes, int totalBytes) onProgress,
    bool useMirror = false,
  }) async {
    var targetUrl = downloadUrl;
    if (useMirror && !downloadUrl.startsWith('http://127.0.0.1')) {
      targetUrl = '${kGitHubMirrors.first}$downloadUrl';
    }

    final request = http.Request('GET', Uri.parse(targetUrl));
    request.headers['User-Agent'] = 'Duiliao-App-Downloader';

    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw HttpException('下载失败，HTTP 状态码: ${response.statusCode}');
    }

    final total = response.contentLength ?? 0;
    var received = 0;

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    if (await file.exists()) {
      await file.delete();
    }

    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onProgress(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    return file;
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
