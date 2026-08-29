// WariMesh — foreground service scaffolding.
//
// Started automatically at bootstrap (see MeshService.bootstrap) together
// with a battery-optimisation exemption request, because an emergency app
// that stops relaying when the screen locks isn't doing its job. The two
// together are what keep the process alive and unfrozen in the background.
//
// HONESTY NOTE (read before claiming the locked-screen scenario works):
// This keeps the Android *process* alive (persistent notification, wake
// lock). It does NOT move the actual BLE scan/advertise calls into the
// foreground task's background isolate — `FlutterBluePlus` and
// `FlutterBlePeripheral` are still driven from the main isolate in
// `MeshService`. That should keep working while the process lives, but how
// long an aggressive OEM ROM (MIUI especially) actually honours that is
// device-specific and still worth measuring on real hardware rather than
// asserting.
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
