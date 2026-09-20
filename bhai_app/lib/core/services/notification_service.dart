import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin),
      );
    } catch (_) {}
  }

  Future<void> showEmergencyActive() async {
    if (kIsWeb) return;
    try {
      await _plugin.show(
        101,
        'BHAI emergency active',
        'Location sharing is active while BHAI remains open and permissions allow.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'bhai_emergency_status',
            'BHAI Emergency Status',
            channelDescription: 'Persistent status while a BHAI emergency is active',
            importance: Importance.max,
            priority: Priority.high,
            ongoing: true,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> showNearbyBluetoothAlert({String? senderId, int? rssi}) async {
    if (kIsWeb) return;
    try {
      await _plugin.show(
        202,
        '🚨 EMERGENCY ALERT',
        'A Bhai user nearby needs help. Please check your surroundings and assist if you can.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'bhai_nearby_alerts',
            'BHAI Nearby Alerts',
            channelDescription: 'Opt-in alerts received from nearby Bluetooth distress beacons',
            importance: Importance.max,
            priority: Priority.high,
            enableVibration: true,
            playSound: true,
            fullScreenIntent: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.critical,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> clearEmergencyActive() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(101);
    } catch (_) {}
  }

  Future<void> showIncomingChatMessage({
    required String senderId,
    required String message,
  }) async {
    if (kIsWeb) return;
    try {
      await _plugin.show(
        303,
        '💬 Message from BHAI-$senderId',
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'bhai_chat_messages',
            'BHAI Emergency Chat',
            channelDescription: 'Real-time messages between emergency victims and responders',
            importance: Importance.max,
            priority: Priority.high,
            enableVibration: true,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> clearNearbyAlert() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(202);
    } catch (_) {}
  }
}
