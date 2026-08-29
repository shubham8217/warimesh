// WariMesh — core mesh logic, separated from UI so screens just listen.
//
// This is the real BLE path only: scan, advertise, relay decision, dedup.
//
// It used to also carry a "Demo Mode" that narrated invented nearby phones
// relaying your alert, for filming on a single device. That is gone. Once
// there are real phones to test against, simulated hops in the activity log
// are worse than useless — they make a broken mesh look like a working one,
// which is the single most expensive kind of bug to chase.
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'database_service.dart';
import 'foreground_service.dart';
import 'location_service.dart';
import 'models.dart';
import 'notification_service.dart';

const Duration kSendCooldown = Duration(seconds: 10);
const Duration kPresenceInterval = Duration(seconds: 15);
// A presence entry older than this is dropped from the headcount — if we
// haven't heard someone in 3 beacon intervals, treat them as out of range
// rather than showing a stale headcount that never shrinks.
const Duration kPresenceExpiry = Duration(seconds: 45);
// How long a person stays *remembered* after they stop being *nearby*. Far
// longer than kPresenceExpiry on purpose — see MeshService._evictStalePresence
// for why a name outlives a presence, and why the map needs a bound at all.
const Duration kPresenceMemory = Duration(minutes: 30);

// ---------------------------------------------------------------------------
// Airtime — why an alert stays on the air for a minute, not three seconds.
//
// When the receiving phone's screen is OFF, Android does NOT honour the
// scan mode the app asked for. AOSP's ScanManager forces every scan into
// SCAN_MODE_SCREEN_OFF: roughly a 512ms listening window once every
// 5120ms, i.e. the radio is deaf ~90% of the time. A one-shot 3-second
// advertisement is therefore a coin flip, and when it loses, the alert is
// gone permanently — there was no retry.
//
// So a broadcast is no longer "advertise once and hope". Anything this
// phone wants heard is registered with the rotation below and re-put on
// the air, slot after slot, until its airtime expires. Sixty seconds of
// repetition against a 10%-duty-cycle listener is the difference between
// "usually missed" and "essentially certain".
// Deliberately long. Every slot boundary that changes payload costs a
// stop/start of the advertiser, and Android's BLE stack is fragile under
// that churn (see the note in _serviceAdvertSlotInner). A lone SOS never
// changes payload at all, so it claims the radio once and holds it.
const Duration kAdvertSlot = Duration(seconds: 5);
// Text fragments rotate faster than alerts. A message split into six
// fragments would take half a minute to deliver at the alert slot, which is
// useless for chat — but the churn that pace causes is bounded (it lasts
// only as long as the message's airtime) rather than the endless rotation
// that wedged the advertiser before. Alerts keep the slow, safe slot.
const Duration kTextSlot = Duration(seconds: 2);
const Duration kTextAirtime = Duration(seconds: 40);
// Half-received messages don't wait forever for a fragment that was lost to
// a passing bus; the sender re-airs the whole message for kTextAirtime, so
// a genuinely reachable phone gets another chance well inside this window.
const Duration kTextAssemblyExpiry = Duration(seconds: 90);
const Duration kAlertAirtime = Duration(seconds: 60); // an alert we originated
const Duration kRelayAirtime = Duration(
  seconds: 45,
); // an alert we're passing on

// Airtime priorities. Only the top live tier gets the radio (see
// _serviceAdvertSlotInner), so these are a strict pecking order, not
// weights: an SOS silences chat, and chat silences the headcount beacon.
const int kPriorityPresence = 0;
const int kPriorityText = 1;
const int kPriorityAlert = 2;

// ACK and RESOLVE ride at kPriorityAlert, NOT above it. It's tempting to
// give a response packet the top of the pecking order — it is, after all,
// the most welcome thing on the network — but the top-tier rule in
// _serviceAdvertSlotInner means a strictly higher priority would silence
// every alert relay for as long as the response is on the air. An ACK that
// stops an SOS propagating is a bug wearing a helpful face. Same tier,
// sharing the rotation, is the correct relationship: a response matters
// exactly as much as the alert it answers.
const Duration kResponseAirtime = Duration(seconds: 45);

// HELP_POINT — the Wari Seva Network. Airtime/priority mirror the alert
// tier reasoning above: an announcement is worth carrying as long as an
// alert (kAlertAirtime/kRelayAirtime) since "where is the medical tent" is
// exactly the kind of thing a screen-off receiver must not miss, but it
// must never outrank an actual SOS. It shares the alert priority tier for
// that reason — same relationship kResponseAirtime has to alerts above.
const int kPriorityHelpPoint = kPriorityAlert;
const Duration kHelpPointAirtime = Duration(
  seconds: 60,
); // a help point we announced
const Duration kHelpPointRelayAirtime = Duration(
  seconds: 45,
); // one we're passing on
const Duration kHelpPointStatusAirtime = Duration(
  seconds: 45,
); // a close/status update

/// One payload this phone is currently putting on the air, and until when.
///
/// [key] identifies the payload so re-registering the same alert refreshes
/// its airtime instead of stacking duplicates. [priority] buys extra slots
/// in the rotation — an SOS must not lose airtime to a headcount beacon.
class _Broadcast {
  final String key;
  final Uint8List bytes;
  final DateTime expiresAt;
  final int priority;

  /// How long this payload holds the radio before the rotation moves on.
  /// Text uses a shorter slot than alerts so a fragmented message arrives
  /// in seconds rather than half a minute — see kTextSlot.
  final Duration slot;
  _Broadcast(this.key, this.bytes, this.expiresAt, this.priority, this.slot);
}

/// Fragments of one text message gathered so far. [head] stays null until
/// fragment 0 arrives, which is what tells us who sent it and how many
/// fragments to expect — parts can and do arrive first.
class _TextAssembly {
  final int msgId;
  final DateTime startedAt = DateTime.now();
  final Map<int, String> chunks = {};
  TextHeadPacket? head;
  int? total;
  _TextAssembly(this.msgId);
}

class _PresenceEntry {
  final String groupTag;
  final String name;
  final DateTime lastHeard;
  final int station;
  final bool isDindiLead;
  _PresenceEntry(
    this.groupTag,
    this.name,
    this.lastHeard,
    this.station,
    this.isDindiLead,
  );
}

/// A volunteer's phone heard nearby that is staffing a help point.
///
/// There is deliberately no distance or direction here, and that is not an
/// omission. A presence beacon carries no location — by design, since a
/// continuously broadcast position is a very different privacy proposition
/// from the one-off position attached to an alert you chose to send. What
/// stands in for a distance is the physics: BLE advertising carries on the
/// order of tens of metres in a dense crowd. If you can hear this beacon at
/// all, the help point is close enough to walk to. "In range" IS the
/// proximity signal, and the UI says exactly that rather than inventing a
/// precision the packet doesn't contain.
class HelpPoint {
  final String meshId;
  final String name;
  final int station;
  final DateTime lastHeard;

  HelpPoint({
    required this.meshId,
    required this.name,
    required this.station,
    required this.lastHeard,
  });

  String get label => stationLabel(station);

  /// "heard just now" / "heard 2 min ago" — the honest freshness signal.
  /// A volunteer walks away and their beacon goes stale; a help point that
  /// was here 40 seconds ago is worth walking towards, one from 20 minutes
  /// ago is not, and the difference must be visible.
  String get freshnessLabel {
    final secs = DateTime.now().difference(lastHeard).inSeconds;
    if (secs < 30) return 'heard just now';
    if (secs < 90) return 'heard a minute ago';
    return 'heard ${(secs / 60).round()} min ago';
  }
}

class MeshService extends ChangeNotifier {
  final FlutterBlePeripheral _blePeripheral = FlutterBlePeripheral();

  // Set by bootstrap(profile) before anything else runs. Falls back to a
  // throwaway random identity only if bootstrap() is ever called without a
  // signed-in profile (shouldn't happen — AuthGate always signs in first —
  // but keeps this class from crashing if that assumption ever breaks).
  String deviceLabel = 'V${Random().nextInt(90000) + 10000}'.substring(0, 6);
  String _myGroupTag = '--';
  String _myName = '';
  UserRole _myRole = UserRole.volunteer;
  int _myStation = kStationNone;
  bool _amDindiLead = false;

  /// This phone's own Mesh ID, as it appears in every packet it sends.
  String get myMeshId => deviceLabel;

  /// Which help point this phone is announcing, or [kStationNone].
  int get myStation => _myStation;
  bool get onDuty => _myStation != kStationNone;

  /// Whether this phone has declared itself the Dindi Lead of its own
  /// Dindi — see UserProfile.isDindiLead for the trust model.
  bool get amDindiLead => _amDindiLead;

  final List<LogEntry> log = [];
  int seenCount = 0;
  bool peripheralSupported = true; // assume yes until checked
  bool scanning = false;
  bool bluetoothOn = true; // assume on until adapter state says otherwise
  bool backgroundServiceEnabled = false;

  DateTime? _lastSendAt;
  Timer? _cooldownTicker;
  Timer? _presenceTicker;
  Timer? _advertTicker;
  Timer? _scanWatchdog;
  AppLifecycleListener? _lifecycle;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  bool _disposed = false;

  // Everything currently being put on the air, and the rotation state that
  // takes turns between them. See the airtime note above kAdvertSlot for
  // why a broadcast repeats rather than firing once.
  final List<_Broadcast> _broadcasts = [];
  int _slotCursor = 0;
  bool _servicingSlot = false;
  Duration?
  _advertPeriod; // cadence the rotation ticker is currently running at
  DateTime? _lastServiceRestart;
  int _serviceRestarts = 0;
  List<int>? _onAir; // payload the radio is advertising right now, if any

  // meshId -> last-heard presence beacon. Populated purely by receiving
  // PresencePacket broadcasts (see models.dart) — never by SOS/Lost Person
  // traffic, and never relayed further (single-hop by construction).
  final Map<String, _PresenceEntry> _presence = {};

  /// The durable alert queue — every alert this phone has received or sent,
  /// with who is responding and whether it's closed. Loaded from SQLite at
  /// bootstrap and kept in sync from there; see [AlertRecord].
  final List<AlertRecord> alerts = [];

  /// Alerts still needing someone, in triage order. This is the volunteer's
  /// actual workload and the number on the Alerts tab badge.
  List<AlertRecord> get openAlerts =>
      alerts.where((a) => !a.isResolved && !a.mine).toList()..sort(_byTriage);

  /// The whole queue in triage order, resolved ones sunk to the bottom.
  List<AlertRecord> get triagedAlerts =>
      List<AlertRecord>.from(alerts)..sort(_byTriage);

