// WariMesh — fires a real Android notification (sound + vibration) whenever
// this phone receives an alert over the mesh, independent of whether the
// live activity screen is even open.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'models.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const String _channelId = 'warimesh_alerts';

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
    );
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Mesh alerts',
        description: 'Fires when this phone receives an SOS or Lost Person alert over the mesh',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  static Future<void> showAlertReceived(MeshPacket packet) async {
    final isSos = packet.category == kCategorySos;
    await _plugin.show(
      // Notification IDs are 32-bit on the Android side; msgId is a uint32
      // and can exceed that, so fold it down instead of passing it raw.
      id: packet.msgId % 100000,
      title: isSos ? '🆘 SOS received' : '🔎 Lost Person alert',
      body: 'From ${packet.senderLabel} · TTL ${packet.ttl}',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Mesh alerts',
          channelDescription: 'Fires when this phone receives an SOS or Lost Person alert over the mesh',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }
}
