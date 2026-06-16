// ─────────────────────────────────────────────────────────────────────────────
// services/local_notification_service.dart
//
// Schedules two types of local notifications:
//   1. Daily study reminder — fires at the user's preferred study time.
//   2. Streak nudge — fires at 8 PM if the user hasn't studied today.
//
// Uses flutter_local_notifications (already in pubspec) with timezone support.
// No new dependencies needed — just add flutter_timezone to pubspec.yaml.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../services/push_service.dart'; // re-uses kChannelId

const int _kDailyReminderId = 1001;
const int _kStreakNudgeId   = 1002;

class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  // ── Init (call once at app start, after PushService.init) ─────────────────
  Future<void> init() async {
    if (_ready) return;
    try {
      tz.initializeTimeZones();
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));

      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false, // already requested by PushService
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

  /// Call this whenever the user's studyTime changes (sign-in, onboarding,
  /// profile update). Pass null to cancel all scheduled notifications.
  Future<void> scheduleAll(String? studyTime) async {
    await init();
    await _scheduleDailyReminder(studyTime);
    await _scheduleStreakNudge();
  }

  /// Cancel everything (on sign-out).
  Future<void> cancelAll() async {
    try {
      await _plugin.cancel(_kDailyReminderId);
      await _plugin.cancel(_kStreakNudgeId);
    } catch (_) {}
  }

  // ── 1. Daily study reminder ────────────────────────────────────────────────
  Future<void> _scheduleDailyReminder(String? studyTime) async {
    await _plugin.cancel(_kDailyReminderId);
    if (studyTime == null || studyTime.isEmpty) return;

    final time = _timeForStudyPreference(studyTime);
    if (time == null) return; // 'Flexible' → no fixed reminder

    try {
      await _plugin.zonedSchedule(
        _kDailyReminderId,
        ' Time to study!',
        _reminderBody(studyTime),
        _nextInstanceOf(time.$1, time.$2),
        _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // repeat daily
      );
    } catch (_) {}
  }

  // ── 2. Streak / inactivity nudge at 8 PM ──────────────────────────────────
  Future<void> _scheduleStreakNudge() async {
    await _plugin.cancel(_kStreakNudgeId);
    try {
      await _plugin.zonedSchedule(
        _kStreakNudgeId,
        ' Don\'t break your streak!',
        'You haven\'t studied today. Keep your streak alive — even 10 minutes counts.',
        _nextInstanceOf(20, 0), // 8:00 PM every day
        _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {}
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Maps the user's study-time preference to a (hour, minute) pair.
  /// Returns null for 'Flexible' since there's no fixed time to target.
  (int, int)? _timeForStudyPreference(String pref) {
    switch (pref) {
      case 'Morning':    return (7, 0);   // 7:00 AM
      case 'Afternoon':  return (13, 0);  // 1:00 PM
      case 'Evening':    return (18, 0);  // 6:00 PM
      case 'Late Night': return (21, 0);  // 9:00 PM
      case 'Flexible':   return null;
      default:           return null;
    }
  }

  String _reminderBody(String studyTime) {
    switch (studyTime) {
      case 'Morning':    return 'Good morning! Start your day with a focused study session.';
      case 'Afternoon':  return 'Afternoon check-in — time to hit the books!';
      case 'Evening':    return 'Evening study time. Find a quiet spot and get started!';
      case 'Late Night': return 'Night owl mode 🦉 — your study session awaits.';
      default:           return 'Your daily study reminder from GYAN.';
    }
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now  = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          kChannelId,
          'Study Reminders',
          channelDescription: 'Daily study reminders and streak nudges',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      );
} 