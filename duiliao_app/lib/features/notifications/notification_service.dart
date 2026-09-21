/// Event polling, local notifications and the message centre.
///
/// There is no third-party push SDK: the client polls `GET /app/events` with a
/// persisted cursor and raises notifications locally. That keeps operational data
/// off any external service, at the cost of delivery latency.
///
/// The cursor is what prevents duplicates. It is the `occurred_at` of the newest
/// event delivered, persisted to disk, and sent back as `since` — so the same
/// event is never notified twice even across a restart. It is only advanced once
/// the events have been handled.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_exception.dart';
import '../../core/navigation.dart';
import '../../core/providers.dart';
import '../../core/storage/cache_store.dart';
import '../../data/collector_repository.dart';
import '../../domain/models/app_event.dart';
import '../../domain/models/user.dart';

/// Foreground poll interval. Background polling is coarser and OS-controlled.
const Duration kEventPollInterval = Duration(minutes: 1);

/// Cap on stored messages, so the centre cannot grow without bound.
const int kMaxStoredMessages = 200;

/// A delivered event plus its read state.
@immutable
class AppMessage {
  const AppMessage({required this.event, required this.read});

  final AppEvent event;
  final bool read;

  Map<String, dynamic> toJson() => {'event': event.toJson(), 'read': read};

  static AppMessage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final event = raw['event'];
    if (event is! Map) return null;
    return AppMessage(
      event: AppEvent.fromJson(event.cast<String, dynamic>()),
      read: raw['read'] == true,
    );
  }

  AppMessage copyWith({bool? read}) =>
      AppMessage(event: event, read: read ?? this.read);
}

/// Local message log, newest first.
@immutable
class MessageCentreState {
  const MessageCentreState({this.messages = const [], this.cursor});

  final List<AppMessage> messages;

  /// Persisted `occurred_at` cursor.
  final String? cursor;

  int get unreadCount => messages.where((m) => !m.read).length;

  MessageCentreState copyWith({List<AppMessage>? messages, String? cursor}) =>
      MessageCentreState(
        messages: messages ?? this.messages,
        cursor: cursor ?? this.cursor,
      );
}

/// Wraps the plugin so polling logic stays testable without a platform channel.
abstract class NotificationPresenter {
  Future<void> initialize();
  Future<void> show(AppEvent event, int id);
}

