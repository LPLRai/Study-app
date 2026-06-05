// ─────────────────────────────────────────────────────────────────────────────
// services/push_service.dart
//
// Firebase Cloud Messaging (FCM) + local-notification glue so the user sees a
// real phone notification for group invites and "notify to study" pings — even
// when the app is in the background or closed.
//
// How delivery works end-to-end:
//   1. A user action writes a notification doc under
//      study_app_users/{uid}/notifications/{id}  (already happens in
//      FirebaseService.inviteByEmail / sendStudyReminder).
//   2. A Cloud Function (see functions/index.js + the deploy guide) triggers on
//      that write and sends an FCM push to every token in the recipient's
//      `fcmTokens`.
//   3. Background / terminated → Android shows it in the tray automatically.
//      Foreground → we display it ourselves via flutter_local_notifications.
//
// This file is the CLIENT side; it registers the device token and shows
// foreground notifications. It never throws into app start-up.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_service.dart';

const String kChannelId = 'gyan_default_channel';
const String _channelName = 'General';
const String _channelDesc = 'Group invites and study reminders';

final FlutterLocalNotificationsPlugin _localNotifs =
    FlutterLocalNotificationsPlugin();

/// Background / terminated handler — MUST be a top-level (or static) function.
/// Notification-type messages are shown by the OS automatically, so there's
/// nothing to do here yet (kept for future data-only messages).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _started = false;
  String? _token;

  /// Call once the user is signed in. Safe to call repeatedly.
  Future<void> init() async {
    if (_started) return;
    _started = true;
    try {
      final messaging = FirebaseMessaging.instance;

      // Ask for permission (shows the OS prompt on Android 13+ / iOS).
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // Local-notification plugin + Android channel (for foreground display).
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(
          android: androidInit, iOS: DarwinInitializationSettings());
      await _localNotifs.initialize(initSettings);
      await _localNotifs
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            kChannelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
          ));

      // iOS: still show a banner while the app is in the foreground.
      await messaging.setForegroundNotificationPresentationOptions(
          alert: true, badge: true, sound: true);

      // Register this device's token, and keep it fresh.
      _token = await messaging.getToken();
      if (_token != null) {
        await FirebaseService.instance.saveFcmToken(_token!);
      }
      messaging.onTokenRefresh.listen((t) {
        _token = t;
        FirebaseService.instance.saveFcmToken(t);
      });

      // Foreground messages aren't shown by the OS — display them ourselves.
      FirebaseMessaging.onMessage.listen(_showForeground);
    } catch (_) {
      // Never block app start-up on push setup.
    }
  }

  void _showForeground(RemoteMessage message) {
    final n = message.notification;
    final title = n?.title ?? (message.data['title'] as String?) ?? 'GYAN';
    final body = n?.body ?? (message.data['body'] as String?) ?? '';
    if (n == null && body.isEmpty) return;
    _localNotifs.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          kChannelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// On sign-out: detach this device's token so it stops receiving the previous
  /// account's notifications.
  Future<void> clearToken() async {
    try {
      if (_token != null) {
        await FirebaseService.instance.removeFcmToken(_token!);
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _token = null;
    _started = false;
  }
}
