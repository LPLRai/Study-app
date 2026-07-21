// ─────────────────────────────────────────────────────────────────────────────
// services/timer_notification_service.dart
//
// Fires local notifications (with custom sound) when a Pomodoro phase ends.
// Unlike AudioPlayer, local notifications are delivered by the OS and will
// ring even when the screen is off or the app is backgrounded.
//
// Three notification channels are created (one per sound) so each phase
// transition plays the correct chime:
//   • "gyan_focus_end"        → focus_end.mp3   (focus → break)
//   • "gyan_break_end"        → break_end.mp3   (break → focus)
//   • "gyan_long_break_start" → long_break_start.mp3 (long break starts)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class TimerNotificationService {
  TimerNotificationService._();
  static final TimerNotificationService instance = TimerNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // ── Channel IDs ────────────────────────────────────────────────────────────
  static const _chFocusEnd       = 'gyan_focus_end';
  static const _chBreakEnd       = 'gyan_break_end';
  static const _chLongBreakStart = 'gyan_long_break_start';

  // ── Notification IDs (one per channel; we just overwrite) ─────────────────
  static const _idFocusEnd       = 2001;
  static const _idBreakEnd       = 2002;
  static const _idLongBreakStart = 2003;

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_ready) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
      _ready = true;
    } catch (_) {}
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Focus phase ended → break starting.
  Future<void> notifyFocusEnd() => _show(
        id: _idFocusEnd,
        channelId: _chFocusEnd,
        channelName: 'Focus complete',
        sound: 'focus_end',
        title: '⏰ Focus session complete!',
        body: 'Great work! Time for a break.',
      );

  /// Break ended → new focus starting.
  Future<void> notifyBreakEnd() => _show(
        id: _idBreakEnd,
        channelId: _chBreakEnd,
        channelName: 'Break over',
        sound: 'break_end',
        title: '🎯 Break over — let\'s focus!',
        body: 'Your break is done. Start the next Pomodoro.',
      );

  /// Long break starting (after a full Pomodoro set).
  Future<void> notifyLongBreakStart() => _show(
        id: _idLongBreakStart,
        channelId: _chLongBreakStart,
        channelName: 'Long break',
        sound: 'long_break_start',
        title: '🏆 Full set complete!',
        body: 'Enjoy your long break — you earned it.',
      );

  // ── Internal ───────────────────────────────────────────────────────────────
  Future<void> _show({
    required int id,
    required String channelId,
    required String channelName,
    required String sound,   // filename without extension, inside res/raw/
    required String title,
    required String body,
  }) async {
    await init();
    if (!_ready) return;
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          // References the file in android/app/src/main/res/raw/<sound>.mp3
          sound: RawResourceAndroidNotificationSound(sound),
          icon: '@mipmap/ic_launcher',
          // Auto-dismiss after a few seconds so it doesn't clutter the tray.
          timeoutAfter: 8000,
          autoCancel: true,
        ),
        iOS: DarwinNotificationDetails(
          sound: '$sound.mp3',
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      );
      await _plugin.show(id, title, body, details);
    } catch (_) {}
  }
}