class LocalNotificationPresenter implements NotificationPresenter {
  LocalNotificationPresenter({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _plugin.initialize(
      InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        openAppDeepLink(response.payload);
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _initialized = true;
  }

  @override
  Future<void> show(AppEvent event, int id) async {
    await initialize();
    final channelId = event.type?.channelId ?? 'duiliao_general';
    await _plugin.show(
      id,
      event.title,
      event.body,
      NotificationDetails(
        // A channel per event type means the OS settings let a user silence, say,
        // draw notifications while keeping job-completion ones.
        android: AndroidNotificationDetails(
          channelId,
          event.type?.label ?? '通知',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: event.deepLink,
    );
  }
}

/// A presenter that records instead of showing, for tests.
class RecordingPresenter implements NotificationPresenter {
  final List<AppEvent> shown = [];
  @override
  Future<void> initialize() async {}
  @override
  Future<void> show(AppEvent event, int id) async => shown.add(event);
}

final notificationPresenterProvider = Provider<NotificationPresenter>(
  (ref) => LocalNotificationPresenter(),
);

final messageCentreProvider =
    NotifierProvider<MessageCentre, MessageCentreState>(MessageCentre.new);

class MessageCentre extends Notifier<MessageCentreState> {
  @override
  MessageCentreState build() {
    // Loaded asynchronously; the UI starts empty and fills in.
    Future.microtask(_restore);
    return const MessageCentreState();
  }

  CacheStore get _cache => ref.read(cacheStoreProvider);
  CollectorRepository get _repo => ref.read(collectorRepositoryProvider);

  Future<void> _restore() async {
    try {
      final cursorEntry =
          await _cache.read(CacheKeys.eventCursor, ttl: const Duration(days: 3650));
      final messagesEntry =
          await _cache.read(CacheKeys.messages, ttl: const Duration(days: 3650));
      final messages = <AppMessage>[];
      final raw = messagesEntry?.value;
      if (raw is List) {
        for (final entry in raw) {
          final message = AppMessage.fromJson(entry);
          if (message != null) messages.add(message);
        }
      }
      state = MessageCentreState(
        messages: messages,
        cursor: cursorEntry?.value as String?,
      );
    } catch (_) {
      // A corrupt store must not stop notifications working from now on.
    }
  }

  Future<void> _persist() async {
    try {
      await _cache.write(
        CacheKeys.messages,
        state.messages.map((m) => m.toJson()).toList(),
      );
      if (state.cursor != null) {
        await _cache.write(CacheKeys.eventCursor, state.cursor);
      }
    } catch (_) {
      // Non-fatal: the cursor is re-derived from the server on the next poll.
    }
  }

  /// Poll once, raise notifications for events the user's rules allow, and
  /// advance the cursor.
  ///
  /// Returns the number of notifications raised.
  Future<int> pollOnce({Subscription? subscription}) async {
    final AppEventPage page;
    try {
      page = await _repo.events(since: state.cursor, limit: 50);
    } on ApiException {
      return 0;
    } on NetworkException {
      return 0;
    }

    if (page.events.isEmpty) {
      // Still adopt the server's cursor so an empty poll does not re-scan.
      if (page.nextCursor != null && page.nextCursor != state.cursor) {
        state = state.copyWith(cursor: page.nextCursor);
        await _persist();
      }
      return 0;
    }

    // Guard against an event arriving twice across a cursor boundary.
    final known = state.messages.map((m) => m.event.dedupeKey).toSet();
    final fresh = page.events.where((e) => !known.contains(e.dedupeKey)).toList();

    final presenter = ref.read(notificationPresenterProvider);
    var raised = 0;
    for (final event in fresh) {
      if (!_allowedByRules(event, subscription)) continue;
      // A stable-ish id keeps the OS from stacking unrelated notifications.
      await presenter.show(event, event.dedupeKey.hashCode & 0x7fffffff);
      raised++;
    }

    final combined = [
      ...fresh.map((e) => AppMessage(event: e, read: false)),
      ...state.messages,
    ];
    state = MessageCentreState(
      messages: combined.take(kMaxStoredMessages).toList(),
      cursor: page.nextCursor ?? state.cursor,
    );
    await _persist();
    return raised;
  }

  /// Whether the user's notification rules permit this event.
  ///
  /// The server already filters by rule, but re-checking locally means a
  /// preference change takes effect immediately rather than at the next poll.
  bool _allowedByRules(AppEvent event, Subscription? subscription) {
    if (subscription == null) return true;
    return switch (event.type) {
      AppEventType.drawPublished =>
        subscription.isEnabled(NotifyRule.drawPublished),
      AppEventType.sourceHit =>
        subscription.isEnabled(NotifyRule.sourceHit, fallback: false),
      AppEventType.sourceMissStreak =>
        subscription.isEnabled(NotifyRule.sourceMissStreak),
      AppEventType.consensusLeaderChanged =>
        subscription.isEnabled(NotifyRule.consensusLeaderChanged, fallback: false),
      AppEventType.collectJobFinished =>
        subscription.isEnabled(NotifyRule.collectJobFinished),
      null => false,
    };
  }

  void markRead(String dedupeKey) {
    state = state.copyWith(
      messages: [
        for (final message in state.messages)
          message.event.dedupeKey == dedupeKey
              ? message.copyWith(read: true)
              : message,
      ],
    );
    _persist();
  }

  void markAllRead() {
    state = state.copyWith(
      messages: [for (final m in state.messages) m.copyWith(read: true)],
    );
    _persist();
  }

  Future<void> clear() async {
    state = MessageCentreState(cursor: state.cursor);
    await _persist();
  }

  /// Reset the cursor, so the next poll re-scans recent history.
  Future<void> resetCursor() async {
    state = const MessageCentreState();
    await _cache.delete(CacheKeys.eventCursor);
    await _cache.delete(CacheKeys.messages);
  }
}

/// Drives foreground polling, tied to app lifecycle.
///
/// Polling stops when the app is backgrounded — a timer firing encrypted requests
/// behind a locked screen wastes battery and radio — and fires immediately on
/// return, which is when the user actually wants fresh data.
class EventPoller with WidgetsBindingObserver {
  EventPoller({required this.onPoll});

  /// Performs one poll. Injected as a plain callback so the poller does not hold
  /// a Ref for its whole lifetime.
  final Future<void> Function() onPoll;

  Timer? _timer;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _resume();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _started = false;
    }
  }

  void _resume() {
    _timer?.cancel();
    // Poll immediately, then on a timer.
    unawaited(_poll());
    _timer = Timer.periodic(kEventPollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      await onPoll();
    } catch (_) {
      // Polling is best-effort; a failure just means the next tick tries again.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _resume();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _timer?.cancel();
        _timer = null;
    }
  }
}

/// The user's server-stored subscription.
final subscriptionProvider = FutureProvider<Subscription>(
  (ref) => ref.read(collectorRepositoryProvider).subscription(),
);

/// Foreground event polling is started by the authenticated app shell. Keeping
/// it provider-scoped makes it stop automatically on logout and avoids a timer
/// surviving a replaced ProviderContainer in tests.
final eventPollerProvider = Provider<EventPoller>((ref) {
  final poller = EventPoller(onPoll: () async {
    Subscription? subscription;
    try {
      subscription = await ref.read(subscriptionProvider.future);
    } catch (_) {
      // The event feed can still be polled with server defaults when the
      // preference request is temporarily unavailable.
    }
    await ref.read(messageCentreProvider.notifier).pollOnce(
          subscription: subscription,
        );
  });
  poller.start();
  ref.onDispose(poller.stop);
  return poller;
});

/// Serialise the message list for persistence. Exposed for tests.
String encodeMessages(List<AppMessage> messages) =>
    jsonEncode(messages.map((m) => m.toJson()).toList());
