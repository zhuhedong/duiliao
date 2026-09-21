/// Authentication state and the token plumbing the [ApiClient] depends on.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../../core/providers.dart';
import '../../core/net/api_exception.dart';
import '../../data/auth_repository.dart';
import '../../domain/models/user.dart';

/// Where the app is in the sign-in lifecycle.
enum AuthPhase {
  /// Checking for a stored refresh token at launch.
  restoring,

  /// No usable credential; the login screen is shown.
  unauthenticated,

  /// Signed in and usable.
  authenticated,

  /// Signed in but the app is locked behind biometrics.
  locked,
}

@immutable
class AuthState {
  const AuthState({
    this.phase = AuthPhase.restoring,
    this.user,
    this.errorMessage,
    this.isSubmitting = false,
  });

  final AuthPhase phase;
  final AppUser? user;

  /// Message for the login form; cleared on the next attempt.
  final String? errorMessage;

  final bool isSubmitting;

  bool get isAuthenticated => phase == AuthPhase.authenticated;
  bool get isLocked => phase == AuthPhase.locked;

  /// Role of the signed-in user, or null when not signed in.
  ///
  /// Drives navigation: `user` gets four tabs, `staff` and `admin` also get the
  /// collection tab.
  UserRole? get role => user?.role;

  /// True when the account may run collections. Defaults to false while
  /// restoring or signed out, so a privileged tab is never shown speculatively.
  bool get canOperate => user?.canOperate ?? false;

  AuthState copyWith({
    AuthPhase? phase,
    AppUser? user,
    String? errorMessage,
    bool clearError = false,
    bool? isSubmitting,
  }) =>
      AuthState(
        phase: phase ?? this.phase,
        user: user ?? this.user,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        isSubmitting: isSubmitting ?? this.isSubmitting,
      );

  AuthState signedOut({String? errorMessage}) => AuthState(
        phase: AuthPhase.unauthenticated,
        errorMessage: errorMessage,
      );
}

/// Owns the access token and drives [AuthState].
///
/// Also implements [TokenProvider] so [ApiClient] can refresh transparently
/// without the network layer depending on the feature layer. The client is
/// wired to this notifier in [AuthNotifier.build].
class AuthNotifier extends Notifier<AuthState> implements TokenProvider {
  AuthNotifier({this.deviceProvider});

  /// Supplies device metadata for the session list, so the web console can tell
  /// this handset apart from other sessions. Null where the platform plugin is
  /// unavailable, in which case login omits the `device` block.
  final DeviceDescriptor Function()? deviceProvider;

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  AuthState build() {
    // Registering here means every request goes out with a live token and can be
    // refreshed transparently, without the network layer importing this feature.
    ref.read(apiClientProvider).attachTokenProvider(this);
    return const AuthState();
  }

  /// Access token, memory only. Never written to disk.
  String? _accessToken;

  /// Collapses concurrent refreshes onto one request. Without this, several
  /// requests failing with 401 at once would each rotate the refresh token, and
  /// all but the first would be using an already-revoked value.
  Future<bool>? _refreshInFlight;

  @override
  String? get accessToken => _accessToken;

  void _emit(AuthState next) => state = next;

  // ------------------------------------------------------------------ //
  // Startup
  // ------------------------------------------------------------------ //
  /// Attempt a silent sign-in from the stored refresh token.
  ///
  /// Called once at launch. A user who signed in previously should not have to
  /// re-enter credentials after the process is killed.
  Future<void> restore({bool requireBiometric = false}) async {
    _emit(const AuthState(phase: AuthPhase.restoring));
    final stored = await _repository.readRefreshToken();
    if (stored == null || stored.isEmpty) {
      _emit(const AuthState(phase: AuthPhase.unauthenticated));
      return;
    }
    try {
      final tokens = await _repository.refresh(stored);
      _accessToken = tokens.accessToken;
      // /auth/refresh does not return a user, so the profile is fetched.
      final user = await _repository.me();
      _emit(AuthState(
        phase: requireBiometric ? AuthPhase.locked : AuthPhase.authenticated,
        user: user,
      ));
    } on NetworkException {
      // Offline at launch is not a credential failure — keep the token and let
      // the user retry rather than silently signing them out.
      _emit(const AuthState(
        phase: AuthPhase.unauthenticated,
        errorMessage: '网络不可用，请检查网络后重试',
      ));
    } on ApiException catch (e) {
      // The refresh token is invalid, revoked or rotated away. Clear it.
      await _repository.clearCredentials();
      _accessToken = null;
      _emit(AuthState(
        phase: AuthPhase.unauthenticated,
        errorMessage: e.isUnauthorized ? null : e.displayMessage,
      ));
    }
  }

