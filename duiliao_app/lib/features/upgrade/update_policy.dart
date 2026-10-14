/// Startup update-check policy (ported from deeix-client): throttle automatic
/// checks and let the user skip a version. Pure functions are unit-tested.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'github_release.dart';

const Duration kAutoCheckInterval = Duration(hours: 12);

/// At most once per [interval]; manual checks bypass this.
bool shouldAutoCheck({
  required DateTime now,
  DateTime? lastCheck,
  Duration interval = kAutoCheckInterval,
}) {
  if (lastCheck == null) return true;
  if (lastCheck.isAfter(now)) return true; // clock moved back
  return now.difference(lastCheck) >= interval;
}

/// Skipped versions only suppress automatic prompts; a manual check always
/// shows the update. A release newer than the skipped one prompts again.
bool shouldPrompt({
  required String latestVersion,
  String? ignoredVersion,
  bool manual = false,
}) {
  if (manual || ignoredVersion == null || ignoredVersion.isEmpty) return true;
  return GitHubRelease.compareVersions(latestVersion, ignoredVersion) > 0;
}

class UpdatePrefs {
  UpdatePrefs(this._prefs);

  static const _kLastCheck = 'update.lastCheckMs';
  static const _kIgnored = 'update.ignoredVersion';

  final SharedPreferences _prefs;

  static Future<UpdatePrefs> load() async =>
      UpdatePrefs(await SharedPreferences.getInstance());

  DateTime? get lastCheck {
    final ms = _prefs.getInt(_kLastCheck);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markChecked(DateTime t) =>
      _prefs.setInt(_kLastCheck, t.millisecondsSinceEpoch);

  String? get ignoredVersion => _prefs.getString(_kIgnored);

  Future<void> ignore(String version) => _prefs.setString(_kIgnored, version);
}
