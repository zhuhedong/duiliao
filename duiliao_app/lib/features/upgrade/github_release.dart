/// GitHub Release models and semantic version comparison for online upgrades.
library;

class GitHubReleaseAsset {
  const GitHubReleaseAsset({
    required this.name,
    required this.size,
    required this.downloadUrl,
    required this.contentType,
    this.digest,
  });

  final String name;
  final int size;
  final String downloadUrl;
  final String contentType;

  /// GitHub's SHA-256 asset digest (usually returned as `sha256:<hex>`).
  ///
  /// The updater refuses to install an artifact without this value.  Keeping
  /// the normalization here means callers never accidentally compare a
  /// prefixed digest with a raw SHA-256 string.
  final String? digest;

  String? get sha256Digest {
    final raw = digest?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    final normalized = raw.startsWith('sha256:') ? raw.substring(7) : raw;
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(normalized) ? normalized : null;
  }

  bool get hasIntegrityDigest => sha256Digest != null;

  bool get hasSupportedContentType {
    final normalized = contentType.split(';').first.trim().toLowerCase();
    // GitHub occasionally reports an empty type for an asset; the streamed
    // response is checked again before it is written to disk.
    return normalized.isEmpty ||
        normalized == 'application/octet-stream' ||
        normalized == 'application/vnd.android.package-archive';
  }

  String get formattedSize {
    if (size <= 0) return '';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  bool get isApk => name.toLowerCase().endsWith('.apk');

  factory GitHubReleaseAsset.fromJson(Map<String, dynamic> json) =>
      GitHubReleaseAsset(
        name: json['name'] as String? ?? '',
        size: json['size'] as int? ?? 0,
        downloadUrl: json['browser_download_url'] as String? ?? '',
        contentType: json['content_type'] as String? ?? '',
        digest: json['digest'] as String? ?? json['sha256'] as String?,
      );
}

class GitHubRelease {
  const GitHubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    this.publishedAt,
    this.assets = const [],
    this.prerelease = false,
  });

  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final DateTime? publishedAt;
  final List<GitHubReleaseAsset> assets;
  final bool prerelease;

  /// Find the best APK asset for Android.
  ///
  /// Prefers arm64-v8a (standard modern Android), then universal/release apk.
  GitHubReleaseAsset? findApkAsset() {
    final apks = assets.where((a) => a.isApk).toList();
    if (apks.isEmpty) return null;

    // Prefer an artifact with a verifiable digest.  If none is available we
    // still return the best matching asset so the UI can explain why automatic
    // installation is disabled instead of silently hiding the release.
    final candidates = apks.where((a) => a.hasIntegrityDigest).toList();
    final ranked = candidates.isNotEmpty ? candidates : apks;

    // Prefer arm64-v8a
    for (final apk in ranked) {
      if (apk.name.contains('arm64-v8a')) return apk;
    }
    // Prefer general release apk
    for (final apk in ranked) {
      if (apk.name.contains('release') || apk.name.contains('universal')) {
        return apk;
      }
    }
    return ranked.first;
  }

  /// Clean version string without 'v' prefix.
  String get versionString {
    var v = tagName.trim();
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1);
    }
    return v;
  }

  /// Compare against current running version (e.g. `1.0.0` or `1.0.0+1`).
  bool isNewerThan(String currentVersion) {
    return compareVersions(versionString, currentVersion) > 0;
  }

  /// Semantic version comparison. Returns > 0 if v1 > v2, < 0 if v1 < v2, 0 if equal.
  static int compareVersions(String v1, String v2) {
    final parsed1 = _parseSemver(v1);
    final parsed2 = _parseSemver(v2);

    for (var i = 0; i < 3; i++) {
      if (parsed1.parts[i] != parsed2.parts[i]) {
        return parsed1.parts[i].compareTo(parsed2.parts[i]);
      }
    }
    // Compare build number if both exist and base is equal
    if (parsed1.build != null && parsed2.build != null) {
      return parsed1.build!.compareTo(parsed2.build!);
    }
    return 0;
  }

  static ({List<int> parts, int? build}) _parseSemver(String raw) {
    var clean = raw.trim();
    if (clean.startsWith('v') || clean.startsWith('V')) {
      clean = clean.substring(1);
    }
    int? buildNumber;
    if (clean.contains('+')) {
      final split = clean.split('+');
      clean = split[0];
      buildNumber = int.tryParse(split[1]);
    }

    final segments = clean.split('.');
    final numbers = <int>[0, 0, 0];
    for (var i = 0; i < 3 && i < segments.length; i++) {
      // Strip any non-digit suffix (e.g. -beta)
      final numStr = RegExp(r'^\d+').stringMatch(segments[i]) ?? '0';
      numbers[i] = int.tryParse(numStr) ?? 0;
    }
    return (parts: numbers, build: buildNumber);
  }

  factory GitHubRelease.fromJson(Map<String, dynamic> json) {
    final assetList = json['assets'] as List<dynamic>? ?? const [];
    return GitHubRelease(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      body: json['body'] as String? ?? '',
      htmlUrl: json['html_url'] as String? ?? '',
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'] as String)
          : null,
      assets: assetList
          .whereType<Map<String, dynamic>>()
          .map(GitHubReleaseAsset.fromJson)
          .toList(),
      prerelease: json['prerelease'] as bool? ?? false,
    );
  }
}
