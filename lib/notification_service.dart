// WariMesh — fires a real Android notification (sound + vibration) whenever
// this phone receives an alert over the mesh, independent of whether the
// live activity screen is even open.
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'l10n/app_strings.dart';
import 'models.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const String _channelId = 'warimesh_alerts';
  static const String _advisoryChannelId = 'warimesh_advisories';

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidInit),
    );
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Mesh alerts',
        description:
            'Fires when this phone receives an SOS or Lost Person alert over the mesh',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    // A separate channel so someone can mute advisories without muting
    // emergencies — Android channel settings are per-channel, and the two
    // must never share one.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _advisoryChannelId,
        'Advisories',
        description: 'Announcements from volunteers along the route',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  /// Fires the system notification for an incoming alert. [senderName] and
  /// [lostName] are shown when known so the notification is actionable from
  /// the lock screen — "Aarav, age 8 is missing" beats "Lost Person alert".
  static Future<void> showAlertReceived(
    MeshPacket packet, {
    String? senderName,
    String? lostName,
    String? lostAge,
    String? distanceLabel,
    String? directionLabel,
    bool isUpdate = false,
  }) async {
    final isSos = packet.category == kCategorySos;
    final from = senderName ?? packet.senderLabel;
    final reason = packet.reason;

    // "240 m away to your north-east" is the difference between an alert
    // someone can act on and one they can only feel bad about. Built here
    // rather than in the caller so it reads the same on the lock screen as
    // it does in the app.
    final where = distanceLabel == null
        ? ''
        : directionLabel == null
        ? ' — $distanceLabel'
        : ' — $distanceLabel, to your $directionLabel';

    final String body;
    if (isSos && reason != null && sosReasonIsSpecific(reason)) {
      // The reason is the whole point of putting it on the lock screen:
      // "Rahul needs help" tells a volunteer to go, "Rahul — Medical" tells
      // them what to bring. See kSosReason* in models.dart.
      body = '$from — ${t.sosReason(reason)}$where';
    } else if (isSos) {
      body = t.notifNeedsHelp(from, where);
    } else if (lostName != null && lostName.isNotEmpty) {
      final age = (lostAge == null || lostAge.isEmpty)
          ? ''
          : ', ${t.notifAgePrefix} $lostAge';
      body = t.notifLookFor(lostName, age, from, where);
    } else {
      body = t.notifSomeoneMissing(from, where);
    }

    await _plugin.show(
      // Notification IDs are 32-bit on the Android side; msgId is a uint32
      // and can exceed that, so fold it down instead of passing it raw.
      id: packet.msgId % 100000,
      title: !isSos
          ? t.notifMissingTitle
          : sosReasonIsSpecific(reason)
          ? '${sosReasonEmoji(reason)} ${t.sosReason(reason)} — SOS'
          : t.notifSosTitle,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Mesh alerts',
          channelDescription:
              'Fires when this phone receives an SOS or Lost Person alert over the mesh',
          importance: Importance.max,
          priority: Priority.max,
          // An update re-posts the same notification id to add the distance
          // once the sender's position arrives (it travels in a separate
          // packet and lands a few seconds after the alert). It must not
          // sound the alarm a second time — the person has already been
          // interrupted, and an emergency tone that fires twice for one
          // event teaches people to distrust it.
          playSound: !isUpdate,
          enableVibration: !isUpdate,
          onlyAlertOnce: isUpdate,
          // An emergency alert has to survive a locked screen and a phone
          // in a pocket, so: full-screen intent wakes the display rather
          // than sliding past unseen; alarm category exempts it from Doze
          // batching; ongoing + autoCancel:false stop it being swiped away
          // before anyone reads it; public visibility shows the text on the
          // lock screen instead of hiding it behind "1 new notification".
          fullScreenIntent: isSos,
          category: isSos
              ? AndroidNotificationCategory.alarm
              : AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
          ongoing: isSos,
          autoCancel: !isSos,
          styleInformation: BigTextStyleInformation(body),
          vibrationPattern: (isSos && !isUpdate) ? _sosVibration : null,
        ),
      ),
    );
  }

  /// Fires for an advisory from a volunteer — a route change, a closed
  /// water point, weather. Deliberately quieter than an alert: high enough
  /// priority to be seen promptly, but no full-screen intent, no alarm
  /// category, and no SOS vibration. An advisory that shouts as loudly as an
  /// emergency trains people to ignore both.
  static Future<void> showAdvisory(MeshTextMessage message) async {
    await _plugin.show(
      // Offset from the alert id space (msgId % 100000) so an advisory can
      // never replace an SOS notification that happens to fold to the same
      // number.
      id: 100000 + (message.msgId % 100000),
      title: t.notifAdvisoryTitle(message.displayName),
      body: message.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _advisoryChannelId,
          'Advisories',
          channelDescription: 'Announcements from volunteers along the route',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.public,
          styleInformation: BigTextStyleInformation(message.body),
        ),
      ),
    );
  }

  /// Fires on the phone that sent an alert, the moment a volunteer claims
  /// it — "Sunita is coming to help you."
  ///
  /// This one is worth interrupting for even though it is not an emergency,
  /// because of who receives it and what they are doing: somebody who
  /// pressed SOS and is now standing in a crowd with no idea whether
  /// anything happened. It is also, unlike the SOS itself, deliberately
  /// dismissible — it is good news, not a summons.
  static Future<void> showResponderComing(String who) async {
    await _plugin.show(
      // Its own fixed id: a second responder replaces the first rather than
      // stacking, and this can never collide with an alert notification.
      id: 900001,
      title: t.notifHelpComingTitle,
      body: t.notifHelpComingBody(who),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Mesh alerts',
          channelDescription:
              'Fires when this phone receives an SOS or Lost Person alert over the mesh',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.public,
          autoCancel: true,
        ),
      ),
    );
  }

  /// Fires on the phone that reported someone missing, the moment anybody
  /// on the mesh reports laying eyes on them — see kSpottedPacketType.
  ///
  /// Like [showResponderComing] this is worth interrupting for because of
  /// who receives it: somebody who has been walking a route looking for a
  /// child. Also like it, this is dismissible — it is news, not a summons.
  static Future<void> showPersonSpotted(String who, {String? lostName}) async {
    final subject = (lostName == null || lostName.isEmpty)
        ? t.notifThePersonYouReported
        : lostName;
    await _plugin.show(
      // Its own fixed id, next to showResponderComing's, so a sighting
      // replaces the previous sighting rather than stacking and can never
      // collide with an alert notification.
      id: 900002,
      title: t.notifSightingTitle,
      body: t.notifSightingBody(who, subject),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Mesh alerts',
          channelDescription:
              'Fires when this phone receives an SOS or Lost Person alert over the mesh',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          visibility: NotificationVisibility.public,
          autoCancel: true,
        ),
      ),
    );
  }

  // Long-short-long-short — deliberately unlike a normal message buzz.
  static final Int64List _sosVibration = Int64List.fromList([
    0,
    600,
    300,
    600,
    300,
    600,
  ]);
}
