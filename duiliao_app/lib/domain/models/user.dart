/// User, session and subscription models.
library;

import '../json.dart';

/// Role values from `backend/app/models/user.py::UserRole`.
///
/// Drives navigation: `user` sees four tabs, `staff` and `admin` additionally see
/// the collection tab. Enforcement is server-side; hiding the tab is a usability
/// measure, not the security boundary.
enum UserRole {
  user('user', '普通用户'),
  staff('staff', '运营'),
  admin('admin', '管理员');

  const UserRole(this.code, this.label);
  final String code;
  final String label;

  static UserRole? tryParse(String? code) {
    for (final role in values) {
      if (role.code == code) return role;
    }
    return null;
  }

  /// True when the role may run collections and trigger judging.
  bool get canOperate => this == staff || this == admin;
}

enum UserStatus {
  pending('pending', '待验证'),
  active('active', '正常'),
  suspended('suspended', '已停用'),
  banned('banned', '已封禁'),
  deleted('deleted', '已删除');

  const UserStatus(this.code, this.label);
  final String code;
  final String label;

  static UserStatus? tryParse(String? code) {
    for (final status in values) {
      if (status.code == code) return status;
    }
    return null;
  }
}

/// Mirrors `UserPublic`.
class AppUser {
  const AppUser({
    required this.id,
    this.username,
    this.email,
    required this.emailVerified,
    this.phone,
    required this.phoneVerified,
    this.displayName,
    this.avatarUrl,
    required this.locale,
    required this.timezone,
    required this.status,
    required this.role,
    this.registrationSource,
    required this.mfaEnabled,
    this.lastLoginAt,
    this.createdAt,
  });

  final String id;
  final String? username;
  final String? email;
  final bool emailVerified;
  final String? phone;
  final bool phoneVerified;
  final String? displayName;
  final String? avatarUrl;
  final String locale;
  final String timezone;
  final UserStatus? status;
  final UserRole? role;
  final String? registrationSource;
  final bool mfaEnabled;
  final String? lastLoginAt;
  final String? createdAt;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: asString(json['id']),
        username: asStringOrNull(json['username']),
        email: asStringOrNull(json['email']),
        emailVerified: asBool(json['email_verified']),
        phone: asStringOrNull(json['phone']),
        phoneVerified: asBool(json['phone_verified']),
        displayName: asStringOrNull(json['display_name']),
        avatarUrl: asStringOrNull(json['avatar_url']),
        locale: asString(json['locale'], fallback: 'zh'),
        timezone: asString(json['timezone'], fallback: 'Asia/Shanghai'),
        status: UserStatus.tryParse(asStringOrNull(json['status'])),
        role: UserRole.tryParse(asStringOrNull(json['role'])),
        registrationSource: asStringOrNull(json['registration_source']),
        mfaEnabled: asBool(json['mfa_enabled']),
        lastLoginAt: asStringOrNull(json['last_login_at']),
        createdAt: asStringOrNull(json['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'email_verified': emailVerified,
        'phone': phone,
        'phone_verified': phoneVerified,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'locale': locale,
        'timezone': timezone,
        'status': status?.code,
        'role': role?.code,
        'registration_source': registrationSource,
        'mfa_enabled': mfaEnabled,
        'last_login_at': lastLoginAt,
        'created_at': createdAt,
      };

  /// Best available name for display.
  String get name {
    for (final candidate in [displayName, username, email, phone]) {
      if (candidate != null && candidate.isNotEmpty) return candidate;
    }
    return id;
  }

  /// Single character for the avatar placeholder.
  String get initial => name.isEmpty ? '?' : name.characters.first;

  bool get canOperate => role?.canOperate ?? false;
}

/// Convenience for [AppUser.initial] without importing `characters` everywhere.
extension on String {
  Iterable<String> get characters => split('');
}

/// A login session. Mirrors `SessionInfo`.
class DeviceSession {
  const DeviceSession({
    required this.id,
    this.deviceName,
    this.platform,
    this.appVersion,
    this.ipAddress,
    this.createdAt,
    this.lastUsedAt,
    required this.current,
  });

  /// Refresh-token row id, used to revoke this session.
  final String id;

  final String? deviceName;
  final String? platform;
  final String? appVersion;
  final String? ipAddress;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  /// From the server's `current` field, which actually means "not expired" rather
  /// than "this device". It is therefore true for every live session and is not
  /// used to highlight the current device — see [isThisDevice].
  final bool current;

