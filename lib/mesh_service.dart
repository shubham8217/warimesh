// WariMesh — core mesh logic, separated from UI so screens just listen.
//
// Two independent things live here:
//  1. The REAL BLE path (scan + advertise + relay decision + dedup). This
//     is unchanged behavior from the original prototype, just centralized.
//  2. DEMO MODE — a filming aid. Most Android emulators (and some real
//     phones) don't support BLE peripheral/advertise mode at all, so
//     `isAdvertisingSupported` comes back false and the real path can't
//     send anything — that's very likely why "SOS has issues" during
//     testing. Demo Mode lets you show the full send → relay → receive →
//     notification pipeline convincingly on ONE device. Everything it does
//     is tagged "(simulated)" in the log so it's never presented as a real
//     over-the-air transmission — see the honesty note in models.dart.
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'database_service.dart';
import 'foreground_service.dart';
import 'models.dart';
import 'notification_service.dart';

const Duration kSendCooldown = Duration(seconds: 10);

class MeshService extends ChangeNotifier {
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  late final String deviceLabel = _generateDeviceLabel();

  final List<LogEntry> log = [];
  int seenCount = 0;
  bool peripheralSupported = true; // assume yes until checked
  bool scanning = false;
  bool bluetoothOn = true; // assume on until adapter state says otherwise
  bool backgroundServiceEnabled = false;
  bool demoMode = true; // on by default — makes single-device filming reliable

  DateTime? _lastSendAt;
  Timer? _cooldownTicker;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  bool _disposed = false;

