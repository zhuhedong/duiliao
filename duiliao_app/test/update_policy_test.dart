import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:duiliao_app/features/upgrade/github_update_service.dart';
import 'package:duiliao_app/features/upgrade/update_policy.dart';

Map<String, dynamic> _release(String tag) => {
      'tag_name': tag,
      'name': '对料 App $tag',
      'body': '',
      'html_url': 'https://github.com/zhuhedong/duiliao/releases/tag/$tag',
      'prerelease': false,
      'assets': [
        {
          'name': 'duiliao-$tag-arm64-v8a-release.apk',
          'size': 21717288,
          'browser_download_url':
              'https://github.com/zhuhedong/duiliao/releases/download/$tag/duiliao-$tag-arm64-v8a-release.apk',
          'content_type': 'application/vnd.android.package-archive',
          'digest': 'sha256:${'b' * 64}',
        },
      ],
    };

void main() {
  group('auto-check throttle', () {
    final now = DateTime(2026, 10, 14, 12);
    test('first run checks', () => expect(shouldAutoCheck(now: now), isTrue));
    test('within interval skips', () {
      expect(
        shouldAutoCheck(now: now, lastCheck: now.subtract(const Duration(hours: 1))),
        isFalse,
      );
    });
    test('after interval checks', () {
      expect(
        shouldAutoCheck(now: now, lastCheck: now.subtract(kAutoCheckInterval)),
        isTrue,
      );
    });
    test('clock moved back checks', () {
      expect(
        shouldAutoCheck(now: now, lastCheck: now.add(const Duration(days: 1))),
        isTrue,
      );
    });
  });

  group('skip version', () {
    test('skipped version suppresses auto prompt only', () {
      expect(shouldPrompt(latestVersion: '2.1.9', ignoredVersion: '2.1.9'), isFalse);
      expect(
        shouldPrompt(latestVersion: '2.1.9', ignoredVersion: '2.1.9', manual: true),
        isTrue,
      );
    });
    test('newer than skipped prompts again', () {
      expect(shouldPrompt(latestVersion: '2.1.10', ignoredVersion: '2.1.9'), isTrue);
      expect(shouldPrompt(latestVersion: '2.1.9'), isTrue);
    });
  });

  group('release source fallback', () {
    test('rate-limited API falls back to latest.json manifest', () async {
      final hits = <String>[];
      final client = MockClient((req) async {
        hits.add(req.url.toString());
        if (req.url.host == 'api.github.com') {
          return http.Response('{"message":"API rate limit exceeded"}', 403,
              headers: {'x-ratelimit-remaining': '0'});
        }
        return http.Response.bytes(utf8.encode(jsonEncode(_release('v2.1.9'))), 200);
      });
      final service = GitHubUpdateService(client: client);
      final result = await service.checkUpdate(currentVersion: '2.1.8');
      expect(result.hasUpdate, isTrue);
      expect(result.error, isNull);
      expect(result.apkAsset!.name, 'duiliao-v2.1.9-arm64-v8a-release.apk');
      expect(hits[1], 'https://github.com/zhuhedong/duiliao/releases/latest/download/latest.json');
    });

    test('mirror manifest is the last resort', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'ghproxy.net') {
          expect(req.url.toString(),
              'https://ghproxy.net/https://github.com/zhuhedong/duiliao/releases/latest/download/latest.json');
          return http.Response.bytes(utf8.encode(jsonEncode(_release('v2.1.9'))), 200);
        }
        throw http.ClientException('blocked');
      });
      final result = await GitHubUpdateService(client: client)
          .checkUpdate(currentVersion: '2.1.8');
      expect(result.hasUpdate, isTrue);
    });

    test('all sources failing reports a real error', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'api.github.com') {
          return http.Response('', 403, headers: {'x-ratelimit-remaining': '0'});
        }
        throw http.ClientException('blocked');
      });
      final result = await GitHubUpdateService(client: client)
          .checkUpdate(currentVersion: '2.1.8');
      expect(result.hasUpdate, isFalse);
      expect(result.error, contains('限流'));
      expect(result.error, isNot(contains('2.1.3')));
    });

    test('dead mirror removed', () {
      expect(kGitHubMirrors, ['https://ghproxy.net/']);
      expect(
        isAllowedUpdateUri(Uri.parse('https://mirror.ghproxy.com/x'), allowMirrors: true),
        isFalse,
      );
    });
  });
}