  int get unclaimedCount => alerts.where((a) => a.isOpen && !a.mine).length;

  /// The Wari Seva Network's durable queue — every HELP_POINT this phone has
  /// announced or received, mirroring how [alerts] backs the SOS queue.
  /// Loaded from SQLite at bootstrap; see [HelpPointRecord].
  final List<HelpPointRecord> helpPoints = [];

  /// Help points worth showing right now: not closed, not expired. This is
  /// what "Nearby Seva" on the Home screen renders — see HelpPointRecord.isActive.
  List<HelpPointRecord> get activeHelpPoints {
    final points = helpPoints.where((h) => h.isActive).toList();
    points.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return points;
  }

  /// The msgId of the help point THIS phone currently has announced, if
  /// any — what "Off duty" (or switching to a different station) has to
  /// close. Null when this phone isn't currently a help point.
  int? _myActiveHelpPointMsgId;

  /// Seva worth offering someone in a given kind of emergency — the SOS →
  /// Seva bridge. Purely a filter over help points this phone has ALREADY
  /// heard announced through the mesh (see [activeHelpPoints]): it asks the
  /// network for nothing, and a help point that has not announced itself
  /// simply does not exist here. An empty list is a completely normal
  /// answer and the UI shows nothing rather than a placeholder.
  ///
  /// Ordered by how relevant the station is to the reason (see
  /// sevaStationsForReason), then freshest first inside each kind — a water
  /// point heard 30 seconds ago is worth more than one heard 20 minutes ago.
  List<HelpPointRecord> sevaForReason(int reason) {
    final wanted = sevaStationsForReason(reason);
    if (wanted.isEmpty) return const [];
    final active = activeHelpPoints;
    final matched = <HelpPointRecord>[];
    for (final station in wanted) {
      final ofKind = active.where((h) => h.helpType == station).toList()
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      matched.addAll(ofKind);
    }
    return matched;
  }

  static int _byTriage(AlertRecord a, AlertRecord b) {
    final rank = a.triageRank.compareTo(b.triageRank);
    if (rank != 0) return rank;
    // Within a tier, oldest first: the person who has been waiting longest
    // is the person who has been waiting longest.
    return a.receivedAt.compareTo(b.receivedAt);
  }

  /// Help points heard recently, freshest first. See [HelpPoint] for why
  /// there is no distance attached to these.
  List<HelpPoint> get helpPointsInRange {
    final cutoff = DateTime.now().subtract(kPresenceExpiry);
    final points = <HelpPoint>[];
    _presence.forEach((meshId, entry) {
      if (entry.station == kStationNone) return;
      if (entry.lastHeard.isBefore(cutoff)) return;
      points.add(
        HelpPoint(
          meshId: meshId,
          name: entry.name,
          station: entry.station,
          lastHeard: entry.lastHeard,
        ),
      );
    });
    points.sort((a, b) => b.lastHeard.compareTo(a.lastHeard));
    return points;
  }

  /// Dindi members heard recently (within kPresenceExpiry), plus yourself.
  int get dindiHeadcount => 1 + dindiMemberNames.length;

  // Alerts received but not yet acknowledged by the person. The UI shows
  // these one at a time as a blocking screen that can't be swiped away —
  // an emergency alert that vanishes on its own is worse than useless. See
  // alert_overlay.dart.
  final List<IncomingAlert> pendingAlerts = [];

  // msgId -> the name/age that arrived on a LostPersonDetailPacket. Kept
  // separately from pendingAlerts because the detail packet can land
  // either just before or just after the alert it belongs to.
  final Map<int, LostPersonDetailPacket> _lostDetails = {};

  // msgId -> where that alert was sent from. Same arrive-in-any-order
  // problem as _lostDetails: the location packet can land before or after
  // the alert it belongs to.
  final Map<int, LocationPacket> _alertLocations = {};

  // msgId -> fragments gathered so far for a text message still being
  // reassembled. Entries are dropped once complete or once they age out
  // (see kTextAssemblyExpiry).
  final Map<int, _TextAssembly> _assembling = {};

  // (msgId, fragmentIndex) pairs already relayed, so a fragment heard from
  // three neighbours is only re-aired once. Alerts use the SQLite ledger for
  // this; a fragment is far more numerous and far less important, so an
  // in-memory set is the right trade.
  final Set<String> _relayedFragments = {};

  // Response packets (ACK / RESOLVE) this phone has already passed on.
  // Neither format has room for a TTL, so relay-exactly-once per phone is
  // what stops a response echoing around a dense crowd forever. Same
  // approach as _relayedFragments above.
  final Set<String> _relayedResponses = {};

  // Messages already reassembled in full. The sender re-airs every fragment
  // for the whole of kTextAirtime, so the same message arrives over and
  // over; without this each repeat rebuilds the assembly and files a fresh
  // copy. Relying on the database insert to reject the duplicate is not
  // enough — the conflict-ignore return value can't be trusted to
  // distinguish "inserted" from "ignored" for a rowid-aliased primary key.
  final Set<int> _completedTextIds = {};

  /// The Dindi conversation plus any advisories, oldest first. Loaded from
  /// SQLite at bootstrap so a restart doesn't lose the thread.
  final List<MeshTextMessage> messages = [];

  /// Messages that arrived while the chat screen wasn't open, so a badge can
  /// show there's something to read.
  int unreadMessages = 0;

  void markMessagesRead() {
    if (unreadMessages == 0) return;
    unreadMessages = 0;
    notifyListeners();
  }

  /// This phone's own position, used both to stamp outgoing alerts and to
  /// work out how far away an incoming one is.
  final LocationService location = LocationService();

  /// Whether this phone currently knows where it is — surfaced in the UI so
  /// someone can tell before an emergency that their SOS won't carry a
  /// location.
  bool get hasLocationFix => location.hasFix;

  /// Marks the oldest pending alert as seen and moves to the next, if any.
  void acknowledgeAlert() {
    if (pendingAlerts.isEmpty) return;
    pendingAlerts.removeAt(0);
    notifyListeners();
  }

  /// The first name last heard for [meshId] via a presence beacon, if we
  /// have one — lets an alert say "Priya" instead of "W7K2M9".
  String? nameFor(String meshId) {
    final name = _presence[meshId]?.name;
    return (name == null || name.isEmpty) ? null : name;
  }

  /// First names of other people in your Dindi heard recently — nearby,
  /// not necessarily still there this second. Falls back to a person's
  /// Mesh ID if their presence beacon somehow carried an empty name.
  List<String> get dindiMemberNames {
    final cutoff = DateTime.now().subtract(kPresenceExpiry);
    return _presence.entries
        .where(
          (e) =>
              e.value.groupTag == _myGroupTag &&
              e.value.lastHeard.isAfter(cutoff),
        )
        .map((e) => e.value.name.isEmpty ? e.key : e.value.name)
        .toList();
  }

  /// The Mesh ID of this Dindi's Lead, if one is known — either this phone
  /// itself, or a Lead heard recently via presence. Null covers two
  /// legitimate edge cases the same way: no Lead has been designated for
  /// this Dindi, or the Lead is currently out of range — SOS still reaches
  /// Volunteers normally either way (see MeshService.dindiEmergencies and
  /// the routing note in models.dart).
  String? get dindiLeadMeshId {
    if (_amDindiLead) return deviceLabel;
    final cutoff = DateTime.now().subtract(kPresenceExpiry);
    for (final entry in _presence.entries) {
      if (entry.value.groupTag == _myGroupTag &&
          entry.value.isDindiLead &&
          entry.value.lastHeard.isAfter(cutoff)) {
        return entry.key;
      }
    }
    return null;
  }

  /// The Lead's first name, when known — falls back to their Mesh ID, same
  /// as every other name lookup in this file.
  String? get dindiLeadName {
    final id = dindiLeadMeshId;
    if (id == null) return null;
    if (id == deviceLabel) return _myName.isEmpty ? id : _myName;
    return nameFor(id) ?? id;
  }

  /// How a responder should be named on screen — "Sunita · Volunteer" /
  /// "Rahul · Dindi Lead" — see responderRoleLabel() in models.dart for the
  /// pure logic this just supplies presence data to.
  String responderRoleLabelFor(String meshId) => responderRoleLabel(
    meshId,
    isDindiLead: meshId == deviceLabel
        ? _amDindiLead
        : (_presence[meshId]?.isDindiLead ?? false),
  );

  /// Open SOS alerts from this phone's own Dindi — a Dindi Lead's
  /// "DINDI EMERGENCIES" queue. See isDindiEmergency() in models.dart for
  /// the filter itself; this just applies it and sorts the way the
  /// volunteer queue does (unclaimed SOS first, oldest first — see
  /// _byTriage).
  List<AlertRecord> get dindiEmergencies =>
      alerts.where((a) => isDindiEmergency(a, _myGroupTag)).toList()
        ..sort(_byTriage);

