import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:duiliao_app/features/upgrade/github_release.dart';
import 'package:duiliao_app/features/upgrade/github_update_service.dart';

void main() {
  group('GitHubRelease semantic version comparison', () {
    test('standard semver comparisons', () {
      expect(GitHubRelease.compareVersions('1.0.1', '1.0.0'), greaterThan(0));
      expect(GitHubRelease.compareVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(GitHubRelease.compareVersions('1.0.0', '1.0.0'), equals(0));
      expect(GitHubRelease.compareVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(GitHubRelease.compareVersions('1.10.0', '1.9.0'), greaterThan(0));
    });

    test('handles leading v and V', () {
      expect(GitHubRelease.compareVersions('v1.0.1', '1.0.0'), greaterThan(0));
      expect(GitHubRelease.compareVersions('V2.0.0', 'v1.9.9'), greaterThan(0));
    });

    test('compares build numbers when base semver matches', () {
      expect(GitHubRelease.compareVersions('1.0.0+2', '1.0.0+1'), greaterThan(0));
      expect(GitHubRelease.compareVersions('1.0.0+1', '1.0.0+2'), lessThan(0));
    });
  });

  group('GitHubRelease JSON parsing and asset matching', () {
    test('parses release and finds arm64 apk', () {
      final json = {
        'tag_name': 'v1.1.0',
        'name': 'Duiliao v1.1.0 发布',
        'body': '## 更新日志\n- 支持 iOS 27 玻璃拟态设计\n- 支持在线升级',
        'html_url': 'https://github.com/zhuhedong/duiliao/releases/tag/v1.1.0',
        'published_at': '2026-09-21T18:00:00Z',
        'assets': [
          {
            'name': 'duiliao-v1.1.0-arm64-v8a-release.apk',
            'size': 25165824, // ~24.0 MB
            'browser_download_url': 'https://github.com/zhuhedong/duiliao/releases/download/v1.1.0/app.apk',
            'content_type': 'application/vnd.android.package-archive',
          },
          {
            'name': 'source.tar.gz',
            'size': 1024,
            'browser_download_url': 'https://github.com/zhuhedong/duiliao/archive/v1.1.0.tar.gz',
            'content_type': 'application/gzip',
          },
        ],
      };

      final release = GitHubRelease.fromJson(json);
      expect(release.tagName, 'v1.1.0');
      expect(release.versionString, '1.1.0');
      expect(release.isNewerThan('1.0.0'), isTrue);
      expect(release.isNewerThan('1.1.0'), isFalse);
      expect(release.isNewerThan('1.2.0'), isFalse);

      final apk = release.findApkAsset();
      expect(apk, isNotNull);
      expect(apk!.name, 'duiliao-v1.1.0-arm64-v8a-release.apk');
      expect(apk.isApk, isTrue);
      expect(apk.formattedSize, '24.0 MB');
    });
  });

  group('GitHubUpdateService checkUpdate', () {
    test('detects available update via mock client', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/releases/latest')) {
          return http.Response(
            jsonEncode({
              'tag_name': 'v2.0.0',
              'name': 'Duiliao 2.0',
              'body': '重大更新',
              'html_url': 'https://github.com/zhuhedong/duiliao/releases/tag/v2.0.0',
              'assets': [
                {
                  'name': 'duiliao-arm64-v8a.apk',
                  'size': 20971520,
                  'browser_download_url': 'https://example.com/app.apk',
                  'content_type': 'application/vnd.android.package-archive',
                }
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = GitHubUpdateService(client: mockClient, repo: 'test/repo');
      final result = await service.checkUpdate(currentVersion: '1.0.0');

      expect(result.hasUpdate, isTrue);
      expect(result.latestRelease?.tagName, 'v2.0.0');
      expect(result.apkAsset?.name, 'duiliao-arm64-v8a.apk');
      expect(result.error, isNull);
    });

    test('returns hasUpdate false when current version is latest', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'tag_name': 'v1.0.0',
            'name': 'Duiliao 1.0',
            'body': '初始版本',
            'html_url': 'https://github.com/zhuhedong/duiliao/releases/tag/v1.0.0',
            'assets': [],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = GitHubUpdateService(client: mockClient, repo: 'test/repo');
      final result = await service.checkUpdate(currentVersion: '1.0.0');

      expect(result.hasUpdate, isFalse);
      expect(result.error, isNull);
    });
  });
}
