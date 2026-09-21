/// Build-time configuration, supplied with `--dart-define`.
///
/// The signing secret is a build-time value and must be injected by CI, never
/// committed. It is extractable from a distributed binary, so it is a
/// transport-integrity measure rather than a user-authentication one — per-user
/// security rests on the JWT. Rotating it invalidates every older build, so a
/// rotation has to ship together with a raised `min_supported` version (see
/// `docs/app_release.md`).
library;

class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.signingSecret,
    required this.appId,
    required this.requestTimeout,
    required this.pollInterval,
  });

  /// Full base URL including the API prefix, e.g. `https://host/api/v1`.
  final String apiBaseUrl;

  /// Must byte-for-byte equal the backend's `APP_SIGNING_SECRET`.
  final String signingSecret;

  /// Sent as `X-App-Id`. The backend does not validate it; it is for log triage.
  final String appId;

  final Duration requestTimeout;

  /// How often the collect-job progress view and the event feed are polled.
  final Duration pollInterval;

  static const String _defaultBaseUrl = 'http://10.0.2.2:8000/api/v1';

  /// Read from `--dart-define` values, falling back to local-development
  /// defaults. `10.0.2.2` is how the Android emulator reaches the host machine.
  factory AppConfig.fromEnvironment() {
    const baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: _defaultBaseUrl);
    const secret = String.fromEnvironment(
      'APP_SIGNING_SECRET',
      defaultValue: 'CHANGE_ME_app_signing_secret_change_me',
    );
    const appId = String.fromEnvironment('APP_ID', defaultValue: 'app');
    const timeoutSeconds = int.fromEnvironment('REQUEST_TIMEOUT_SECONDS', defaultValue: 30);
    const pollSeconds = int.fromEnvironment('POLL_INTERVAL_SECONDS', defaultValue: 2);
    return AppConfig(
      // A trailing slash would produce a double slash in every path.
      apiBaseUrl: baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
      signingSecret: secret,
      appId: appId,
      requestTimeout: Duration(seconds: timeoutSeconds),
      pollInterval: Duration(seconds: pollSeconds),
    );
  }

  /// True when the build still carries the placeholder secret, which means every
  /// request will fail `bad_signature` against a correctly configured server.
  /// Surfaced on the debug screen instead of failing silently.
  bool get hasPlaceholderSecret => signingSecret.startsWith('CHANGE_ME');

  /// Host and scheme only, for display.
  String get displayHost {
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null) return apiBaseUrl;
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }
}