  Duration get cooldownRemaining {
    if (_lastSendAt == null) return Duration.zero;
    final elapsed = DateTime.now().difference(_lastSendAt!);
    final remaining = kSendCooldown - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get onCooldown => cooldownRemaining > Duration.zero;

  /// A warkari can create/join a Dindi any time from the Home screen (see
  /// dindi_picker.dart), not just at sign-in — this updates the tag used
  /// for notification tiering immediately, without needing to restart
  /// bootstrap() or the mesh scan/advertise loop.
  void updateDindi(String groupOrId) {
    _myGroupTag = dindiTagFor(groupOrId);
    notifyListeners();
  }

  /// Goes on or off duty at a help point. Takes effect on the next presence
  /// beacon, and re-airs one immediately so a volunteer who has just opened
  /// the water tent doesn't stay invisible for up to 15 seconds.
  ///
  /// This drives two independent signals, not one: the ambient presence
  /// beacon above (single-hop, dies quietly 45s after this phone stops
  /// sending it — see kPresenceExpiry) keeps working exactly as before, and
  /// is now joined by a relayed [HelpPointPacket] announcement (multi-hop,
  /// explicitly closed, durable) — see the note on kHelpPointPacketType in
  /// models.dart for why one beacon can't do both jobs. Switching stations
  /// closes the old announcement before opening the new one, and going off
  /// duty closes it outright.
  void setStation(int station) {
    if (_myStation == station) return;
    if (_myActiveHelpPointMsgId != null) {
      _closeHelpPoint(_myActiveHelpPointMsgId!);
    }
    _myStation = station;
    appendLog(
      station == kStationNone
          ? 'Off duty — no longer announcing a help point'
          : 'On duty: ${stationLabel(station)} — nearby phones will see this',
      'Sent',
    );
    _broadcastPresence();
    if (station != kStationNone) {
      unawaited(_announceHelpPoint(station));
    }
    notifyListeners();
  }

  /// Declares (or un-declares) this phone as its Dindi's Lead. Takes effect
  /// on the next presence beacon, re-aired immediately — same reasoning as
  /// [setStation]. Self-declared and unauthenticated: see the note on
  /// UserProfile.isDindiLead.
  void setDindiLead(bool value) {
    if (_amDindiLead == value) return;
    _amDindiLead = value;
    appendLog(
      value
          ? 'You are now the Dindi Lead — SOS from your Dindi will be shown here as Dindi Emergencies'
          : 'No longer the Dindi Lead',
      'Sent',
    );
    _broadcastPresence();
    notifyListeners();
  }

  /// Puts one HELP_POINT announcement on the air and files it into
  /// [helpPoints] as our own. Public entry point is [setStation] — this is
  /// also what re-arms the announcement at bootstrap for a volunteer whose
  /// duty state survived an app restart (see bootstrap()).
  Future<void> _announceHelpPoint(
    int helpType, {
    int status = kHelpStatusOpen,
  }) async {
    final msgId = Random().nextInt(0xFFFFFFFF);
    final packet = HelpPointPacket(
      ttl: kDefaultTtl,
      msgId: msgId,
      helpType: helpType,
      status: status,
      senderLabel: deviceLabel,
      expiresInMinutesDiv5: (helpPointDefaultExpiry(helpType).inMinutes ~/ 5)
          .clamp(1, 255),
    );
    await SeenMessagesDb.markSeenRaw(
      msgId,
      category: kHelpPointPacketType,
      senderLabel: deviceLabel,
      ttl: kDefaultTtl,
    );

    if (peripheralSupported && bluetoothOn) {
      _queueBroadcast(
        'helppoint:$msgId',
        packet.encode(),
        kHelpPointAirtime,
        priority: kPriorityHelpPoint,
      );
      appendLog(
        'Announced ${stationLabel(helpType)} help point — visible to nearby WariMesh users',
        'Sent',
      );
    } else {
      appendLog(
        'On duty as ${stationLabel(helpType)}, but this phone cannot broadcast — nobody will see it',
        'Warning',
      );
    }

    _myActiveHelpPointMsgId = msgId;
    final record = HelpPointRecord(
      msgId: msgId,
      helpType: helpType,
      senderLabel: deviceLabel,
      senderName: _myName,
      receivedAt: DateTime.now(),
      expiresAt: DateTime.now().add(packet.expiryDuration),
      hops: 0,
      mine: true,
      status: status,
    );
    try {
      await HelpPointsDb.insertIfNew(record);
      await loadHelpPoints();
    } catch (e) {
      appendLog('Could not file this help point: $e', 'Warning');
    }
  }

  /// Closes a help point this phone announced — see the note above
  /// kHelpPointPacketType for why this exists as an explicit broadcast
  /// rather than only relying on expiry.
  void _closeHelpPoint(int msgId) {
    _myActiveHelpPointMsgId = null;
    _cancelBroadcast('helppoint:$msgId');
    unawaited(() async {
      try {
        await HelpPointsDb.setStatus(
          msgId,
          kHelpStatusClosed,
          closedBy: deviceLabel,
          closedAt: DateTime.now(),
        );
        await loadHelpPoints();
      } catch (e) {
        appendLog('Could not close this help point: $e', 'Warning');
      }
    }());

    final packet = HelpPointStatusPacket(
      msgId: msgId,
      updaterMeshId: deviceLabel,
      status: kHelpStatusClosed,
    );
    if (peripheralSupported && bluetoothOn) {
      _queueBroadcast(
        'hpstatus:$msgId',
        packet.encode(),
        kHelpPointStatusAirtime,
        priority: kPriorityHelpPoint,
      );
      appendLog('Help point closed — nearby phones told', 'Sent');
    } else {
      appendLog(
        'Help point closed on this phone only — cannot broadcast',
        'Warning',
      );
    }
  }

  /// Reloads the Wari Seva Network queue from SQLite, dropping anything
  /// that expired more than a day ago first. Mirrors [loadAlerts].
  Future<void> loadHelpPoints() async {
    try {
      await HelpPointsDb.reapExpired();
      final rows = await HelpPointsDb.all();
      helpPoints
        ..clear()
        ..addAll(rows);
      notifyListeners();
    } catch (e) {
      appendLog('Could not load nearby seva: $e', 'Warning');
    }
  }

  /// "I'm going there" — a private note to self, never broadcast. See the
  /// note on [HelpPointRecord.acknowledged].
  Future<void> acknowledgeHelpPoint(HelpPointRecord point) async {
    try {
      await HelpPointsDb.setAcknowledged(point.msgId, true);
      await loadHelpPoints();
    } catch (e) {
      appendLog('Could not save that: $e', 'Warning');
    }
  }

  Future<void> bootstrap(UserProfile profile) async {
    deviceLabel = profile.meshId;
    _myGroupTag = profile.dindiTag;
    _myRole = profile.role;
    _myStation = profile.role == UserRole.volunteer
        ? profile.station
        : kStationNone;
    // Same reasoning as station above: only a warkari can lead a Dindi.
    _amDindiLead = profile.role == UserRole.warkari && profile.isDindiLead;
    _myName = profile.name.trim().split(RegExp(r'\s+')).first;

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
      await loadAlerts();
      await loadHelpPoints();
    } catch (e) {
      appendLog(
        'Local database unavailable — activity won\'t persist: $e',
        'Warning',
      );
    }

    try {
      initForegroundTask();
      FlutterForegroundTask.addTaskDataCallback(_onForegroundTaskData);
    } catch (e) {
      appendLog('Background service setup failed: $e', 'Warning');
    }

    // The background relay used to be opt-in behind a switch that only the
    // volunteer dashboard showed — so a warkari's phone had no way to turn
    // it on at all, and every phone defaulted to "stops relaying when the
    // screen locks". For an emergency app that default is backwards: the
    // relay should be running unless someone deliberately turns it off.
    try {
      await _requestBatteryExemption();
      await toggleBackgroundService(true);
    } catch (e) {
      appendLog('Could not start the background relay: $e', 'Warning');
    }

    // Started early and independently guarded: an SOS that can say WHERE
    // is worth far more than one that can't, but a refused location
    // permission must never stop the mesh from coming up.
    try {
      final ok = await location.start();
      appendLog(
        ok
            ? 'Location is on — your SOS will carry where you are'
            : 'No location access — your SOS will still send, but without a position',
        ok ? 'Sent' : 'Warning',
      );
    } catch (e) {
      appendLog('Location unavailable: $e', 'Warning');
    }

    try {
      peripheralSupported = await _blePeripheral.isSupported;
    } catch (_) {
      peripheralSupported = false;
    }
    appendLog(
      peripheralSupported
          ? 'This phone CAN advertise over BLE — real mesh sending is available'
          : 'This phone CANNOT advertise over BLE — it can receive but never send',
      peripheralSupported ? 'Sent' : 'Warning',
    );
    notifyListeners();

    // Bluetooth being off was previously only detected, never acted on —
    // the app would sit there silently "not connected" until someone
    // happened to flip it on themselves in system settings. This actually
    // asks Android to turn it on (system permission dialog), same as any
    // BLE app does on first launch.
    try {
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        await FlutterBluePlus.turnOn();
      }
    } catch (e) {
      appendLog(
        'Could not enable Bluetooth automatically — turn it on manually: $e',
        'Warning',
      );
    }

    _watchAdapterState();
    await startScanning();
    _startPresenceBroadcast();
    _startScanWatchdog();
    _startLifecycleWatch();

