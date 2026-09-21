/// Errors raised by [ApiClient], and the code extraction the backend requires.
library;

/// Error codes the transport layer and auth surface produce.
///
/// Values match the backend exactly; see `app/middleware/encryption.py` for the
/// transport codes and `app/api/v1/auth.py` for the auth ones.
abstract final class ApiErrorCode {
  // --- transport (middleware), returned as plaintext -------------------- //
  /// The session key is unknown or expired. The in-memory session store is
  /// cleared by a backend restart, so this is expected in normal operation and
  /// is handled by re-handshaking rather than surfaced to the user.
  static const String noSession = 'no_session';
  static const String badSignature = 'bad_signature';
  static const String badTimestamp = 'bad_timestamp';
  static const String replay = 'replay';
  static const String badPayload = 'bad_payload';
  static const String payloadTooLarge = 'payload_too_large';

  // --- auth (handlers), returned encrypted ------------------------------ //
  static const String invalidCredentials = 'invalid_credentials';
  static const String locked = 'locked';
  static const String inactive = 'inactive';
  static const String invalidRefresh = 'invalid_refresh';
  static const String revoked = 'revoked';
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code, this.payload});

  final String message;
  final int? statusCode;
  final String? code;
  final Object? payload;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isSessionExpired => code == ApiErrorCode.noSession;
  bool get isAccountLocked => code == ApiErrorCode.locked;

  /// True for signature/clock problems, which indicate a misconfigured build
  /// rather than anything the user did.
  bool get isConfigurationProblem =>
      code == ApiErrorCode.badSignature || code == ApiErrorCode.badTimestamp;

  /// A message suitable for display, in Chinese, for the cases a user can act on.
  String get displayMessage {
    switch (code) {
      case ApiErrorCode.invalidCredentials:
        return '账号或密码错误';
      case ApiErrorCode.locked:
        return '账号已临时锁定，请稍后再试';
      case ApiErrorCode.inactive:
        return '账号未启用，请联系管理员';
      case ApiErrorCode.badSignature:
        return '客户端签名密钥与服务端不一致，请更新 APP';
      case ApiErrorCode.badTimestamp:
        return '设备时间偏差过大，请检查系统时间';
      case ApiErrorCode.payloadTooLarge:
        return '请求内容过大';
      default:
        if (statusCode == 403) return '当前账号没有该操作权限';
        if (statusCode == 404) return '数据不存在';
        if (statusCode != null && statusCode! >= 500) return '服务端异常，请稍后重试';
        return message.isEmpty ? '请求失败' : message;
    }
  }

  @override
  String toString() =>
      'ApiException($statusCode${code == null ? '' : ' $code'}): $message';
}

/// Raised when the request could not reach the server at all (no route to host,
/// DNS failure, timeout). Distinct from [ApiException] because callers fall back
/// to cached data for this but not for a 4xx.
class NetworkException implements Exception {
  const NetworkException(this.message, {this.cause});
  final String message;
  final Object? cause;

  String get displayMessage => '网络连接失败，请检查网络';

  @override
  String toString() => 'NetworkException: $message';
}

/// Extract an error code from a decoded error body.
///
/// The backend produces two different shapes, and reading only one of them is a
/// live bug in the web client:
///
/// * Middleware errors are **plaintext** with the code as a sibling of `detail`:
///   `{"detail": "Missing or expired encryption session", "code": "no_session"}`
/// * Handler errors are **encrypted** with the code nested inside `detail`:
///   `{"detail": {"message": "...", "code": "invalid_credentials"}}`
///
/// Both are checked here, top level first, so `no_session` is actually detected
/// and the re-handshake path runs instead of falling through to a token refresh.
String? extractApiErrorCode(Object? payload) {
  if (payload is! Map) return null;
  final top = payload['code'];
  if (top is String && top.isNotEmpty) return top;
  final detail = payload['detail'];
  if (detail is Map) {
    final nested = detail['code'];
    if (nested is String && nested.isNotEmpty) return nested;
  }
  return null;
}

/// Extract a human-readable message, covering all three `detail` shapes
/// (string, object with `message`, and a bare string body).
String extractApiErrorMessage(Object? payload, String fallback) {
  if (payload is String && payload.isNotEmpty) return payload;
  if (payload is Map) {
    final detail = payload['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is Map) {
      final message = detail['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    if (detail is List && detail.isNotEmpty) {
      // FastAPI validation errors: [{loc: [...], msg: "...", type: "..."}]
      final first = detail.first;
      if (first is Map && first['msg'] is String) return first['msg'] as String;
    }
    final message = payload['message'];
    if (message is String && message.isNotEmpty) return message;
  }
  return fallback;
}