  // ------------------------------------------------------------------ //
  // Sign in / out
  // ------------------------------------------------------------------ //
  Future<bool> login({required String identifier, required String password}) async {
    _emit(state.copyWith(isSubmitting: true, clearError: true));
    try {
      final result = await _repository.login(
        identifier: identifier,
        password: password,
        device: deviceProvider?.call(),
      );
      _accessToken = result.tokens.accessToken;
      _emit(AuthState(phase: AuthPhase.authenticated, user: result.user));
      return true;
    } on ApiException catch (e) {
      _emit(AuthState(
        phase: AuthPhase.unauthenticated,
        errorMessage: e.displayMessage,
      ));
      return false;
    } on NetworkException catch (e) {
      _emit(AuthState(
        phase: AuthPhase.unauthenticated,
        errorMessage: e.displayMessage,
      ));
      return false;
    }
  }

  Future<void> logout({bool allDevices = false}) async {
    final refreshToken = await _repository.readRefreshToken();
    await _repository.logout(refreshToken: refreshToken, allDevices: allDevices);
    _accessToken = null;
    _emit(const AuthState(phase: AuthPhase.unauthenticated));
  }

  /// Unlock after a successful biometric check.
  void completeUnlock() {
    if (state.phase != AuthPhase.locked) return;
    _emit(state.copyWith(phase: AuthPhase.authenticated));
  }

  /// Re-lock, e.g. when returning from the background with biometrics enabled.
  void lock() {
    if (state.phase != AuthPhase.authenticated) return;
    _emit(state.copyWith(phase: AuthPhase.locked));
  }

  void clearError() {
    if (state.errorMessage == null) return;
    _emit(state.copyWith(clearError: true));
  }

  /// Replace the cached user, after a profile edit.
  void updateUser(AppUser user) => _emit(state.copyWith(user: user));

  /// Refresh the cached profile from the server.
  Future<void> reloadUser() async {
    if (!state.isAuthenticated) return;
    try {
      _emit(state.copyWith(user: await _repository.me()));
    } on ApiException {
      // Not worth interrupting the UI; the cached user remains valid.
    } on NetworkException {
      // Same offline.
    }
  }

  // ------------------------------------------------------------------ //
  // TokenProvider
  // ------------------------------------------------------------------ //
  @override
  Future<bool> refreshAccessToken() {
    // One shared attempt, because the refresh token is single-use.
    return _refreshInFlight ??= _performRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _performRefresh() async {
    final stored = await _repository.readRefreshToken();
    if (stored == null || stored.isEmpty) return false;
    try {
      final tokens = await _repository.refresh(stored);
      _accessToken = tokens.accessToken;
      return true;
    } on ApiException {
      return false;
    } on NetworkException {
      // Offline: report failure so the caller surfaces a network error, but do
      // not destroy the credential — it may still be valid once connectivity
      // returns.
      return false;
    }
  }

  @override
  void onAuthenticationLost() {
    _accessToken = null;
    // Fire and forget: the state change is what matters for the UI.
    _repository.clearCredentials();
    _emit(const AuthState(
      phase: AuthPhase.unauthenticated,
      errorMessage: '登录已过期，请重新登录',
    ));
  }
}