  Duration get cooldownRemaining {
    if (_lastSendAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(_lastSendAt!);
    final remaining = kSendCooldown - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get onCooldown => cooldownRemaining > Duration.zero;

  String _generateDeviceLabel() {
    final n = Random().nextInt(900) + 100; // 3 digits, matches DEVxxx labels used in filming docs
    return 'DEV$n';
  }

  Future<void> bootstrap() async {
    // Each step is independently guarded: one subsystem failing (DB won't
    // open, notification permission denied, foreground task plugin missing
    // on this device, …) used to be able to abort the whole bootstrap
    // silently — which is a very plausible explanation for "SOS sometimes
    // just doesn't work": one early throw and everything after it,
    // including startScanning(), never ran.
    try {
      await _requestPermissions();
    } catch (e) {
      appendLog('Permission request failed: $e', 'Warning');
    }

    try {
      await NotificationService.init();
    } catch (e) {
      appendLog('Notifications unavailable: $e', 'Warning');
    }

    try {
      await AppDatabase.instance; // ensure tables exist
      await refreshSeenCount();
    } catch (e) {
      appendLog('Local database unavailable — activity won\'t persist: $e', 'Warning');
    }

    try {
      initForegroundTask();
      FlutterForegroundTask.addTaskDataCallback(_onForegroundTaskData);
    } catch (e) {
      appendLog('Background service setup failed: $e', 'Warning');
    }

    try {
      peripheralSupported = await _blePeripheral.isSupported;
    } catch (_) {
      peripheralSupported = false;
    }
    notifyListeners();

    _watchAdapterState();
    await startScanning();
  }

  @override
  void dispose() {
    _disposed = true;
    _scanSub?.cancel();
    _adapterSub?.cancel();
    _cooldownTicker?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_onForegroundTaskData);
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // bootstrap() is a long chain of independently-awaited steps (permissions,
  // notifications, DB, BLE …) — if whatever owns this MeshService gets torn
  // down while a step is still in flight, callbacks and notifyListeners()
  // calls could otherwise land after dispose() and crash the (correct,
  // debug-only) ChangeNotifier assertion. Every notifyListeners() in this
  // class goes through here so a disposed service just quietly stops
  // announcing updates instead.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  void _onForegroundTaskData(Object data) {
    // Heartbeat from WariMeshTaskHandler; nothing to act on yet.
  }

  Future<void> _requestPermissions() async {
    await [
      ph.Permission.bluetoothScan,
      ph.Permission.bluetoothAdvertise,
      ph.Permission.bluetoothConnect,
      ph.Permission.locationWhenInUse,
      ph.Permission.notification,
    ].request();
  }

  void _watchAdapterState() {
    _adapterSub?.cancel();
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      final wasOn = bluetoothOn;
      bluetoothOn = state == BluetoothAdapterState.on;
      notifyListeners();
      if (!wasOn && bluetoothOn) {
        // Bluetooth just got turned on — pick scanning back up automatically
        // instead of leaving the app silently dead until a restart.
        startScanning();
      }
    });
  }

  Future<void> toggleBackgroundService(bool enabled) async {
    if (enabled) {
      final result = await FlutterForegroundTask.startService(
        serviceTypes: const [ForegroundServiceTypes.connectedDevice],
        notificationTitle: 'WariMesh relay active',
        notificationText: 'Keeping mesh scan/advertise alive in the background (experimental)',
        callback: startCallback,
      );
      if (result is ServiceRequestFailure) {
        appendLog('Background service failed to start: ${result.error}', 'Warning');
        return;
      }
    } else {
      await FlutterForegroundTask.stopService();
    }
    backgroundServiceEnabled = enabled;
    notifyListeners();
  }

  Future<void> startScanning() async {
    try {
      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen(_onScanResults);
      await FlutterBluePlus.startScan(
        withMsd: [MsdFilter(kManufacturerId)],
        continuousUpdates: true,
        oneByOne: true,
        androidUsesFineLocation: false,
      );
      scanning = true;
    } catch (e) {
      appendLog('Scan failed to start: $e', 'Warning');
      scanning = false;
    }
    notifyListeners();
  }

  void _onScanResults(List<ScanResult> results) {
    for (final r in results) {
      final data = r.advertisementData.manufacturerData[kManufacturerId];
      if (data == null) continue;
      final packet = MeshPacket.decode(data);
      if (packet == null) continue;
      unawaited(_handleReceivedPacket(packet));
    }
  }

  Future<void> _handleReceivedPacket(MeshPacket packet) async {
    if (packet.senderLabel == deviceLabel) return; // ignore our own advertisement bouncing back
    final alreadySeen = await SeenMessagesDb.hasSeen(packet.msgId);
    if (alreadySeen) return; // dedup — also the loop-prevention mechanism

    await SeenMessagesDb.markSeen(packet);
    await refreshSeenCount();
    appendLog(
      'Received ${categoryLabel(packet.category)} from ${packet.senderLabel} (TTL ${packet.ttl})',
      'Received',
    );
    await NotificationService.showAlertReceived(packet);

    if (packet.ttl > 0) {
      // Random jitter before relaying so nearby phones that all heard the
      // same packet don't all re-advertise in the same instant.
      final jitterMs = 300 + Random().nextInt(501); // 300–800ms
      await Future.delayed(Duration(milliseconds: jitterMs));
      final relayed = packet.relayed();
      await _advertise(relayed);
      appendLog('Relayed via $deviceLabel (TTL now ${relayed.ttl})', 'Relayed');
    } else {
      appendLog('Final hop reached $deviceLabel — not relayed further', 'Final hop');
    }
  }

  Future<void> _advertise(MeshPacket packet) async {
    try {
      if (await _blePeripheral.isAdvertising) {
        await _blePeripheral.stop();
      }
      final data = AdvertiseData(
        manufacturerId: kManufacturerId,
        manufacturerData: packet.encode(),
      );
      final settings = AdvertiseSettings(
        advertiseMode: AdvertiseMode.advertiseModeLowLatency,
        txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
        connectable: false,
        timeout: 3000, // ~3s burst — long enough for a nearby scanner to catch it, short enough not to hog the radio
      );
      await _blePeripheral.start(advertiseData: data, advertiseSettings: settings);
    } catch (e) {
      appendLog('Advertise failed: $e', 'Warning');
    }
  }

  /// Sends an alert. Returns the packet that was sent, or null if blocked
  /// (cooldown). Real BLE advertising is attempted whenever the device
  /// supports it; Demo Mode additionally narrates a simulated relay so the
  /// activity feed stays convincing even solo on one phone.
  Future<MeshPacket?> sendAlert(int category) async {
    if (onCooldown) {
      appendLog(
        'Send blocked — wait ${cooldownRemaining.inSeconds + 1}s (10s rate limit)',
        'Warning',
      );
      return null;
    }

    _lastSendAt = DateTime.now();
    _startCooldownTicker();

    final packet = MeshPacket(
      ttl: kDefaultTtl,
      msgId: Random().nextInt(0xFFFFFFFF),
      category: category,
      senderLabel: deviceLabel,
    );
    // Mark our own send as seen so a stray echo of our own advertisement
    // isn't treated as a fresh incoming alert.
    await SeenMessagesDb.markSeen(packet);
    await refreshSeenCount();

    if (peripheralSupported && bluetoothOn) {
      await _advertise(packet);
    } else if (!peripheralSupported) {
      appendLog('This device cannot advertise over real BLE (peripheral unsupported) — using Demo Mode', 'Warning');
    } else if (!bluetoothOn) {
      appendLog('Bluetooth is off — turn it on to broadcast over real BLE', 'Warning');
    }

    appendLog(
      'Sent ${categoryLabel(category)} (msg #${packet.msgId}, TTL ${packet.ttl})',
      'Sent',
    );

    if (demoMode) {
      unawaited(_simulateRelayNarration(packet));
    }

    return packet;
  }

  void _startCooldownTicker() {
    _cooldownTicker?.cancel();
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      notifyListeners();
      if (!onCooldown) t.cancel();
    });
  }

  /// Demo-only: narrates 1-2 nearby phones picking up and relaying the
  /// alert. Clearly tagged "(simulated)" and never touches the real
  /// seen_messages ledger — that table represents THIS phone's own
  /// dedup history, not another phone's.
  Future<void> _simulateRelayNarration(MeshPacket packet) async {
    final hops = 1 + Random().nextInt(2); // 1-2 simulated nearby phones
    for (var i = 0; i < hops; i++) {
      await Future.delayed(Duration(milliseconds: 500 + Random().nextInt(700)));
      final fakeLabel = 'DEV${Random().nextInt(900) + 100}';
      appendLog(
        '📡 $fakeLabel picked up your ${categoryLabel(packet.category)} and relayed it (simulated)',
        'Demo',
      );
    }
  }

  /// Manually feeds a synthetic packet into the exact same
  /// `_handleReceivedPacket` pipeline a real BLE scan result would hit:
  /// decode → dedup → SQLite → notification → relay decision. Useful to
  /// show a genuine incoming-alert notification on camera without needing
  /// a second phone. Clearly tagged as simulated in the log.
  Future<void> simulateIncomingAlert(int category) async {
    final fakeSender = 'DEV${Random().nextInt(900) + 100}';
    final packet = MeshPacket(
      ttl: kDefaultTtl,
      msgId: Random().nextInt(0xFFFFFFFF),
      category: category,
      senderLabel: fakeSender,
    );
    appendLog('Simulating an incoming alert from $fakeSender (demo)', 'Demo');
    await _handleReceivedPacket(packet);
  }

  Future<void> refreshSeenCount() async {
    seenCount = await SeenMessagesDb.count();
    notifyListeners();
  }

  void appendLog(String text, String kind) {
    log.insert(0, LogEntry(text, kind));
    if (log.length > 200) log.removeLast();
    notifyListeners();
  }
}
