// WariMesh — foreground service scaffolding.
//
// HONESTY NOTE (read before assuming the locked-screen scenario works):
// This keeps the Android *process* alive longer in the background
// (persistent notification, wake lock). It does NOT move the actual BLE
// scan/advertise calls into the foreground task's background isolate —
// `FlutterBluePlus` and `FlutterBlePeripheral` are still driven from the
// main isolate in `MeshService`. Whether a foreground service alone is
// enough to keep those calls running with the screen locked is genuinely
// unverified. Keep the app foregrounded and the screen on while filming.
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(WariMeshTaskHandler());
}

class WariMeshTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Heartbeat only, so the main isolate (and the UI, if visible) can see
    // the service is still alive. Deliberately does not touch BLE — real
    // scan/advertise calls live in MeshService, not here.
    FlutterForegroundTask.sendDataToMain(
      'heartbeat:${timestamp.millisecondsSinceEpoch}',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

void initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'warimesh_fg',
      channelName: 'WariMesh background relay',
      channelDescription:
          'Keeps the mesh scan/advertise process alive while the screen is off (experimental, unverified)',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(15000),
      autoRunOnBoot: false,
      allowWakeLock: true,
    ),
  );
}