    // A volunteer's duty state survives an app restart (see UserProfile —
    // station is persisted), but the HELP_POINT announcement itself does
    // not: it was never on the air on this boot until now. Re-arm it so a
    // volunteer who has been at the medical tent since 5am and just had
    // their phone restart doesn't silently drop off "Nearby Seva" for
    // everyone else.
    if (_myStation != kStationNone) {
      unawaited(_announceHelpPoint(_myStation));
    }
  }

  /// Android can quietly end a scan without telling the app — a Bluetooth
  /// stack restart, a scan-throttle strike, or an OEM power manager pruning
  /// background work once the screen goes off. Nothing recovered from that
  /// except the adapter-state listener, which only fires if Bluetooth
  /// itself toggled, so a phone could sit there deaf while still showing
  /// "Connected to the mesh". This checks the real scanner state and
  /// restarts it.
  void _startScanWatchdog() {
    _scanWatchdog?.cancel();
    _scanWatchdog = Timer.periodic(const Duration(seconds: 20), (_) async {
      // The foreground service is what stops Android freezing this process
      // once the screen is off. If it dies, the app goes deaf a few seconds
      // later and nothing else would notice — so re-assert it first.
      try {
        final running = await FlutterForegroundTask.isRunningService;
        if (!running && _mayRestartService()) {
          appendLog('Background relay had stopped — restarting it', 'Warning');
          await toggleBackgroundService(true);
        }
      } catch (e) {
        appendLog('Could not check the background relay: $e', 'Warning');
      }

      if (!bluetoothOn) return;
      if (FlutterBluePlus.isScanningNow) {
        if (!scanning) {
          scanning = true;
          notifyListeners();
        }
        return;
      }
      appendLog('Scan had stopped — restarting it', 'Warning');
      await startScanning();
    });
  }

  /// Rate-limits foreground-service restarts.
  ///
  /// Starting the service respawns its Flutter engine and background
  /// isolate, which is disruptive to the BLE plugins running on the main
  /// isolate. If an OEM power manager is killing the service on sight,
  /// retrying every 20s means restarting the engine every 20s forever —
  /// which breaks scanning outright rather than fixing anything. Back off
  /// to once a minute and give up after a few tries; by then it isn't a
  /// transient failure, it's a device setting the person has to change.
  bool _mayRestartService() {
    if (_serviceRestarts >= 5) return false;
    final last = _lastServiceRestart;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 1)) {
      return false;
    }
    _lastServiceRestart = DateTime.now();
    _serviceRestarts++;
    return true;
  }

  /// Logs (to logcat, via appendLog) the moment the app leaves the
  /// foreground, which on a phone is almost always the screen going off.
  /// Without this there was no way to tell "Android froze the process" from
  /// "the packet never arrived" — the two look identical from the outside,
  /// and they need completely different fixes. Lines after a `paused` entry
  /// prove the isolate is still alive and listening.
  void _startLifecycleWatch() {
    _lifecycle?.dispose();
    location.dispose();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        appendLog('App lifecycle → ${state.name}', 'System');
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) {
          // Re-assert both as we go into the background rather than waiting
          // up to 20s for the next watchdog tick — this transition is
          // exactly when Android tears things down.
          unawaited(_reassertBackgroundReceiving());
        }
      },
    );
  }

  Future<void> _reassertBackgroundReceiving() async {
    try {
      if (!await FlutterForegroundTask.isRunningService &&
          _mayRestartService()) {
        await toggleBackgroundService(true);
      }
      if (bluetoothOn && !FlutterBluePlus.isScanningNow) {
        await startScanning();
      }
    } catch (e) {
      appendLog('Could not re-arm background receiving: $e', 'Warning');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scanSub?.cancel();
    _adapterSub?.cancel();
    _cooldownTicker?.cancel();
    _presenceTicker?.cancel();
    _advertTicker?.cancel();
    _scanWatchdog?.cancel();
    _lifecycle?.dispose();
    FlutterForegroundTask.removeTaskDataCallback(_onForegroundTaskData);
    FlutterBluePlus.stopScan();
    // Advertising no longer has a hardware timeout (see _advertiseBytes),
    // so it has to be stopped explicitly or the radio keeps broadcasting
    // the last payload after this service is gone.
    unawaited(_blePeripheral.stop().then<void>((_) {}, onError: (_) {}));
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

  /// Asks Android to exempt WariMesh from battery optimisation. Without it
  /// the OS freezes the process soon after the screen goes off and alerts
  /// stop arriving — the exact scenario this app exists for. The person can
  /// still refuse; we log it and carry on rather than blocking startup.
  Future<void> _requestBatteryExemption() async {
    try {
      if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) return;
      final granted =
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      if (!granted) {
        appendLog(
          'Battery optimisation is still on — Android may stop alerts arriving once the screen locks',
          'Warning',
        );
      }
    } catch (e) {
      appendLog('Could not check battery optimisation: $e', 'Warning');
    }
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
        notificationTitle: 'WariMesh is listening',
        notificationText: 'Relaying SOS and missing-person alerts nearby',
        callback: startCallback,
      );
      // "Already started" is success, not failure. Treating it as a failure
      // reported the relay as dead while it was actually running, and left
      // the watchdog trying to restart a healthy service every 20 seconds.
      final alreadyRunning =
          result is ServiceRequestFailure &&
          result.error is ServiceAlreadyStartedException;
      if (result is ServiceRequestFailure && !alreadyRunning) {
        appendLog(
          'Background service failed to start: ${result.error}',
          'Warning',
        );
        backgroundServiceEnabled = false;
        notifyListeners();
        return;
      }
      // Ask the OS whether the service is genuinely running rather than
      // trusting that startService() returning success means it survived.
      // This flag is the single thing that decides whether Android freezes
      // this process once the screen goes off — and with it, whether an
      // SOS can be received at all — so it must reflect reality, not
      // intent. It used to be set to `enabled` unconditionally.
      backgroundServiceEnabled = await FlutterForegroundTask.isRunningService;
      appendLog(
        backgroundServiceEnabled
            ? 'Background relay is running — this phone can receive alerts with the screen off'
            : 'Background relay did NOT start — Android will freeze this app when the screen goes off, '
                  'and alerts will not arrive. Check battery settings for WariMesh.',
        backgroundServiceEnabled ? 'Sent' : 'Warning',
      );
    } else {
      await FlutterForegroundTask.stopService();
      backgroundServiceEnabled = false;
    }
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

  /// Broadcasts "I exist, here's my name" every kPresenceInterval so nearby
  /// Dindi members show up in the Home screen's headcount. Deliberately
  /// independent of the SOS send cooldown and the demo-mode narration —
  /// PresencePacket is a completely separate wire format from the ALERT
  /// packet (see models.dart) and must keep going regardless of whether an
  /// alert was just sent.
  void _startPresenceBroadcast() {
    _presenceTicker?.cancel();
    _presenceTicker = Timer.periodic(
      kPresenceInterval,
      (_) => _broadcastPresence(),
    );
    _broadcastPresence(); // don't wait a full interval for the first beacon
  }

  void _broadcastPresence() {
    if (!peripheralSupported || !bluetoothOn)
      return; // no real radio to send on — nothing to do
    // Lowest priority: a headcount beacon may never cost an alert airtime.
    // Its airtime runs slightly past the next tick so the beacon stays in
    // the rotation continuously rather than blinking out between ticks.
    final packet = PresencePacket(
      meshId: deviceLabel,
      groupTag: _myGroupTag,
      name: _myName,
      station: _myStation,
      isDindiLead: _amDindiLead,
    );
    _queueBroadcast(
      'presence',
      packet.encode(),
      kPresenceInterval * 2,
      priority: 0,
    );
  }

  /// Registers [bytes] to be repeatedly put on the air for [airtime].
  ///
  /// Re-registering the same [key] refreshes that payload's airtime in
  /// place — hearing the same relayed alert twice extends how long we
  /// carry it rather than queueing it twice.
  /// Takes a payload off the air before its airtime is up.
  ///
  /// Every other broadcast in this service expires on a timer, because
  /// almost everything here should keep repeating until it has had a fair
  /// chance to be heard. A resolved alert is the one case that runs the
  /// other way: continuing to advertise "this child is missing" after she
  /// has been found is not merely wasted airtime, it sends people looking
  /// for someone who is already safe.
  void _cancelBroadcast(String key) {
    _broadcasts.removeWhere((b) => b.key == key);
  }

  void _queueBroadcast(
    String key,
    Uint8List bytes,
    Duration airtime, {
    int priority = kPriorityPresence,
    Duration slot = kAdvertSlot,
  }) {
    if (!peripheralSupported || !bluetoothOn) return;
    _broadcasts.removeWhere((b) => b.key == key);
    _broadcasts.add(
      _Broadcast(key, bytes, DateTime.now().add(airtime), priority, slot),
    );
    _startAdvertLoop(slot);
    unawaited(_serviceAdvertSlot()); // don't make an SOS wait up to a full slot
  }

  /// (Re)starts the rotation ticker at [slot]. The period follows whatever
  /// is currently on the air, so text fragments tick every couple of seconds
  /// while alerts keep the slower, gentler cadence.
  void _startAdvertLoop(Duration slot) {
    if (_advertTicker != null && _advertPeriod == slot) return;
    _advertTicker?.cancel();
    _advertPeriod = slot;
    _advertTicker = Timer.periodic(
      slot,
      (_) => unawaited(_serviceAdvertSlot()),
    );
  }

  /// Gives the radio to one registered broadcast for this slot, dropping
  /// anything whose airtime has run out. This is the single place that
  /// touches the advertiser, which is what stops a 15s presence beacon
  /// from calling stop() in the middle of an SOS the way it used to.
  Future<void> _serviceAdvertSlot() async {
    // The slot ticker and an immediate _queueBroadcast can land at the same
    // moment; two overlapping stop/start pairs on one radio is how you end
    // up advertising nothing at all. Whoever is second just waits for the
    // next slot.
    if (_servicingSlot) return;
    _servicingSlot = true;
    try {
      await _serviceAdvertSlotInner();
    } finally {
      _servicingSlot = false;
    }
  }

  Future<void> _serviceAdvertSlotInner() async {
    _broadcasts.removeWhere((b) => b.expiresAt.isBefore(DateTime.now()));

    if (_broadcasts.isEmpty) {
      _advertTicker?.cancel();
      _advertTicker = null;
      _advertPeriod = null;
      if (_onAir != null) {
        _onAir = null;
        try {
          await _blePeripheral.stop();
        } catch (_) {
          // Nothing on the air to stop is not a failure worth logging.
        }
      }
      return;
    }

    // Only the most important tier gets the radio; nothing below it is
    // rotated in at all. While an alert is live the presence beacon simply
    // goes quiet for a minute — a headcount is worth nothing next to an
    // SOS, and every payload we interleave costs a stop/start cycle.
    //
    // That cost is the reason for this rule rather than fairness. Restarting
    // the advertiser every slot is what wedges Android's BLE stack:
    // repeated stop/start at high TX power runs it out of advertiser
    // instances (ADVERTISE_FAILED_TOO_MANY_ADVERTISERS) and it then stops
    // transmitting altogether until Bluetooth is toggled — silently, on
    // every phone running it. An SOS on its own now claims the radio once
    // and holds it for the full 60 seconds, which is both gentler on the
    // stack and strictly better for a screen-off receiver.
    final topPriority = _broadcasts.map((b) => b.priority).reduce(max);
    final live = _broadcasts.where((b) => b.priority == topPriority).toList();
    final chosen = live[_slotCursor++ % live.length];

    // Follow the live tier's cadence: a fragmented message must not crawl at
    // the alert slot, and an alert must not churn at the text slot.
    _startAdvertLoop(chosen.slot);

    // Re-advertising a payload that's already on the air would mean a
    // stop/start gap for no gain — the whole point is continuous airtime.
    if (_onAir != null && listEquals(_onAir, chosen.bytes)) return;

    // Only claim it's on the air if the radio actually accepted it. Setting
    // this optimistically meant a failed start looked like a live broadcast,
    // so the check above would skip it every slot from then on and the alert
    // would never get retried — the exact way a wedged advertiser turns into
    // permanent silence.
    _onAir = await _advertiseBytes(chosen.bytes) ? chosen.bytes : null;
  }

  void _onScanResults(List<ScanResult> results) {
    for (final r in results) {
      final data = r.advertisementData.manufacturerData[kManufacturerId];
      if (data == null || data.isEmpty) continue;
      // Raw sighting, before any decode/dedup — the ground truth for "is
      // this phone's radio hearing the other phone at all?".
      debugPrint(
        'WariMesh[RAW] rssi=${r.rssi} type=${data[0]} len=${data.length}',
      );

      // Two completely separate wire formats share the manufacturer-data
      // slot — the byte-0 packetType says which. See the note on
      // kPresencePacketType in models.dart for why presence isn't just
      // another MeshPacket category.
      if (data[0] == kPresencePacketType) {
        final presence = PresencePacket.decode(data);
        if (presence != null) _handlePresence(presence);
        continue;
      }

      if (data[0] == kTextHeadPacketType) {
        final head = TextHeadPacket.decode(data);
        if (head != null) unawaited(_handleTextHead(head));
        continue;
      }

      if (data[0] == kTextPartPacketType) {
        final part = TextPartPacket.decode(data);
        if (part != null) unawaited(_handleTextPart(part));
        continue;
      }

      if (data[0] == kLocationPacketType) {
        final loc = LocationPacket.decode(data);
        if (loc != null) _handleLocation(loc);
        continue;
      }

      if (data[0] == kLostDetailPacketType) {
        final detail = LostPersonDetailPacket.decode(data);
        if (detail != null) _handleLostDetail(detail);
        continue;
      }

      if (data[0] == kAckPacketType) {
        final ack = AckPacket.decode(data);
        if (ack != null) unawaited(_handleAck(ack));
        continue;
      }

      if (data[0] == kResolvePacketType) {
        final res = ResolvePacket.decode(data);
        if (res != null) unawaited(_handleResolve(res));
        continue;
      }

      if (data[0] == kSpottedPacketType) {
        final spot = SpottedPacket.decode(data);
        if (spot != null) unawaited(_handleSpotted(spot));
        continue;
      }

      if (data[0] == kHelpPointPacketType) {
        final hp = HelpPointPacket.decode(data);
        if (hp != null) unawaited(_handleHelpPointPacket(hp));
        continue;
      }

      if (data[0] == kHelpPointStatusPacketType) {
        final hpStatus = HelpPointStatusPacket.decode(data);
        if (hpStatus != null) unawaited(_handleHelpPointStatus(hpStatus));
        continue;
      }

      final packet = MeshPacket.decode(data);
      if (packet == null) continue;
      unawaited(_handleReceivedPacket(packet));
    }
  }

  void _handlePresence(PresencePacket packet) {
    if (packet.meshId == deviceLabel) return; // our own beacon bouncing back
    _presence[packet.meshId] = _PresenceEntry(
      packet.groupTag,
      packet.name,
      DateTime.now(),
      packet.station,
      packet.isDindiLead,
    );
    _evictStalePresence();
    notifyListeners();
  }

  /// Drops presence entries nobody has heard from in a long while.
  ///
  /// Every reader of [_presence] already filters on kPresenceExpiry, so
  /// stale entries were never *shown* — but nothing ever removed them, and
  /// the map grew for the lifetime of the process. That was invisible until
  /// the app ran next to real Bluetooth traffic and started manufacturing a
  /// new identity out of every passing advertisement (see isPlausibleMeshId,
  /// which now rejects those at the door). Both halves are worth fixing: an
  /// app meant to run for twelve hours of walking should not accumulate
  /// state it can never use again.
  ///
  /// The cutoff is deliberately far longer than kPresenceExpiry. Someone who
  /// drops out of range for a few minutes and comes back should still be a
  /// familiar name rather than a stranger, and [nameFor] is what turns a
  /// Mesh ID on an incoming ACK into a person — that lookup stays useful
  /// long after somebody has stopped being "nearby".
  void _evictStalePresence() {
    final cutoff = DateTime.now().subtract(kPresenceMemory);
    _presence.removeWhere((_, entry) => entry.lastHeard.isBefore(cutoff));
  }

  // ---------------------------------------------------------------------
  // The alert queue — receiving, claiming and closing.
  //
  // Everything above this point is about getting an alarm to travel. This
  // section is about what happens next: somebody has to pick it up, and
  // somebody has to be able to say it's over. See AlertRecord in models.dart
  // for why these are stored rather than merely notified.
  // ---------------------------------------------------------------------

  /// Reads the queue back from SQLite. Called at bootstrap, and again after
  /// anything that changes a row, so the in-memory list and the database
  /// can't drift apart.
  Future<void> loadAlerts() async {
    try {
      final rows = await AlertsDb.all();
      alerts
        ..clear()
        ..addAll(rows);
      _stampDistances();
      notifyListeners();
    } catch (e) {
      appendLog('Could not load the alert queue: $e', 'Warning');
    }
  }

  /// Recomputes how far away each located alert is, from wherever this
  /// phone is now. Cheap, and correct only at the moment it runs — which is
  /// why it runs on every queue load rather than being stored.
  void _stampDistances() {
    final me = location.lastKnown;
    if (me == null) return;
    for (final a in alerts) {
      final lat = a.latitude, lon = a.longitude;
      if (lat == null || lon == null) continue;
      a.distanceMetres = LocationService.distanceBetween(
        me.latitude,
        me.longitude,
        lat,
        lon,
      );
      a.bearingDegrees = LocationService.bearingBetween(
        me.latitude,
        me.longitude,
        lat,
        lon,
      );
    }
  }

  AlertRecord? _findAlert(int msgId) {
    for (final a in alerts) {
      if (a.msgId == msgId) return a;
    }
    return null;
  }

  /// Files an alert into the queue. [mine] marks an alert this phone sent —
  /// stored too, because the sender needs somewhere for an incoming ACK to
  /// land: without a row of their own, "someone is responding" has nothing
  /// to attach to.
  Future<void> _recordAlert(MeshPacket packet, {required bool mine}) async {
    final detail = _lostDetails[packet.msgId];
    final loc = _alertLocations[packet.msgId];
    final record = AlertRecord(
      msgId: packet.msgId,
      category: packet.category,
      senderLabel: packet.senderLabel,
      senderName: mine ? null : nameFor(packet.senderLabel),
      groupTag: packet.groupTag,
      receivedAt: DateTime.now(),
      hops: mine ? 0 : kDefaultTtl - packet.ttl,
      mine: mine,
      reason: packet.reason,
      lostName: detail?.name,
      lostAge: detail?.age,
      latitude: loc?.latitude,
      longitude: loc?.longitude,
    );
    try {
      await AlertsDb.insertIfNew(record);
      await loadAlerts();
    } catch (e) {
      appendLog('Could not file this alert into the queue: $e', 'Warning');
    }
  }

  /// Claims an alert: "I am responding to this." Puts an ACK on the air so
  /// the person who sent it learns help is coming, and so other volunteers
  /// see it as taken rather than converging on it too.
  Future<void> claimAlert(AlertRecord alert) async {
    final now = DateTime.now();
    try {
      await AlertsDb.setClaim(alert.msgId, deviceLabel, now);
      await loadAlerts();
    } catch (e) {
      appendLog('Could not record your response: $e', 'Warning');
      return;
    }

    final ack = AckPacket(msgId: alert.msgId, responderMeshId: deviceLabel);
    if (peripheralSupported && bluetoothOn) {
      _queueBroadcast(
        'ack:${alert.msgId}',
        ack.encode(),
        kResponseAirtime,
        priority: kPriorityAlert,
      );
      appendLog(
        'Responding to #${alert.msgId} — telling the sender help is coming',
        'Sent',
      );
    } else {
      // The claim still stands locally. It has to: a volunteer on a phone
      // that cannot advertise is still a volunteer walking towards someone,
      // and their own queue must reflect that even if nobody else hears it.
      appendLog(
        'Responding to #${alert.msgId} — but this phone cannot broadcast, '
            'so the sender will not be told',
        'Warning',
      );
    }
  }

  /// Closes an alert and broadcasts that it's closed, which is what stops
  /// the search — and, for a missing child, is the whole point of the app.
  Future<void> resolveAlert(
    AlertRecord alert, {
    int reason = kResolveFound,
  }) async {
    final now = DateTime.now();
    try {
      await AlertsDb.setResolved(alert.msgId, deviceLabel, reason, now);
      await loadAlerts();
    } catch (e) {
      appendLog('Could not close this alert: $e', 'Warning');
      return;
    }

    // Stop spending airtime on an alert that is over — this is the other
    // half of why RESOLVE exists. Both the alert and everything attached to
    // it come off the air here.
    _cancelBroadcast('alert:${alert.msgId}');
    _cancelBroadcast('detail:${alert.msgId}');
    _cancelBroadcast('loc:${alert.msgId}');

    final packet = ResolvePacket(
      msgId: alert.msgId,
      resolverMeshId: deviceLabel,
      reason: reason,
    );
    if (peripheralSupported && bluetoothOn) {
      _queueBroadcast(
        'res:${alert.msgId}',
        packet.encode(),
        kResponseAirtime,
        priority: kPriorityAlert,
      );
      appendLog(
        '${resolveReasonLabel(reason)} — #${alert.msgId} closed and nearby phones told',
        'Sent',
      );
    } else {
      appendLog(
        '${resolveReasonLabel(reason)} — #${alert.msgId} closed on this phone only',
        'Warning',
      );
    }
  }

  /// Closes the alert that was broadcast for a missing-person report, by
  /// its msgId. This is what "Mark as found" reaches for: the report lives
  /// in its own table with its own screen, but the thing still circulating
  /// over the air is the alert, and only a RESOLVE stops it.
  ///
  /// Returns false when there is no alert to close — the report was never
  /// broadcast, so there is nothing on the air and nothing to say.
  Future<bool> resolveByMsgId(int msgId, {int reason = kResolveFound}) async {
    final alert = _findAlert(msgId);
    if (alert == null) return false;
    if (alert.isResolved) return true;
    await resolveAlert(alert, reason: reason);
    return true;
  }

  /// Puts a closed alert back in the queue. A RESOLVE is an unsigned claim
  /// from an unauthenticated radio (see kResolvePacketType); a volunteer who
  /// knows better must be able to overrule it.
  Future<void> reopenAlert(AlertRecord alert) async {
    try {
      await AlertsDb.reopen(alert.msgId);
      await loadAlerts();
      appendLog('Reopened #${alert.msgId} — back in the queue', 'Received');
    } catch (e) {
      appendLog('Could not reopen this alert: $e', 'Warning');
    }
  }

  /// "I have just seen this person, here." Reports a sighting of a missing
  /// person and puts it on the air so the people searching — above all the
  /// reporter and their Dindi Lead — learn where the trail is now.
  ///
  /// Deliberately does NOT claim the alert (see the note on
  /// kSpottedPacketType): the person reporting a sighting is usually walking
  /// on, and the case must stay open for someone who can actually go.
  Future<void> reportSpotted(AlertRecord alert) async {
    final now = DateTime.now();
    // The cached fix, never a blocking wait for GPS — same rule as sending
    // an alert (see _broadcastLocationFor). A sighting reported thirty
    // seconds late because the radio was warming up is a sighting of where
    // they no longer are.
    final me = location.lastKnown;

    try {
      await AlertsDb.setSpotted(
        alert.msgId,
        deviceLabel,
        now,
        latitude: me?.latitude,
        longitude: me?.longitude,
      );
      await loadAlerts();
    } catch (e) {
      appendLog('Could not record the sighting: $e', 'Warning');
      return;
    }

    final packet = SpottedPacket(
      msgId: alert.msgId,
      spotterMeshId: deviceLabel,
      latitude: me?.latitude,
      longitude: me?.longitude,
    );
    if (peripheralSupported && bluetoothOn) {
      _queueBroadcast(
        'spot:${alert.msgId}',
        packet.encode(),
        kResponseAirtime,
        priority: kPriorityAlert,
      );
      appendLog(
        me == null
            ? 'Sighting reported for #${alert.msgId} — no position on this phone to send with it'
            : 'Sighting reported for #${alert.msgId} — position sent with it',
        'Sent',
      );
    } else {
      appendLog(
        'Sighting recorded for #${alert.msgId} on this phone only — cannot broadcast',
        'Warning',
      );
    }
  }

  Future<void> _handleSpotted(SpottedPacket spot) async {
    if (spot.spotterMeshId == deviceLabel) return; // our own, echoed back

    final existing = _findAlert(spot.msgId);
    // Like an ACK, a sighting for a case we have never heard of has nothing
    // to attach to — but it is still relayed below, because the phone that
    // filed the report may be a hop further out.
    if (existing != null && !existing.isResolved) {
      try {
        await AlertsDb.setSpotted(
          spot.msgId,
          spot.spotterMeshId,
          DateTime.now(),
          latitude: spot.latitude,
          longitude: spot.longitude,
        );
        await loadAlerts();
      } catch (e) {
        appendLog(
          'Could not record the sighting of #${spot.msgId}: $e',
          'Warning',
        );
      }

      final who = nameFor(spot.spotterMeshId) ?? spot.spotterMeshId;
      appendLog(
        spot.hasLocation
            ? '$who reported seeing the missing person from #${spot.msgId}, with a position'
            : '$who reported seeing the missing person from #${spot.msgId}',
        'Received',
      );

      if (existing.mine) {
        // The person who filed the report needs to be told the moment
        // somebody lays eyes on who they are looking for — they have very
        // likely put the phone in a pocket and started walking.
        try {
          await NotificationService.showPersonSpotted(
            who,
            lostName: existing.lostName,
          );
        } catch (_) {
          // A missing notification must not lose the sighting itself.
        }
      }
    }

    _relayResponse('spot:${spot.msgId}', spot.encode());
  }

  Future<void> _handleAck(AckPacket ack) async {
    if (ack.responderMeshId == deviceLabel) return; // our own, echoed back

    final existing = _findAlert(ack.msgId);
    // An ACK for an alert we've never seen is not noise worth acting on: we
    // have nothing to attach it to and no way to display it. It is still
    // relayed below, because the phone that DOES need it may be a hop away.
    if (existing != null && existing.claimedBy == null) {
      try {
        await AlertsDb.setClaim(ack.msgId, ack.responderMeshId, DateTime.now());
        await loadAlerts();
      } catch (e) {
        appendLog(
          'Could not record the response to #${ack.msgId}: $e',
          'Warning',
        );
      }

      final who = nameFor(ack.responderMeshId) ?? ack.responderMeshId;
      if (existing.mine) {
        // The single most reassuring thing this app can say. It gets a real
        // notification, because the person who pressed SOS has very likely
        // put their phone down or is holding it at their side.
        appendLog('$who is responding to your alert', 'Received');
        try {
          await NotificationService.showResponderComing(who);
        } catch (_) {
          // A missing notification must not lose the claim itself.
        }
      } else {
        appendLog('$who has taken #${ack.msgId}', 'Received');
      }
    }

    _relayResponse('ack:${ack.msgId}', ack.encode());
  }

  Future<void> _handleResolve(ResolvePacket res) async {
    if (res.resolverMeshId == deviceLabel) return; // our own, echoed back

    final existing = _findAlert(res.msgId);
    if (existing != null && !existing.isResolved) {
      try {
        await AlertsDb.setResolved(
          res.msgId,
          res.resolverMeshId,
          res.reason,
          DateTime.now(),
        );
        await loadAlerts();
      } catch (e) {
        appendLog('Could not close #${res.msgId}: $e', 'Warning');
      }

      // Stop carrying an alert whose search is over. This is what keeps a
      // found child's beacon from circulating for the rest of the day.
      _cancelBroadcast('alert:${res.msgId}');
      _cancelBroadcast('detail:${res.msgId}');
      _cancelBroadcast('loc:${res.msgId}');

      final who = nameFor(res.resolverMeshId) ?? res.resolverMeshId;
      appendLog(
        '${resolveReasonLabel(res.reason)}: #${res.msgId} closed by $who',
        'Received',
      );

      // Pull the alert off the in-app overlay too — leaving a full-screen
      // "someone needs help" over a resolved alert is actively misleading.
      pendingAlerts.removeWhere((a) => a.packet.msgId == res.msgId);
      notifyListeners();
    }

    _relayResponse('res:${res.msgId}', res.encode());
  }

  /// Receives a HELP_POINT announcement — files it, and relays it exactly
  /// like an ALERT (TTL/dedup/jitter), since it needs to reach a phone that
  /// may be several hops from the volunteer who announced it. See the note
  /// on kHelpPointPacketType for why this can't just be a PresencePacket.
  Future<void> _handleHelpPointPacket(HelpPointPacket packet) async {
    if (packet.senderLabel == deviceLabel) return; // our own, echoed back

    final alreadySeen = await SeenMessagesDb.hasSeen(packet.msgId);
    if (alreadySeen) return; // dedup — also the loop-prevention mechanism
    await SeenMessagesDb.markSeenRaw(
      packet.msgId,
      category: kHelpPointPacketType,
      senderLabel: packet.senderLabel,
      ttl: packet.ttl,
    );

    appendLog(
      'Received ${stationLabel(packet.helpType)} help point from ${packet.senderLabel} (TTL ${packet.ttl})',
      'Received',
    );

    try {
      await HelpPointsDb.insertIfNew(
        HelpPointRecord(
          msgId: packet.msgId,
          helpType: packet.helpType,
          senderLabel: packet.senderLabel,
          senderName: nameFor(packet.senderLabel),
          receivedAt: DateTime.now(),
          expiresAt: DateTime.now().add(packet.expiryDuration),
          hops: kDefaultTtl - packet.ttl,
          mine: false,
          status: packet.status,
        ),
      );
      await loadHelpPoints();
    } catch (e) {
      appendLog('Could not file this help point: $e', 'Warning');
    }

    if (packet.ttl > 0) {
      final jitterMs =
          300 + Random().nextInt(501); // 300–800ms, same as alert relay
      await Future.delayed(Duration(milliseconds: jitterMs));
      final relayed = packet.relayed();
      _queueBroadcast(
        'helppoint:${relayed.msgId}',
        relayed.encode(),
        kHelpPointRelayAirtime,
        priority: kPriorityHelpPoint,
      );
      appendLog(
        'Relayed help point via $deviceLabel (TTL now ${relayed.ttl})',
        'Relayed',
      );
    } else {
      appendLog(
        'Final hop reached $deviceLabel — help point not relayed further',
        'Final hop',
      );
    }
  }

  /// Receives a close/status update for a help point — the HELP_POINT
  /// counterpart to [_handleResolve]. No TTL (see kHelpPointStatusPacketType),
  /// so relay-once-per-phone via [_relayedResponses] bounds the flood.
  Future<void> _handleHelpPointStatus(HelpPointStatusPacket packet) async {
    if (packet.updaterMeshId == deviceLabel) return; // our own, echoed back

    try {
      await HelpPointsDb.setStatus(
        packet.msgId,
        packet.status,
        closedBy: packet.updaterMeshId,
        closedAt: DateTime.now(),
      );
      await loadHelpPoints();
      appendLog(
        '${helpStatusLabel(packet.status)}: help point #${packet.msgId} updated by ${packet.updaterMeshId}',
        'Received',
      );
    } catch (e) {
      appendLog('Could not update this help point: $e', 'Warning');
    }

    _relayResponse('hpstatus:${packet.msgId}', packet.encode());
  }

  /// Passes a response packet on once, for the same reasons an alert is
  /// relayed: the sender may be one hop further away than the responder.
  ///
  /// Neither packet carries a TTL — there is no room, and none is needed:
  /// [_relayedResponses] makes each phone re-air a given response exactly
  /// once ever, which bounds the flood without a hop counter. The same
  /// trick the text fragments use (see _relayFragment).
  void _relayResponse(String key, Uint8List bytes) {
    if (!_relayedResponses.add(key)) return;
    if (!peripheralSupported || !bluetoothOn) return;
    _queueBroadcast(key, bytes, kResponseAirtime, priority: kPriorityAlert);
  }

  void _handleLocation(LocationPacket loc) {
    _alertLocations[loc.msgId] = loc;

    if (_findAlert(loc.msgId) != null) {
      unawaited(() async {
        try {
          await AlertsDb.setLocation(loc.msgId, loc.latitude, loc.longitude);
          await loadAlerts();
        } catch (_) {
          // Same as the detail packet: losing this costs a distance on the
          // queue card, never the alert itself.
        }
      }());
    }
    appendLog('Position received for alert #${loc.msgId}', 'Received');

    // The alert and its position travel as separate packets that take turns
    // on the air, so the alert almost always lands first — meaning the
    // notification has already been posted by the time we learn where the
    // sender is. Filling in the open dialog is not enough: the lock screen
    // is where most people will actually see this, and a notification that
    // says "needs help" when we know it's 240 m north-east is withholding
    // the one fact that makes it actionable. So the notification is
    // re-posted with the distance as soon as we have it.
    var changed = false;
    for (final alert in pendingAlerts) {
      if (alert.packet.msgId == loc.msgId && !alert.hasLocation) {
        _applyLocation(alert, loc);
        changed = true;
        unawaited(_repostWithLocation(alert));
      }
    }
    if (changed) notifyListeners();
  }

  /// Re-posts an already-shown notification, now carrying the distance.
  /// Same notification id, so Android replaces the existing one rather than
  /// stacking a second alert for the same event.
  Future<void> _repostWithLocation(IncomingAlert alert) async {
    try {
      await NotificationService.showAlertReceived(
        alert.packet,
        senderName: alert.senderName,
        lostName: alert.lostName,
        lostAge: alert.lostAge,
        distanceLabel: alert.distanceLabel,
        directionLabel: alert.directionLabel,
        isUpdate: true,
      );
      appendLog(
        alert.distanceLabel == null
            ? 'Position added to the alert (no distance — this phone has no fix of its own)'
            : 'Alert updated: ${alert.distanceLabel}, to your ${alert.directionLabel}',
        'Received',
      );
    } catch (e) {
      appendLog('Could not update the alert with its position: $e', 'Warning');
    }
  }

  /// Stamps an alert with the sender's position, plus how far and which way
  /// that is from here. Distance stays null when this phone has no fix of
  /// its own — we still show the raw coordinates in that case.
  void _applyLocation(IncomingAlert alert, LocationPacket loc) {
    alert.senderLatitude = loc.latitude;
    alert.senderLongitude = loc.longitude;
    final me = location.lastKnown;
    if (me == null) return;
    alert.distanceMetres = LocationService.distanceBetween(
      me.latitude,
      me.longitude,
      loc.latitude,
      loc.longitude,
    );
    alert.bearingDegrees = LocationService.bearingBetween(
      me.latitude,
      me.longitude,
      loc.latitude,
      loc.longitude,
    );
  }

  // ---------------------------------------------------------------------
  // Text messages — Dindi chat and volunteer advisories.
  // ---------------------------------------------------------------------

  /// Sends [body] as a Dindi chat message, or as an advisory to everyone in
  /// range when [announcement] is true. Returns false if there was nothing
  /// to send or the radio can't transmit.
  ///
  /// Unlike an alert there is no cooldown: rate-limiting a conversation
  /// would make it unusable, and text already yields the radio to any alert.
  /// [airtime] is how long the message keeps repeating on the radio. Chat
  /// takes the default 40s — long enough for a phone in a pocket to catch
  /// it. An advisory can ask for much longer, and should: a route change
  /// matters to the people who will walk past this camp in the next ten
  /// minutes, not only to whoever happened to be in range at the instant a
  /// volunteer hit send. Extending airtime is the right way to do that —
  /// one message, one msgId, re-aired — rather than sending the same text
  /// repeatedly, which would dedup as several different messages on every
  /// receiving phone and fill their chat with copies.
  Future<bool> sendText(
    String body, {
    bool announcement = false,
    Duration? airtime,
  }) async {
    final text = body.trim();
    if (text.isEmpty) return false;

    final msgId = Random().nextInt(0xFFFFFFFF);
    final kind = announcement ? kTextKindAnnouncement : kTextKindChat;
    final fragments = fragmentText(
      msgId: msgId,
      ttl: kDefaultTtl,
      kind: kind,
      groupTag: _myGroupTag,
      senderLabel: deviceLabel,
      body: text,
    );

    final message = MeshTextMessage(
      msgId: msgId,
      kind: kind,
      groupTag: _myGroupTag,
      senderLabel: deviceLabel,
      senderName: _myName,
      body: asciiSafe(text).trim(),
      createdAt: DateTime.now(),
      outgoing: true,
    );
    await _storeMessage(message, countUnread: false);

    if (!peripheralSupported || !bluetoothOn) {
      appendLog(
        'Message saved but not broadcast — this phone cannot transmit right now',
        'Warning',
      );
      return false;
    }

    _airText(fragments.head, fragments.parts, airtime ?? kTextAirtime);
    appendLog(
      announcement
          ? 'Advisory sent to everyone in range for '
                '${(airtime ?? kTextAirtime).inMinutes < 1 ? '${(airtime ?? kTextAirtime).inSeconds}s' : '${(airtime ?? kTextAirtime).inMinutes} min'} '
                '(${fragments.parts.length + 1} fragments)'
          : 'Message sent to your Dindi (${fragments.parts.length + 1} fragments)',
      'Sent',
    );
    return true;
  }

  /// Puts a whole message on the air. Every fragment shares the text tier,
  /// so they rotate among themselves and repeat for the full airtime —
  /// a receiver that misses fragment 3 on the first pass catches it later.
  void _airText(
    TextHeadPacket head,
    List<TextPartPacket> parts,
    Duration airtime,
  ) {
    _queueBroadcast(
      'txt:${head.msgId}:0',
      head.encode(),
      airtime,
      priority: kPriorityText,
      slot: kTextSlot,
    );
    for (final part in parts) {
      _queueBroadcast(
        'txt:${head.msgId}:${part.index}',
        part.encode(),
        airtime,
        priority: kPriorityText,
        slot: kTextSlot,
      );
    }
  }

  Future<void> _handleTextHead(TextHeadPacket head) async {
    if (head.senderLabel == deviceLabel) return; // our own message echoing back

    // Relay regardless of whether we've already read it — a neighbour
    // further out may still be waiting for this fragment.
    _relayFragment('${head.msgId}:0', head.ttl, () => head.relayed().encode());
    if (_completedTextIds.contains(head.msgId)) return;

    final assembly = _assembling.putIfAbsent(
      head.msgId,
      () => _TextAssembly(head.msgId),
    );
    assembly.head = head;
    assembly.total = head.fragTotal;
    assembly.chunks[0] = head.chunk;
    await _completeIfWhole(assembly);
  }

  Future<void> _handleTextPart(TextPartPacket part) async {
    // A part can arrive before its head — we don't know the sender or the
    // fragment count yet, so hold it until the head turns up.
    _relayFragment(
      '${part.msgId}:${part.index}',
      part.ttl,
      () => part.relayed().encode(),
    );
    if (_completedTextIds.contains(part.msgId)) return;

    final assembly = _assembling.putIfAbsent(
      part.msgId,
      () => _TextAssembly(part.msgId),
    );
    assembly.chunks[part.index] = part.chunk;
    await _completeIfWhole(assembly);
  }

  /// Re-airs one fragment if it still has hops left and we have not already
  /// passed this exact fragment on.
  void _relayFragment(String key, int ttl, Uint8List Function() encode) {
    if (ttl <= 0) return;
    if (!_relayedFragments.add(key)) return;
    // Bounded so a long conversation cannot grow this without limit.
    if (_relayedFragments.length > 500) {
      _relayedFragments.remove(_relayedFragments.first);
    }
    _queueBroadcast(
      'txt:$key',
      encode(),
      kTextAirtime,
      priority: kPriorityText,
      slot: kTextSlot,
    );
  }

  /// Joins the fragments once they are all present and files the result.
  Future<void> _completeIfWhole(_TextAssembly assembly) async {
    _assembling.removeWhere(
      (_, a) =>
          DateTime.now().difference(a.startedAt) > kTextAssemblyExpiry &&
          a != assembly,
    );

    final head = assembly.head;
    final total = assembly.total;
    if (head == null || total == null) return; // head has not arrived yet
    for (var i = 0; i < total; i++) {
      if (!assembly.chunks.containsKey(i)) return; // still missing a fragment
    }

    final body = [
      for (var i = 0; i < total; i++) assembly.chunks[i]!,
    ].join().trimRight();
    _assembling.remove(assembly.msgId);

    // Claim it before filing so a fragment landing mid-await can't produce
    // a second copy.
    if (!_completedTextIds.add(assembly.msgId)) return;
    if (_completedTextIds.length > 500) {
      _completedTextIds.remove(_completedTextIds.first);
    }

    await _storeMessage(
      MeshTextMessage(
        msgId: assembly.msgId,
        kind: head.kind,
        groupTag: head.groupTag,
        senderLabel: head.senderLabel,
        senderName: nameFor(head.senderLabel),
        body: body,
        createdAt: DateTime.now(),
        outgoing: false,
      ),
      countUnread: true,
    );
  }

  /// Files a message, in SQLite and in memory. Silently does nothing if the
  /// msgId is already known — the same message reaches us repeatedly as
  /// neighbours relay it, and a conversation must not fill with duplicates.
  Future<void> _storeMessage(
    MeshTextMessage message, {
    required bool countUnread,
  }) async {
    if (messages.any((m) => m.msgId == message.msgId)) return;

    var isNew = true;
    try {
      isNew = await MessagesDb.insertIfNew(message);
    } catch (e) {
      // No database — keep it for this session at least, rather than
      // dropping what someone just said.
      isNew = !messages.any((m) => m.msgId == message.msgId);
      appendLog('Message not saved to this phone: $e', 'Warning');
    }
    if (!isNew) return;

    // Shown only if it is for our Dindi, or it is an advisory for everyone.
    // Note this decides DISPLAY, never relay: every phone passes on every
    // fragment, exactly as it does for alerts, so reach never depends on
    // group membership.
    final forUs = message.groupTag == _myGroupTag || message.isAnnouncement;
    if (!forUs) return;

    messages.add(message);
    if (countUnread && !message.outgoing) unreadMessages++;

    if (message.isAnnouncement && !message.outgoing) {
      // An advisory is the reason a volunteer sent it — route changes and
      // closed water points are no use sitting unread in a tab.
      try {
        await NotificationService.showAdvisory(message);
      } catch (e) {
        appendLog('Could not show the advisory notification: $e', 'Warning');
      }
    }

    appendLog(
      message.outgoing
          ? 'You: ${message.body}'
          : '${message.displayName}: ${message.body}',
      message.isAnnouncement ? 'Advisory' : 'Received',
    );
    notifyListeners();
  }

  /// Loads this Dindi's conversation from SQLite at startup.
  Future<void> loadMessages() async {
    try {
      final stored = await MessagesDb.forGroup(_myGroupTag);
      messages
        ..clear()
        ..addAll(stored);
      notifyListeners();
    } catch (e) {
      appendLog('Could not load earlier messages: $e', 'Warning');
    }
  }

  void _handleLostDetail(LostPersonDetailPacket detail) {
    _lostDetails[detail.msgId] = detail;

    // The queue row may already exist (the alert landed first) — give it the
    // name, or it stays a "lost person" card with nobody to look for.
    if (_findAlert(detail.msgId) != null) {
      unawaited(() async {
        try {
          await AlertsDb.setLostDetail(detail.msgId, detail.name, detail.age);
          await loadAlerts();
        } catch (_) {
          // The in-memory path below still works; a failed write here only
          // costs the name after a restart.
        }
      }());
    }
    // The detail can arrive after its alert is already on screen — fill it
    // in so the open alert gains the name instead of staying generic.
    var changed = false;
    for (final alert in pendingAlerts) {
      if (alert.packet.msgId == detail.msgId && alert.lostName == null) {
        alert.lostName = detail.name;
        alert.lostAge = detail.age;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> _handleReceivedPacket(MeshPacket packet) async {
    if (packet.senderLabel == deviceLabel)
      return; // ignore our own advertisement bouncing back

    final alreadySeen = await SeenMessagesDb.hasSeen(packet.msgId);
    if (alreadySeen) return; // dedup — also the loop-prevention mechanism

    await SeenMessagesDb.markSeen(packet);
    await refreshSeenCount();

    // Notification tiering: every phone relays every packet regardless
    // (reach must never depend on group membership), but a loud, buzzing
    // notification is only worth interrupting someone for if it's their
    // own Dindi's business or they're a volunteer — the responder tier for
    // everyone else's alerts too. Anyone outside both still gets the quiet
    // activity-log line below, just not the heads-up notification.
    final isMyDindi = packet.groupTag == _myGroupTag;
    final isResponder = _myRole == UserRole.volunteer;
    // An SOS is never tiered down. Tiering exists so a warkari isn't
    // interrupted by every Lost Person report in a crowd of thousands —
    // but a warkari who hasn't joined a Dindi yet carries the tag '--',
    // which matches nobody, so under the old rule their phone stayed
    // completely silent for a real SOS from someone standing next to
    // them. Whoever is nearest is who can help; group membership must not
    // decide whether they're told.
    final prominent =
        packet.category == kCategorySos || isMyDindi || isResponder;

    final what = sosReasonIsSpecific(packet.reason)
        ? '${sosReasonLabel(packet.reason)} SOS'
        : categoryLabel(packet.category);
    appendLog(
      'Received $what from ${packet.senderLabel}'
          '${isMyDindi ? ' (your Dindi)' : ''} (TTL ${packet.ttl})',
      'Received',
    );
    if (prominent) {
      // Two channels on purpose: the system notification is what reaches
      // someone whose phone is in their pocket, and the in-app alert is
      // what they see when they pull it out — it stays until acknowledged.
      final detail = _lostDetails[packet.msgId];
      final alert = IncomingAlert(
        packet: packet,
        senderName: nameFor(packet.senderLabel),
        receivedAt: DateTime.now(),
        lostName: detail?.name,
        lostAge: detail?.age,
      );
      final loc = _alertLocations[packet.msgId];
      if (loc != null) _applyLocation(alert, loc);

      await NotificationService.showAlertReceived(
        packet,
        senderName: alert.senderName,
        lostName: detail?.name,
        lostAge: detail?.age,
        distanceLabel: alert.distanceLabel,
        directionLabel: alert.directionLabel,
      );
      pendingAlerts.add(alert);
      notifyListeners();
    }

    // Filed for every received alert, prominent or not: the notification
    // tier decides whether to interrupt someone, and must not decide whether
    // the alert exists at all — a volunteer scrolling their queue should
    // still find the quiet ones.
    //
    // Deliberately AFTER the notification and deliberately not awaited. This
    // writes a row and then re-reads the whole queue, and nothing about
    // filing paperwork should sit between an incoming SOS and the buzz in
    // someone's pocket.
    unawaited(_recordAlert(packet, mine: false));

    if (packet.ttl > 0) {
      // Random jitter before relaying so nearby phones that all heard the
      // same packet don't all re-advertise in the same instant.
      final jitterMs = 300 + Random().nextInt(501); // 300–800ms
      await Future.delayed(Duration(milliseconds: jitterMs));
      final relayed = packet.relayed();
      // Carried for kRelayAirtime rather than re-advertised once: the
      // phone we're relaying to may well have its screen off, and a
      // single burst is exactly what it would miss. This is also what
      // lets someone who walks into range ten seconds late still hear it.
      _queueBroadcast(
        'alert:${relayed.msgId}',
        relayed.encode(),
        kRelayAirtime,
        priority: 2,
      );
      final loc = _alertLocations[relayed.msgId];
      if (loc != null) {
        // The position has to travel as far as the alert does, or a phone
        // two hops out learns someone needs help but not where.
        _queueBroadcast(
          'loc:${relayed.msgId}',
          loc.encode(),
          kRelayAirtime,
          priority: 2,
        );
      }
      final detail = _lostDetails[relayed.msgId];
      if (detail != null) {
        // Same priority as the alert, not lower: under the top-tier rule
        // in _serviceAdvertSlotInner a lower priority would never air at
        // all, and an alert without its name is barely actionable.
        _queueBroadcast(
          'detail:${relayed.msgId}',
          detail.encode(),
          kRelayAirtime,
          priority: 2,
        );
      }
      appendLog('Relayed via $deviceLabel (TTL now ${relayed.ttl})', 'Relayed');
    } else {
      appendLog(
        'Final hop reached $deviceLabel — not relayed further',
        'Final hop',
      );
    }
  }

  /// Puts one payload on the air. Only [_serviceAdvertSlot] calls this —
  /// go through [_queueBroadcast] instead, so airtime is scheduled rather
  /// than grabbed.
  Future<bool> _advertiseBytes(List<int> bytes) async {
    try {
      if (await _blePeripheral.isAdvertising) {
        await _blePeripheral.stop();
      }
      final data = AdvertiseData(
        manufacturerId: kManufacturerId,
        manufacturerData: Uint8List.fromList(bytes),
      );
      final settings = AdvertiseSettings(
        advertiseMode: AdvertiseMode.advertiseModeLowLatency,
        txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
        connectable: false,
        // No hardware timeout: how long a payload stays on the air is now
        // decided by its airtime in [_broadcasts], and [_serviceAdvertSlot]
        // stops the radio when nothing is left. A 3s hardware timeout used
        // to end an alert permanently after one burst — see the airtime
        // note above kAdvertSlot for why that lost screen-off receivers.
        timeout: 0,
      );
      await _blePeripheral.start(
        advertiseData: data,
        advertiseSettings: settings,
      );
      return true;
    } catch (e) {
      appendLog('Advertise failed: $e', 'Warning');
      return false;
    }
  }

  /// Sends an alert. Returns the packet that was sent, or null if blocked
  /// (cooldown). Real BLE advertising is attempted whenever the device
  /// supports it; Demo Mode additionally narrates a simulated relay so the
  /// activity feed stays convincing even solo on one phone.
  ///
  /// For a Lost Person alert, pass [lostName]/[lostAge] — they're
  /// broadcast as a separate detail packet so receiving phones can show
  /// who to look for rather than a nameless "someone is missing".
  Future<MeshPacket?> sendAlert(
    int category, {
    String? lostName,
    String? lostAge,
    int reason = kSosReasonUnspecified,
  }) async {
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
      groupTag: _myGroupTag,
      // Only an SOS carries a reason. A Lost Person alert's "what" is the
      // person, not a reason code — see MeshPacket.reason.
      reason: category == kCategorySos ? reason : kSosReasonUnspecified,
    );
    // Mark our own send as seen so a stray echo of our own advertisement
    // isn't treated as a fresh incoming alert.
    await SeenMessagesDb.markSeen(packet);
    await refreshSeenCount();

    if (peripheralSupported && bluetoothOn) {
      final detail = (lostName == null || lostName.isEmpty)
          ? null
          : LostPersonDetailPacket(
              msgId: packet.msgId,
              name: lostName,
              age: lostAge ?? '',
            );
      _broadcastAlert(packet, detail);
    } else if (!peripheralSupported) {
      appendLog(
        'This device cannot advertise over real BLE — it can receive alerts but never send them',
        'Warning',
      );
    } else if (!bluetoothOn) {
      appendLog(
        'Bluetooth is off — turn it on to broadcast over real BLE',
        'Warning',
      );
    }

    final what = sosReasonIsSpecific(packet.reason)
        ? '${sosReasonLabel(packet.reason)} SOS'
        : categoryLabel(category);
    appendLog('Sent $what (msg #${packet.msgId}, TTL ${packet.ttl})', 'Sent');

    // Our own alerts go in the queue too — that row is where an incoming
    // ACK lands, and it's what lets this phone's own screen change from
    // "alert sent" to "someone is responding".
    if (lostName != null && lostName.isNotEmpty) {
      _lostDetails[packet.msgId] = LostPersonDetailPacket(
        msgId: packet.msgId,
        name: lostName,
        age: lostAge ?? '',
      );
    }
    await _recordAlert(packet, mine: true);

    return packet;
  }

  /// Registers an alert (and its detail packet, when there is one) for a
  /// full minute of airtime. There's still only one BLE advertiser, so the
  /// two payloads take turns — but now via the shared rotation in
  /// [_serviceAdvertSlot], which is what keeps the 15s presence beacon from
  /// cutting the alert short and keeps the alert repeating long enough for
  /// a phone whose screen is off to actually catch it.
  void _broadcastAlert(MeshPacket packet, LostPersonDetailPacket? detail) {
    _queueBroadcast(
      'alert:${packet.msgId}',
      packet.encode(),
      kAlertAirtime,
      priority: 2,
    );
    if (detail != null) {
      _queueBroadcast(
        'detail:${packet.msgId}',
        detail.encode(),
        kAlertAirtime,
        priority: 2,
      );
    }
    _broadcastLocationFor(packet.msgId);
  }

  /// Puts this phone's position on the air alongside an alert.
  ///
  /// The cached fix goes out immediately — an emergency button must never
  /// block on GPS, which can take half a minute to acquire cold. A fresh
  /// fix is then requested in the background and, if it lands while the
  /// alert is still on the air, replaces the cached one under the same
  /// broadcast key. Worst case the receiver gets a slightly stale position;
  /// that is enormously better than no position, and better than an SOS
  /// that took 30 seconds to send.
  void _broadcastLocationFor(int msgId) {
    final cached = location.lastKnown;
    if (cached != null) {
      final loc = LocationPacket(
        msgId: msgId,
        latitude: cached.latitude,
        longitude: cached.longitude,
      );
      _alertLocations[msgId] = loc;
      _queueBroadcast('loc:$msgId', loc.encode(), kAlertAirtime, priority: 2);
      appendLog('Your position is going out with this alert', 'Sent');
    } else {
      appendLog(
        'No location fix yet — this alert goes out without a position',
        'Warning',
      );
    }

    unawaited(() async {
      final fresh = await location.currentFix();
      if (fresh == null || _disposed) return;
      final loc = LocationPacket(
        msgId: msgId,
        latitude: fresh.latitude,
        longitude: fresh.longitude,
      );
      _alertLocations[msgId] = loc;
      // Same key, so this replaces the cached position rather than
      // competing with it for airtime.
      _queueBroadcast('loc:$msgId', loc.encode(), kAlertAirtime, priority: 2);
      if (cached == null) {
        appendLog(
          'Got a location fix — now sending it with your alert',
          'Sent',
        );
      }
    }());
  }

  void _startCooldownTicker() {
    _cooldownTicker?.cancel();
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      notifyListeners();
      if (!onCooldown) t.cancel();
    });
  }

  Future<void> refreshSeenCount() async {
    seenCount = await SeenMessagesDb.count();
    notifyListeners();
  }

  void appendLog(String text, String kind) {
    // Mirrored to logcat so the mesh can be diagnosed on a real device
    // (`adb logcat | grep WariMesh`) — the in-app feed is invisible once
    // the screen is off, which is exactly when the interesting failures
    // happen.
    debugPrint('WariMesh[$kind] $text');
    log.insert(0, LogEntry(text, kind));
    if (log.length > 200) log.removeLast();
    notifyListeners();
  }
}