  factory DeviceSession.fromJson(Map<String, dynamic> json) => DeviceSession(
        id: asString(json['id']),
        deviceName: asStringOrNull(json['device_name']),
        platform: asStringOrNull(json['platform']),
        appVersion: asStringOrNull(json['app_version']),
        ipAddress: asStringOrNull(json['ip_address']),
        createdAt: asDateTimeOrNull(json['created_at']),
        lastUsedAt: asDateTimeOrNull(json['last_used_at']),
        current: asBool(json['current']),
      );

  String get displayName {
    if (deviceName != null && deviceName!.isNotEmpty) return deviceName!;
    return platformLabel;
  }

  String get platformLabel {
    switch (platform) {
      case 'android':
        return 'Android';
      case 'ios':
        return 'iOS';
      case 'web':
        return '网页后台';
      default:
        return platform ?? '未知设备';
    }
  }

  /// Whether this row is the running app.
  ///
  /// Matched on device name and version because the server does not expose
  /// `device_id` on this payload, and its `current` flag does not mean what its
  /// name suggests.
  bool isThisDevice({String? thisDeviceName, String? thisAppVersion}) {
    if (thisDeviceName == null) return false;
    return deviceName == thisDeviceName &&
        (thisAppVersion == null || appVersion == thisAppVersion);
  }
}

/// Notification rule keys, matching `DEFAULT_NOTIFY_RULES` on the server.
abstract final class NotifyRule {
  static const String drawPublished = 'draw_published';
  static const String sourceHit = 'source_hit';
  static const String sourceMissStreak = 'source_miss_streak';
  static const String missStreakThreshold = 'miss_streak_threshold';
  static const String consensusLeaderChanged = 'consensus_leader_changed';
  static const String collectJobFinished = 'collect_job_finished';

  /// Boolean rules in display order, with their labels.
  static const Map<String, String> toggles = {
    drawPublished: '新开奖',
    sourceHit: '关注源命中',
    sourceMissStreak: '关注源连挂',
    consensusLeaderChanged: '共识领先变动',
    collectJobFinished: '采集任务完成或失败',
  };
}

/// Server-stored subscription, so preferences follow the user across devices.
class Subscription {
  const Subscription({
    required this.sourceIds,
    required this.lotteries,
    required this.playTypes,
    required this.notifyRules,
    this.updatedAt,
  });

  final List<String> sourceIds;
  final List<String> lotteries;
  final List<String> playTypes;
  final Map<String, dynamic> notifyRules;
  final String? updatedAt;

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        sourceIds: asStringList(json['source_ids']),
        lotteries: asStringList(json['lotteries']),
        playTypes: asStringList(json['play_types']),
        notifyRules: asMap(json['notify_rules']),
        updatedAt: asStringOrNull(json['updated_at']),
      );

  static const empty = Subscription(
    sourceIds: [],
    lotteries: [],
    playTypes: [],
    notifyRules: {},
  );

  Map<String, dynamic> toJson() => {
        'source_ids': sourceIds,
        'lotteries': lotteries,
        'play_types': playTypes,
        'notify_rules': notifyRules,
      };

  bool isEnabled(String rule, {bool fallback = true}) =>
      asBool(notifyRules[rule], fallback: fallback);

  int get missStreakThreshold =>
      asInt(notifyRules[NotifyRule.missStreakThreshold], fallback: 3);

  Subscription copyWith({
    List<String>? sourceIds,
    List<String>? lotteries,
    List<String>? playTypes,
    Map<String, dynamic>? notifyRules,
  }) =>
      Subscription(
        sourceIds: sourceIds ?? this.sourceIds,
        lotteries: lotteries ?? this.lotteries,
        playTypes: playTypes ?? this.playTypes,
        notifyRules: notifyRules ?? this.notifyRules,
        updatedAt: updatedAt,
      );

  /// Toggle one boolean rule.
  Subscription withRule(String rule, Object? value) {
    final rules = Map<String, dynamic>.from(notifyRules);
    rules[rule] = value;
    return copyWith(notifyRules: rules);
  }

  Subscription withSource(String sourceId, bool followed) {
    final ids = [...sourceIds];
    if (followed) {
      if (!ids.contains(sourceId)) ids.add(sourceId);
    } else {
      ids.remove(sourceId);
    }
    return copyWith(sourceIds: ids);
  }
}

/// Tokens returned by login and refresh.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;

  /// Rotated on every refresh: the previous value is dead immediately, so the new
  /// one must be persisted before the old one is discarded.
  final String refreshToken;

  /// Access-token lifetime in seconds.
  final int expiresIn;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        accessToken: asString(json['access_token']),
        refreshToken: asString(json['refresh_token']),
        expiresIn: asInt(json['expires_in'], fallback: 900),
      );

  bool get isValid => accessToken.isNotEmpty && refreshToken.isNotEmpty;
}
