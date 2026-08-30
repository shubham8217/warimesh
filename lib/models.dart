// WariMesh — shared data models + the mesh packet protocol.
//
// Packet protocol (15 bytes, carried as BLE manufacturer data):
//   [0]     packetType   (always 1 = ALERT, reserved for future packet kinds)
//   [1]     ttl          (hop budget; each relay decrements by 1)
//   [2..5]  msgId        (uint32, random per send; dedup + loop prevention)
//   [6]     category     (0 = SOS, 1 = Lost Person)
//   [7..12] senderLabel  (6 ASCII chars — the sender's persistent Mesh ID,
//                         e.g. "W7K2M9": role letter + 5 random chars,
//                         generated once at sign-in, not per launch)
//   [13..14] groupTag    (2 ASCII chars — a short deterministic hash of the
//                         sender's Dindi/camp name, used by receivers to
//                         decide whether to show a loud notification or
//                         just log the alert quietly; every phone still
//                         relays every packet regardless of this tag)
//
// This packet is intentionally tiny — it's what can hop phone to phone
// over BLE advertising with no internet and no pairing. A name,
// description or photo can never ride the mesh itself: that richer data
// (LostReport below) lives only on the reporting phone's own SQLite
// database. What travels over the mesh is a lightweight "look out for
// this" beacon; the human details are meant to sync separately once a
// phone reaches internet or a camp coordinator — that sync isn't built
// yet, so today a LostReport is local-only until you show someone the
// phone directly.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

const int kManufacturerId = 0xFFFF; // BT SIG "reserved for testing" ID — fine for a prototype, not for shipped hardware.
const int kPacketType = 1;
const int kDefaultTtl = 2;
const int kPacketLength = 15;
const int kCategorySos = 0;
const int kCategoryLostPerson = 1;

// A presence beacon lives in its own, separate wire format (packetType 2,
// see PresencePacket below) rather than being a category of MeshPacket —
// deliberately so it can carry a first name without touching the 15-byte
// ALERT format at all. The untested-on-real-hardware core relay only ever
// deals with packetType 1; presence packets are decoded on a completely
// separate path and never enter that code.
const int kPresencePacketType = 2;
const int kPresenceNameLength = 10; // fits a first name; longer ones truncate
const int kPresenceBaseLength = 1 + 6 + 2 + kPresenceNameLength; // type + meshId + groupTag + name
// A trailing station byte (see kStationNone and friends) was appended after
// the name, taking the beacon from 19 to 20 bytes. It is deliberately LAST
// and read by length, not position: a phone still running the 19-byte
// format decodes here as kStationNone rather than failing, and an older
// phone ignores the extra byte it doesn't know how to read. No flag day,
// no version negotiation — just append-only growth, which is the only kind
// of protocol change you can safely make to devices you cannot update.
const int kPresencePacketLength = kPresenceBaseLength + 1;

// A missing-person DETAIL packet (packetType 3, see LostPersonDetailPacket)
// — sent alongside the Lost Person ALERT, carrying the one thing that
// makes the alert actionable: who to look for. Without it a receiving
// phone can only say "someone reported someone missing", which is nearly
// useless to a person standing in a crowd.
//
// Kept to name + age and linked back to the alert by msgId. A full
// description, last-seen location and photo still can't fit in a BLE
// advertisement (~24 usable bytes) and remain local to the reporting
// phone / the cloud-sync path.
// TEXT messages — Dindi chat (packetTypes 5 and 6, see TextHeadPacket /
// TextPartPacket).
//
// Every other packet in this file fits in a single advertisement. Text does
// not: ~24 usable bytes is roughly three words, so a message has to be cut
// into fragments, put on the air one at a time, and reassembled by the
// receiver. That is what these two packet types are for.
//
//   head (5): identity + how many fragments to expect + the first 9 chars
//   part (6): msgId + fragment index + 17 more chars
//
// So a message is 9 + 17×(n−1) characters over n fragments. kMaxTextLength
// is set well inside the 15-fragment ceiling the 4-bit counter allows,
// because every extra fragment is another few seconds of airtime — see the
// note on kTextAirtime in mesh_service.dart. This is a walkie-talkie, not
// WhatsApp: short, useful messages ("water point at the next turn"), not
// conversation.
//
// PRIVACY: a BLE advertisement is public and unencrypted. Anyone in range
// with a scanner can read every word, whether or not they are in the Dindi.
// The groupTag decides who is *shown* a message, never who can hear it.
// This is stated plainly in the chat UI too — people must not assume a
// private channel where none exists.
const int kTextHeadPacketType = 5;
const int kTextPartPacketType = 6;
const int kTextHeadChars = 9;
const int kTextPartChars = 17;
const int kMaxTextFragments = 8; // 4-bit field allows 15; kept lower for airtime
const int kMaxTextLength = kTextHeadChars + kTextPartChars * (kMaxTextFragments - 1); // 128

/// What a text message is for. An [announcement] is an advisory from a
/// volunteer to everyone in range regardless of Dindi — route changes,
/// weather, a closed water point. A [chat] message is ordinary talk within
/// one Dindi.
const int kTextKindChat = 0;
const int kTextKindAnnouncement = 1;

// A LOCATION packet (packetType 4, see LocationPacket) — where the alert
// was sent from, linked back to it by msgId. Without this an SOS says
// "someone nearby needs help" and nothing more, which in a crowd of a
// hundred thousand people is close to unactionable: the receiver has no
// idea whether to look ten metres away or four hundred.
//
// Coordinates ride as two int32s of degrees × 1e7 (the usual fixed-point
// GPS encoding, ~1cm resolution, and ±1.8e9 still inside int32 range), so
// the whole packet is 13 bytes and fits an advertisement comfortably.
//
// PRIVACY, stated plainly: a BLE advertisement is public. Anyone in range
// with a scanner can read this, not just WariMesh users. For an SOS that
// is the whole point — you are asking to be found — and the same applies
// to a missing-person report. It is broadcast ONLY as part of sending an
// alert, never continuously: the presence beacon (PresencePacket) carries
// no location and never has.
const int kLocationPacketType = 4;
const int kLocationPacketLength = 1 + 4 + 4 + 4; // type + msgId + lat + lon

const int kLostDetailPacketType = 3;
const int kLostDetailNameLength = 12;
const int kLostDetailAgeLength = 3;
const int kLostDetailPacketLength = 1 + 4 + kLostDetailNameLength + kLostDetailAgeLength;

// RESPONSE packets — ACK (type 7) and RESOLVE (type 8).
//
// Every packet above this line exists to raise an alarm. These two exist to
// close one, which until now the mesh simply could not do: an alert went
// out, hopped as far as its TTL allowed, and then nothing — no way for a
// volunteer to say "I have this", no way for anyone to say "she's been
// found, stop looking". A lost-child beacon would keep circulating across
// the Wari for as long as phones kept re-airing it.
//
//   ACK     (7): msgId + responder's Mesh ID          — 11 bytes
//   RESOLVE (8): msgId + resolver's Mesh ID + reason  — 12 bytes
//
// Both are tiny because both are just a reference to an alert that every
// phone in range has already seen and stored. The ACK is what turns
// "alert sent" on the sender's phone into "V7K2M9 is responding" — the
// single most useful sentence this app can put in front of someone who
// has just pressed SOS in a crowd of a hundred thousand people. It also
// stops five volunteers converging on one incident while a second goes
// unanswered, since a claimed alert is visibly claimed on every phone.
//
// Like presence, location and text, these are decoded on a path entirely
// separate from the core ALERT relay (packetType 1), which is the code
// path that has never been proven on real hardware. Nothing here can
// change how an alert relays.
//
// TRUST, stated plainly: a BLE advertisement is unauthenticated. Anyone in
// range can forge an ACK or a RESOLVE for a msgId they have overheard.
// There is no signing here and there cannot be in 12 bytes. The UI must
// therefore treat these as claims attributed to a Mesh ID, never as
// facts — a resolved alert is greyed out and moved down, never deleted,
// and it can always be reopened by hand.
const int kAckPacketType = 7;
const int kAckPacketLength = 1 + 4 + 6; // type + msgId + responder meshId

const int kResolvePacketType = 8;
const int kResolvePacketLength = 1 + 4 + 6 + 1; // type + msgId + meshId + reason

/// Why an alert was closed. [kResolveFound] is the one that matters — the
/// missing person is back with their people — and is worded that way
/// everywhere in the UI.
const int kResolveFound = 0;
const int kResolveHandled = 1;
const int kResolveFalseAlarm = 2;

String resolveReasonLabel(int reason) {
  switch (reason) {
    case kResolveFound:
      return 'Found safe';
    case kResolveFalseAlarm:
      return 'False alarm';
    default:
      return 'Handled';
  }
}

/// What kind of help a volunteer's phone is standing next to, carried in
/// the presence beacon (see [PresencePacket]). Volunteers are the one group
/// on the Wari that stays put — they staff a camp at a halt while everyone
/// else walks past — so their phones are the mesh's natural anchors. This
/// byte is what makes that physical fact legible to a pilgrim: not just
/// "a phone is nearby" but "medical help is nearby, this direction".
///
/// [kStationNone] is the default and what every volunteer starts as; going
/// on duty at a camp is a deliberate choice, because claiming to be a
/// medical point when you are not is worse than claiming nothing.
const int kStationNone = 0;
const int kStationMedical = 1;
const int kStationWater = 2;
const int kStationFood = 3;
const int kStationLostChildDesk = 4;
const int kStationPolice = 5;
// Added for the Wari Seva Network (HelpPointPacket) — kept in the same byte
// space as the original five so one station code works for both the ambient
// presence beacon and the relayed HELP_POINT packet. See kHelpPointTypes in
// mesh_service.dart's HelpPointRecord for future extensibility (crowd
// density, ambulance, route diversions, …) this list is designed to grow
// into without a wire-format change — station is already just a byte.
const int kStationToilet = 6;
const int kStationNightHalt = 7;
const int kStationCharging = 8;
const int kStationFirstAid = 9;
const int kStationOther = 10;

const List<int> kStationTypes = [
  kStationNone,
  kStationMedical,
  kStationWater,
  kStationFood,
  kStationLostChildDesk,
  kStationPolice,
  kStationToilet,
  kStationNightHalt,
  kStationCharging,
  kStationFirstAid,
  kStationOther,
];

String stationLabel(int station) {
  switch (station) {
    case kStationMedical:
      return 'Medical';
    case kStationWater:
      return 'Water';
    case kStationFood:
      return 'Food';
    case kStationLostChildDesk:
      return 'Lost child desk';
    case kStationPolice:
      return 'Police';
    case kStationToilet:
      return 'Toilet';
    case kStationNightHalt:
      return 'Night halt';
    case kStationCharging:
      return 'Charging';
    case kStationFirstAid:
      return 'First aid';
    case kStationOther:
      return 'Help point';
    default:
      return 'Not at a help point';
  }
}

/// A short, one-line icon-free description used where a full label reads
/// too formally — e.g. a confirmation dialog. Kept separate from
/// [stationLabel] so that one can stay a plain noun (good for chips) while
/// this can read like a sentence fragment.
String stationAnnounceLabel(int station) => '${stationLabel(station)} help';

// ---------------------------------------------------------------------------
// HELP_POINT — the Wari Seva Network.
//
// A volunteer's phone going on duty (see setStation in mesh_service.dart)
// already broadcasts a PresencePacket carrying its station, but that beacon
// is deliberately single-hop and carries no notion of "closed" or "expired"
// — it simply goes quiet 45s after the phone stops sending it (see
// kPresenceExpiry). That's the right behaviour for "is a phone physically
// near me right now", but it is the wrong behaviour for "where is the
// nearest medical tent", which has to survive relay through phones that are
// not the volunteer's, and has to be explicitly closeable — a volunteer
// packing up a water point should be able to say so once, and have that
// travel exactly like a RESOLVE for an alert (see kResolvePacketType) rather
// than just letting the beacon time out for everyone.
//
// So HELP_POINT (9) rides the same relay machinery as an ALERT: a unique
// msgId, a TTL that decrements per hop, and dedup against seen_messages
// (see SeenMessagesDb.hasSeen — already keyed on msgId alone, so it works
// unmodified here). HELP_POINT_STATUS_UPDATE (10) closes/updates it, mirroring
// RESOLVE.
//
// Deliberately NOT carrying a location: see the note on kLocationPacketType
// for why a *chosen* disclosure (an SOS) is a different privacy proposition
// from a standing one, and PresencePacket above for why the mesh already
// treats "can I hear it at all" as the proximity signal for exactly this
// kind of beacon. HELP_POINT follows the same rule.
const int kHelpPointPacketType = 9;
const int kHelpPointPacketLength = 1 + 1 + 4 + 1 + 1 + 6 + 1; // 15 bytes — same budget as MeshPacket

const int kHelpStatusOpen = 0;
const int kHelpStatusClosed = 1;
const int kHelpStatusLimited = 2;

String helpStatusLabel(int status) {
  switch (status) {
    case kHelpStatusClosed:
      return 'Closed';
    case kHelpStatusLimited:
      return 'Limited space';
    default:
      return 'Open';
  }
}

/// How long a freshly-announced help point stays valid before it is dropped
/// even if nobody ever closes it — the "temporary" in temporary help point.
/// A night halt is meant to stand for hours; most other stations are worth
/// re-confirming sooner, since a volunteer may simply have walked off
/// without remembering to go off duty.
Duration helpPointDefaultExpiry(int helpType) {
  switch (helpType) {
    case kStationNightHalt:
      return const Duration(hours: 12);
    default:
      return const Duration(hours: 2);
  }
}

/// "Medical help available here" — announced by a volunteer's phone,
/// relayed hop by hop exactly like an SOS. [expiresInMinutesDiv5] is coarse
/// on purpose: one byte covers over 21 hours at 5-minute resolution, which
/// is more than any help point on the Wari needs.
class HelpPointPacket {
  final int ttl;
  final int msgId;
  final int helpType;
  final int status;
  final String senderLabel;
  final int expiresInMinutesDiv5;

  HelpPointPacket({
    required this.ttl,
    required this.msgId,
    required this.helpType,
    required this.senderLabel,
    this.status = kHelpStatusOpen,
    this.expiresInMinutesDiv5 = 24, // 120 minutes
  });

  Duration get expiryDuration => Duration(minutes: expiresInMinutesDiv5 * 5);

  Uint8List encode() {
    final bytes = Uint8List(kHelpPointPacketLength);
    bytes[0] = kHelpPointPacketType;
    bytes[1] = ttl & 0xFF;
    final idBytes = ByteData(4)..setUint32(0, msgId, Endian.big);
    bytes.setRange(2, 6, idBytes.buffer.asUint8List());
    bytes[6] = helpType & 0xFF;
    bytes[7] = status & 0xFF;
    final label = asciiSafe(senderLabel).padRight(6).substring(0, 6);
    bytes.setRange(8, 14, ascii.encode(label));
    bytes[14] = expiresInMinutesDiv5 & 0xFF;
    return bytes;
  }

  static HelpPointPacket? decode(List<int> raw) {
    if (raw.length < kHelpPointPacketLength) return null;
    if (raw[0] != kHelpPointPacketType) return null;
    final idBytes = Uint8List.fromList(raw.sublist(2, 6));
    final msgId = ByteData.sublistView(idBytes).getUint32(0, Endian.big);
    final helpType = raw[6];
    final status = raw[7];
    final label = ascii.decode(raw.sublist(8, 14), allowInvalid: true).trim();
    if (label.isEmpty) return null;
    // An unrecognised station code (from a newer build, or a corrupt
    // advertisement) must not render as a help point of some undefined
    // kind — see the same guard on PresencePacket.decode.
    if (!kStationTypes.contains(helpType) || helpType == kStationNone) return null;
    return HelpPointPacket(
      ttl: raw[1],
      msgId: msgId,
      helpType: helpType,
      status: status <= kHelpStatusLimited ? status : kHelpStatusOpen,
      senderLabel: label,
      expiresInMinutesDiv5: raw[14],
    );
  }

  HelpPointPacket relayed() => HelpPointPacket(
        ttl: ttl - 1,
        msgId: msgId,
        helpType: helpType,
        status: status,
        senderLabel: senderLabel,
        expiresInMinutesDiv5: expiresInMinutesDiv5,
      );
}

/// "This help point is closed / limited now." The HELP_POINT counterpart to
/// [ResolvePacket] — see the note above kHelpPointPacketType. Like ACK/
/// RESOLVE, this carries no TTL: a phone relays a given status update
/// exactly once (see MeshService._relayedResponses), which bounds the flood
/// without a hop counter.
class HelpPointStatusPacket {
  final int msgId;
  final String updaterMeshId;
  final int status;

  HelpPointStatusPacket({
    required this.msgId,
    required this.updaterMeshId,
    this.status = kHelpStatusClosed,
  });

  Uint8List encode() {
    final bytes = Uint8List(kHelpPointStatusPacketLength);
    bytes[0] = kHelpPointStatusPacketType;
    final idBytes = ByteData(4)..setUint32(0, msgId, Endian.big);
    bytes.setRange(1, 5, idBytes.buffer.asUint8List());
    final who = asciiSafe(updaterMeshId).padRight(6).substring(0, 6);
    bytes.setRange(5, 11, ascii.encode(who));
    bytes[11] = status & 0xFF;
    return bytes;
  }

  static HelpPointStatusPacket? decode(List<int> raw) {
    if (raw.length < kHelpPointStatusPacketLength) return null;
    if (raw[0] != kHelpPointStatusPacketType) return null;
    final idBytes = Uint8List.fromList(raw.sublist(1, 5));
    final msgId = ByteData.sublistView(idBytes).getUint32(0, Endian.big);
    final who = ascii.decode(raw.sublist(5, 11), allowInvalid: true).trim();
    if (who.isEmpty) return null;
    final status = raw[11];
    return HelpPointStatusPacket(
      msgId: msgId,
      updaterMeshId: who,
      status: status <= kHelpStatusLimited ? status : kHelpStatusClosed,
    );
  }
}

const int kHelpPointStatusPacketType = 10;
const int kHelpPointStatusPacketLength = 1 + 4 + 6 + 1; // 12 bytes — same shape as ResolvePacket

/// A help point as stored on this phone — the durable counterpart to
/// [HelpPointPacket], same relationship [AlertRecord] has to [MeshPacket].
/// Written for every help point announced here *and* every one received,
/// so it survives an app restart and so "Nearby Seva" doesn't go blank the
/// instant the announcing phone falls out of range.
class HelpPointRecord {
  final int msgId;
  final int helpType;
  final String senderLabel;
  final String? senderName;
  final DateTime receivedAt;
  final DateTime expiresAt;
  final int hops;
  final bool mine;

  int status;
  String? closedBy;
  DateTime? closedAt;

  /// Set locally when the person taps "I'm going there" — never broadcast,
  /// never authoritative, just a note to themselves.
  bool acknowledged;

  HelpPointRecord({
    required this.msgId,
    required this.helpType,
    required this.senderLabel,
    required this.receivedAt,
    required this.expiresAt,
    this.senderName,
    this.hops = 0,
    this.mine = false,
    this.status = kHelpStatusOpen,
    this.closedBy,
    this.closedAt,
    this.acknowledged = false,
  });

  bool get isOpen => status == kHelpStatusOpen;
  bool get isClosed => status == kHelpStatusClosed;
  bool get isLimited => status == kHelpStatusLimited;
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Whether this belongs in "Nearby Seva" right now.
  bool get isActive => !isClosed && !isExpired;

  String get label => stationLabel(helpType);

  /// "heard just now" / "heard 2 min ago" — same honesty rule as
  /// [HelpPoint.freshnessLabel]: a help point announced 90 minutes ago is
  /// still technically active, but a person deciding whether to walk
  /// towards it should be able to see how stale that promise is.
  String get freshnessLabel {
    final mins = DateTime.now().difference(receivedAt).inMinutes;
    if (mins < 1) return 'just now';
    if (mins < 60) return '$mins min ago';
    final hours = mins ~/ 60;
    return hours < 24 ? '${hours}h ago' : '${hours ~/ 24}d ago';
  }

  Map<String, Object?> toMap() => {
        'msg_id': msgId,
        'help_type': helpType,
        'sender_label': senderLabel,
        'sender_name': senderName,
        'received_at': receivedAt.millisecondsSinceEpoch,
        'expires_at': expiresAt.millisecondsSinceEpoch,
        'hops': hops,
        'mine': mine ? 1 : 0,
        'status': status,
        'closed_by': closedBy,
        'closed_at': closedAt?.millisecondsSinceEpoch,
        'acknowledged': acknowledged ? 1 : 0,
      };

  static HelpPointRecord fromMap(Map<String, Object?> map) => HelpPointRecord(
        msgId: map['msg_id'] as int,
        helpType: map['help_type'] as int,
        senderLabel: map['sender_label'] as String,
        senderName: map['sender_name'] as String?,
        receivedAt: DateTime.fromMillisecondsSinceEpoch(map['received_at'] as int),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(map['expires_at'] as int),
        hops: (map['hops'] as int?) ?? 0,
        mine: ((map['mine'] as int?) ?? 0) == 1,
        status: (map['status'] as int?) ?? kHelpStatusOpen,
        closedBy: map['closed_by'] as String?,
        closedAt: map['closed_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['closed_at'] as int),
        acknowledged: ((map['acknowledged'] as int?) ?? 0) == 1,
      );
}

// Alphabet avoids visually-ambiguous characters (0/O, 1/I/L) since a Mesh ID
// is meant to be readable off a screen or said aloud if two people need to
// confirm they're looking at the same phone.
const String _kMeshIdAlphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

/// A persistent, per-person identifier: one role letter (W = warkari,
/// V = volunteer) + 5 random characters, generated exactly once — at
/// sign-in — and saved to volunteer_profile from then on. This is what
/// rides the mesh as `senderLabel`, replacing the old behaviour of
/// regenerating a random "DEV482"-style label on every app launch, which
/// made relay logs and "who sent this" attribution meaningless across
/// restarts.
String generateMeshId(UserRole role) {
  final rand = Random.secure();
  final prefix = role == UserRole.warkari ? 'W' : 'V';
  final body = List.generate(5, (_) => _kMeshIdAlphabet[rand.nextInt(_kMeshIdAlphabet.length)]).join();
  return '$prefix$body';
}

/// A short, deterministic 2-character tag derived from a Dindi/group name
/// (or volunteer camp ID) so two phones from the same group produce the
/// same tag without any shared registry — just a stable hash of the text
/// itself. Case/whitespace-insensitive so "Sant Tukaram Dindi" and
/// " sant tukaram dindi " tag identically.
String dindiTagFor(String groupOrId) {
  final normalized = groupOrId.trim().toLowerCase();
  if (normalized.isEmpty || normalized == '—') return '--';
  var hash = 0;
  for (final codeUnit in normalized.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7FFFFFFF;
  }
  final a = _kMeshIdAlphabet[hash % _kMeshIdAlphabet.length];
  final b = _kMeshIdAlphabet[(hash ~/ _kMeshIdAlphabet.length) % _kMeshIdAlphabet.length];
  return '$a$b';
}

String categoryLabel(int category) =>
    category == kCategorySos ? 'SOS' : 'Lost Person';

/// Names on the Wari are very plausibly non-ASCII (Devanagari, etc.), and
/// ascii.encode() throws on anything outside 7-bit ASCII. Substituting '?'
/// keeps one person's name from crashing a whole broadcast — the packet
/// formats here are byte-counted and have no room for UTF-8.
String asciiSafe(String s) =>
    String.fromCharCodes(s.codeUnits.map((c) => c < 128 ? c : 63)); // 63 = '?'

class MeshPacket {
  final int ttl;
  final int msgId;
  final int category;
  final String senderLabel;
  final String groupTag;

  MeshPacket({
    required this.ttl,
    required this.msgId,
    required this.category,
    required this.senderLabel,
    this.groupTag = '--',
  });

  Uint8List encode() {
    final bytes = Uint8List(kPacketLength);
    bytes[0] = kPacketType;
    bytes[1] = ttl & 0xFF;
    final idBytes = ByteData(4)..setUint32(0, msgId, Endian.big);
    bytes.setRange(2, 6, idBytes.buffer.asUint8List());
    bytes[6] = category & 0xFF;
    final label = senderLabel.padRight(6).substring(0, 6);
    bytes.setRange(7, 13, ascii.encode(label));
    final tag = groupTag.padRight(2).substring(0, 2);
    bytes.setRange(13, 15, ascii.encode(tag));
    return bytes;
  }

  static MeshPacket? decode(List<int> raw) {
    if (raw.length < kPacketLength) return null;
    if (raw[0] != kPacketType) return null;
    final ttl = raw[1];
    final idBytes = Uint8List.fromList(raw.sublist(2, 6));
    final msgId = ByteData.sublistView(idBytes).getUint32(0, Endian.big);
    final category = raw[6];
    final label = ascii.decode(raw.sublist(7, 13), allowInvalid: true).trim();
    final groupTag = ascii.decode(raw.sublist(13, 15), allowInvalid: true).trim();
    return MeshPacket(
      ttl: ttl,
      msgId: msgId,
      category: category,
      senderLabel: label,
      groupTag: groupTag,
    );
  }

  /// The packet this device re-advertises after deciding to relay: same
  /// identity (msgId/category/sender/group), TTL down by one hop.
  MeshPacket relayed() => MeshPacket(
        ttl: ttl - 1,
        msgId: msgId,
        category: category,
        senderLabel: senderLabel,
        groupTag: groupTag,
      );
}

/// "I exist" — broadcast every ~15s (see MeshService._broadcastPresence)
/// so nearby phones can show a live Dindi headcount with actual first
/// names, not just Mesh IDs. Single-hop only (never relayed, no ttl/msgId
/// needed) and completely separate from MeshPacket's wire format — see the
/// note on kPresencePacketType above for why.
class PresencePacket {
  final String meshId;
  final String groupTag;
  final String name;

  /// What kind of help point this phone is standing at, or [kStationNone].
  /// See the kStation* constants for why this is worth a byte.
  final int station;

  PresencePacket({
    required this.meshId,
    required this.groupTag,
    required this.name,
    this.station = kStationNone,
  });

  bool get isHelpPoint => station != kStationNone;

  Uint8List encode() {
    final bytes = Uint8List(kPresencePacketLength);
    bytes[0] = kPresencePacketType;
    final id = asciiSafe(meshId).padRight(6).substring(0, 6);
    bytes.setRange(1, 7, ascii.encode(id));
    final tag = asciiSafe(groupTag).padRight(2).substring(0, 2);
    bytes.setRange(7, 9, ascii.encode(tag));
    final displayName = asciiSafe(name).padRight(kPresenceNameLength).substring(0, kPresenceNameLength);
    bytes.setRange(9, 9 + kPresenceNameLength, ascii.encode(displayName));
    bytes[kPresenceBaseLength] = station & 0xFF;
    return bytes;
  }

  static PresencePacket? decode(List<int> raw) {
    // Accepts both the 19-byte original and the 20-byte station form — see
    // the note on kPresencePacketLength.
    if (raw.length < kPresenceBaseLength) return null;
    if (raw[0] != kPresencePacketType) return null;
    final meshId = ascii.decode(raw.sublist(1, 7), allowInvalid: true).trim();
    final groupTag = ascii.decode(raw.sublist(7, 9), allowInvalid: true).trim();
    final name = ascii.decode(raw.sublist(9, 9 + kPresenceNameLength), allowInvalid: true).trim();
    final station = raw.length > kPresenceBaseLength ? raw[kPresenceBaseLength] : kStationNone;
    return PresencePacket(
      meshId: meshId,
      groupTag: groupTag,
      name: name,
      // An unknown station code from a newer build must not render as a
      // help point of some undefined kind — fall back to "not a help point".
      station: kStationTypes.contains(station) ? station : kStationNone,
    );
  }
}

/// "I am responding to this alert." Sent by a volunteer claiming an alert
/// they have received; see the note on kAckPacketType for why 11 bytes is
/// enough and why the claim is unauthenticated.
class AckPacket {
  final int msgId;
  final String responderMeshId;

  AckPacket({required this.msgId, required this.responderMeshId});

  Uint8List encode() {
    final bytes = Uint8List(kAckPacketLength);
    bytes[0] = kAckPacketType;
    final idBytes = ByteData(4)..setUint32(0, msgId, Endian.big);
    bytes.setRange(1, 5, idBytes.buffer.asUint8List());
    final who = asciiSafe(responderMeshId).padRight(6).substring(0, 6);
    bytes.setRange(5, kAckPacketLength, ascii.encode(who));
    return bytes;
  }

  static AckPacket? decode(List<int> raw) {
    if (raw.length < kAckPacketLength) return null;
    if (raw[0] != kAckPacketType) return null;
    final idBytes = Uint8List.fromList(raw.sublist(1, 5));
    final msgId = ByteData.sublistView(idBytes).getUint32(0, Endian.big);
    final who = ascii.decode(raw.sublist(5, kAckPacketLength), allowInvalid: true).trim();
    if (who.isEmpty) return null;
    return AckPacket(msgId: msgId, responderMeshId: who);
  }
}

/// "This alert is closed." The counterpart to [AckPacket] — see
/// kResolvePacketType. [reason] is one of the kResolve* constants.
class ResolvePacket {
  final int msgId;
  final String resolverMeshId;
  final int reason;

  ResolvePacket({
    required this.msgId,
    required this.resolverMeshId,
    this.reason = kResolveFound,
  });

  Uint8List encode() {
    final bytes = Uint8List(kResolvePacketLength);
    bytes[0] = kResolvePacketType;
    final idBytes = ByteData(4)..setUint32(0, msgId, Endian.big);
    bytes.setRange(1, 5, idBytes.buffer.asUint8List());
    final who = asciiSafe(resolverMeshId).padRight(6).substring(0, 6);
    bytes.setRange(5, 11, ascii.encode(who));
    bytes[11] = reason & 0xFF;
    return bytes;
  }

  static ResolvePacket? decode(List<int> raw) {
    if (raw.length < kResolvePacketLength) return null;
    if (raw[0] != kResolvePacketType) return null;
    final idBytes = Uint8List.fromList(raw.sublist(1, 5));
    final msgId = ByteData.sublistView(idBytes).getUint32(0, Endian.big);
    final who = ascii.decode(raw.sublist(5, 11), allowInvalid: true).trim();
    if (who.isEmpty) return null;
    final reason = raw[11];
    return ResolvePacket(
      msgId: msgId,
      resolverMeshId: who,
      reason: reason <= kResolveFalseAlarm ? reason : kResolveHandled,
    );
  }
}

/// Who to look for, sent right after a Lost Person alert and linked to it
/// by [msgId]. See the note on kLostDetailPacketType for the size limits
/// that keep this to a name and an age.
class LostPersonDetailPacket {
  final int msgId;
  final String name;
  final String age;

  LostPersonDetailPacket({required this.msgId, required this.name, required this.age});

  Uint8List encode() {
    final bytes = Uint8List(kLostDetailPacketLength);
    bytes[0] = kLostDetailPacketType;
    final idBytes = ByteData(4)..setUint32(0, msgId, Endian.big);
    bytes.setRange(1, 5, idBytes.buffer.asUint8List());
    final n = asciiSafe(name).padRight(kLostDetailNameLength).substring(0, kLostDetailNameLength);
    bytes.setRange(5, 5 + kLostDetailNameLength, ascii.encode(n));
    final a = asciiSafe(age).padRight(kLostDetailAgeLength).substring(0, kLostDetailAgeLength);
    bytes.setRange(5 + kLostDetailNameLength, kLostDetailPacketLength, ascii.encode(a));
    return bytes;
  }

  static LostPersonDetailPacket? decode(List<int> raw) {
    if (raw.length < kLostDetailPacketLength) return null;
    if (raw[0] != kLostDetailPacketType) return null;
    final idBytes = Uint8List.fromList(raw.sublist(1, 5));
    final msgId = ByteData.sublistView(idBytes).getUint32(0, Endian.big);
    final name = ascii.decode(raw.sublist(5, 5 + kLostDetailNameLength), allowInvalid: true).trim();
    final age = ascii.decode(raw.sublist(5 + kLostDetailNameLength, kLostDetailPacketLength), allowInvalid: true).trim();
    return LostPersonDetailPacket(msgId: msgId, name: name, age: age);
  }
}

/// Where an alert was sent from, linked to it by [msgId]. See the note on
/// kLocationPacketType for the encoding and the privacy trade-off.
class LocationPacket {
  final int msgId;
  final double latitude;
  final double longitude;

  LocationPacket({required this.msgId, required this.latitude, required this.longitude});

  Uint8List encode() {
    final bytes = Uint8List(kLocationPacketLength);
    bytes[0] = kLocationPacketType;
    final view = ByteData(12)
      ..setUint32(0, msgId, Endian.big)
      ..setInt32(4, (latitude * 1e7).round(), Endian.big)
      ..setInt32(8, (longitude * 1e7).round(), Endian.big);
    bytes.setRange(1, kLocationPacketLength, view.buffer.asUint8List());
    return bytes;
  }

  static LocationPacket? decode(List<int> raw) {
    if (raw.length < kLocationPacketLength) return null;
    if (raw[0] != kLocationPacketType) return null;
    final view = ByteData.sublistView(Uint8List.fromList(raw.sublist(1, kLocationPacketLength)));
    final lat = view.getInt32(4, Endian.big) / 1e7;
    final lon = view.getInt32(8, Endian.big) / 1e7;
    // A corrupt advertisement can decode to coordinates that aren't on
    // Earth. Pointing someone at a garbage fix is worse than showing them
    // no location at all, so drop it instead.
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    return LocationPacket(
      msgId: view.getUint32(0, Endian.big),
      latitude: lat,
      longitude: lon,
    );
  }
}

/// First fragment of a text message: who sent it, which Dindi it belongs
/// to, whether it's chat or an advisory, how many fragments to expect, and
/// the first [kTextHeadChars] characters.
class TextHeadPacket {
  final int msgId;
  final int ttl;
  final int kind;
  final int fragTotal;
  final String groupTag;
  final String senderLabel;
  final String chunk;

  TextHeadPacket({
    required this.msgId,
    required this.ttl,
    required this.kind,
    required this.fragTotal,
    required this.groupTag,
    required this.senderLabel,
    required this.chunk,
  });

  Uint8List encode() {
    final bytes = Uint8List(24);
    bytes[0] = kTextHeadPacketType;
    final id = ByteData(4)..setUint32(0, msgId, Endian.big);
    bytes.setRange(1, 5, id.buffer.asUint8List());
    bytes[5] = ttl & 0xFF;
    // Two 4-bit fields in one byte: kind above, fragment count below.
    bytes[6] = ((kind & 0x0F) << 4) | (fragTotal & 0x0F);
    bytes.setRange(7, 9, ascii.encode(asciiSafe(groupTag).padRight(2).substring(0, 2)));
    bytes.setRange(9, 15, ascii.encode(asciiSafe(senderLabel).padRight(6).substring(0, 6)));
    bytes.setRange(15, 24, ascii.encode(asciiSafe(chunk).padRight(kTextHeadChars).substring(0, kTextHeadChars)));
    return bytes;
  }

  static TextHeadPacket? decode(List<int> raw) {
    if (raw.length < 24 || raw[0] != kTextHeadPacketType) return null;
    final total = raw[6] & 0x0F;
    // A zero-fragment message is meaningless and would divide-by-zero the
    // reassembler; a corrupt advertisement can easily produce one.
    if (total < 1 || total > kMaxTextFragments) return null;
    final id = ByteData.sublistView(Uint8List.fromList(raw.sublist(1, 5)));
    return TextHeadPacket(
      msgId: id.getUint32(0, Endian.big),
      ttl: raw[5],
      kind: (raw[6] >> 4) & 0x0F,
      fragTotal: total,
      groupTag: ascii.decode(raw.sublist(7, 9), allowInvalid: true).trim(),
      senderLabel: ascii.decode(raw.sublist(9, 15), allowInvalid: true).trim(),
      // Not trimmed: padding is stripped once the whole message is joined,
      // so a chunk ending in a real space keeps it.
      chunk: ascii.decode(raw.sublist(15, 24), allowInvalid: true),
    );
  }

  TextHeadPacket relayed() => TextHeadPacket(
        msgId: msgId, ttl: ttl - 1, kind: kind, fragTotal: fragTotal,
        groupTag: groupTag, senderLabel: senderLabel, chunk: chunk,
      );
}

/// A continuation fragment: [index] is 1-based, since fragment 0 is the
/// head. Carries no identity of its own — it's bound to its message by
/// [msgId] alone.
class TextPartPacket {
  final int msgId;
  final int ttl;
  final int index;
  final String chunk;

  TextPartPacket({required this.msgId, required this.ttl, required this.index, required this.chunk});

  Uint8List encode() {
    final bytes = Uint8List(24);
    bytes[0] = kTextPartPacketType;
    final id = ByteData(4)..setUint32(0, msgId, Endian.big);
    bytes.setRange(1, 5, id.buffer.asUint8List());
    bytes[5] = ttl & 0xFF;
    bytes[6] = index & 0xFF;
    bytes.setRange(7, 24, ascii.encode(asciiSafe(chunk).padRight(kTextPartChars).substring(0, kTextPartChars)));
    return bytes;
  }

  static TextPartPacket? decode(List<int> raw) {
    if (raw.length < 24 || raw[0] != kTextPartPacketType) return null;
    final index = raw[6];
    if (index < 1 || index >= kMaxTextFragments) return null;
    final id = ByteData.sublistView(Uint8List.fromList(raw.sublist(1, 5)));
    return TextPartPacket(
      msgId: id.getUint32(0, Endian.big),
      ttl: raw[5],
      index: index,
      chunk: ascii.decode(raw.sublist(7, 24), allowInvalid: true),
    );
  }

  TextPartPacket relayed() =>
      TextPartPacket(msgId: msgId, ttl: ttl - 1, index: index, chunk: chunk);
}

/// Splits [body] into the fragments that carry it over the air. Returns the
/// head packet plus however many continuation packets are needed.
({TextHeadPacket head, List<TextPartPacket> parts}) fragmentText({
  required int msgId,
  required int ttl,
  required int kind,
  required String groupTag,
  required String senderLabel,
  required String body,
}) {
  final safe = asciiSafe(body).trim();
  final text = safe.length > kMaxTextLength ? safe.substring(0, kMaxTextLength) : safe;

  final headChunk = text.length <= kTextHeadChars ? text : text.substring(0, kTextHeadChars);
  final rest = text.length <= kTextHeadChars ? '' : text.substring(kTextHeadChars);

  final chunks = <String>[];
  for (var i = 0; i < rest.length; i += kTextPartChars) {
    chunks.add(rest.substring(i, min(i + kTextPartChars, rest.length)));
  }

  final head = TextHeadPacket(
    msgId: msgId,
    ttl: ttl,
    kind: kind,
    fragTotal: 1 + chunks.length,
    groupTag: groupTag,
    senderLabel: senderLabel,
    chunk: headChunk,
  );
  final parts = [
    for (var i = 0; i < chunks.length; i++)
      TextPartPacket(msgId: msgId, ttl: ttl, index: i + 1, chunk: chunks[i]),
  ];
  return (head: head, parts: parts);
}

/// A text message as a person sees it — after reassembly, or as composed on
/// this phone. Stored in SQLite so a Dindi's conversation survives a
/// restart (see MessagesDb).
class MeshTextMessage {
  final int msgId;
  final int kind;
  final String groupTag;
  final String senderLabel;
  final String? senderName; // resolved from presence beacons where possible
  final String body;
  final DateTime createdAt;
  final bool outgoing;

  const MeshTextMessage({
    required this.msgId,
    required this.kind,
    required this.groupTag,
    required this.senderLabel,
    required this.senderName,
    required this.body,
    required this.createdAt,
    required this.outgoing,
  });

  bool get isAnnouncement => kind == kTextKindAnnouncement;

  /// Who to show as the author. Falls back to the Mesh ID when no presence
  /// beacon has told us a real name.
  String get displayName => outgoing
      ? 'You'
      : (senderName == null || senderName!.isEmpty) ? senderLabel : senderName!;

  Map<String, Object?> toMap() => {
        'msg_id': msgId,
        'kind': kind,
        'group_tag': groupTag,
        'sender_label': senderLabel,
        'sender_name': senderName,
        'body': body,
        'created_at': createdAt.millisecondsSinceEpoch,
        'outgoing': outgoing ? 1 : 0,
      };

  static MeshTextMessage fromMap(Map<String, Object?> m) => MeshTextMessage(
        msgId: m['msg_id'] as int,
        kind: m['kind'] as int,
        groupTag: m['group_tag'] as String,
        senderLabel: m['sender_label'] as String,
        senderName: m['sender_name'] as String?,
        body: m['body'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        outgoing: (m['outgoing'] as int? ?? 0) == 1,
      );
}

/// An alert this phone received and hasn't been acknowledged yet — what
/// the blocking in-app alert screen renders. [senderName] is resolved from
/// the presence table where possible (a real first name beats a Mesh ID);
/// [lostName]/[lostAge] arrive separately via LostPersonDetailPacket and
/// may still be null when the alert first lands.
class IncomingAlert {
  final MeshPacket packet;
  final String? senderName;
  final DateTime receivedAt;
  String? lostName;
  String? lostAge;

  /// Where the sender was, if a LocationPacket arrived for this msgId, and
  /// how far/which way that is from wherever this phone is now. All stay
  /// null when the sender had no GPS fix or this phone doesn't know its own
  /// position — an alert without a location is still shown in full, just
  /// without a distance. Never withhold an alert for want of coordinates.
  double? senderLatitude;
  double? senderLongitude;
  double? distanceMetres;
  double? bearingDegrees;

  IncomingAlert({
    required this.packet,
    required this.senderName,
    required this.receivedAt,
    this.lostName,
    this.lostAge,
    this.senderLatitude,
    this.senderLongitude,
    this.distanceMetres,
    this.bearingDegrees,
  });

  bool get hasLocation => senderLatitude != null && senderLongitude != null;

  /// "240 m away" / "1.4 km away" — null when there's no distance to show.
  String? get distanceLabel {
    final d = distanceMetres;
    if (d == null) return null;
    if (d < 1000) return '${d.round()} m away';
    return '${(d / 1000).toStringAsFixed(1)} km away';
  }

  /// Compass direction to the sender, e.g. "north-east". Null without a
  /// bearing. Eight points is as precise as a phone compass is worth
  /// trusting when someone is reading it while walking.
  String? get directionLabel {
    final b = bearingDegrees;
    if (b == null) return null;
    const points = [
      'north', 'north-east', 'east', 'south-east',
      'south', 'south-west', 'west', 'north-west',
    ];
    return points[(((b % 360) + 360) % 360 / 45).round() % 8];
  }

  bool get isSos => packet.category == kCategorySos;

  /// Relays this packet went through before reaching us. TTL counts down
  /// from kDefaultTtl, so 0 means it came straight from the sender.
  int get hops => kDefaultTtl - packet.ttl;
}

/// One alert as a piece of work, from the moment it lands to the moment
/// someone closes it.
///
/// [IncomingAlert] above is the transient thing: it exists to drive the
/// full-screen overlay and the notification the instant a packet arrives,
/// and it dies with the process. This is the durable counterpart, written
/// to SQLite for every alert received *and* every alert sent from this
/// phone. The distinction matters because a volunteer's queue has to
/// outlive an app restart — an SOS that vanishes when Android kills the
/// process in the background is not a work queue, it is a notification
/// that already scrolled past.
///
/// Lifecycle: open → claimed (someone is responding) → resolved. Claims
/// and resolutions arrive over the air as AckPacket / ResolvePacket, or
/// are made here on this phone. They are attributed, never authenticated
/// — see the note on kAckPacketType.
class AlertRecord {
  final int msgId;
  final int category;
  final String senderLabel;
  final String? senderName;
  final String? groupTag;
  final DateTime receivedAt;
  final int hops;

  /// True when this phone is the one that sent the alert. The sender needs
  /// this row every bit as much as a volunteer does — it is what lets their
  /// screen change from "alert sent" to "someone is responding".
  final bool mine;

  String? lostName;
  String? lostAge;
  double? latitude;
  double? longitude;

  String? claimedBy;
  DateTime? claimedAt;
  String? resolvedBy;
  int? resolvedReason;
  DateTime? resolvedAt;

  /// How far and which way the sender was, computed against this phone's
  /// own position at read time rather than stored — both phones move, so a
  /// distance frozen at receipt would be a lie within a minute.
  double? distanceMetres;
  double? bearingDegrees;

  AlertRecord({
    required this.msgId,
    required this.category,
    required this.senderLabel,
    required this.receivedAt,
    this.senderName,
    this.groupTag,
    this.hops = 0,
    this.mine = false,
    this.lostName,
    this.lostAge,
    this.latitude,
    this.longitude,
    this.claimedBy,
    this.claimedAt,
    this.resolvedBy,
    this.resolvedReason,
    this.resolvedAt,
  });

  bool get isSos => category == kCategorySos;
  bool get isResolved => resolvedAt != null;
  bool get isClaimed => claimedBy != null && !isResolved;
  bool get isOpen => !isClaimed && !isResolved;
  bool get hasLocation => latitude != null && longitude != null;

  /// True when the claim on this alert was made on this phone — the only
  /// case where "Resolve" should be the primary action rather than a
  /// second volunteer stepping on someone else's response.
  bool claimedByMe(String myMeshId) => claimedBy == myMeshId;

  String get title => isSos ? 'SOS' : 'Lost person';

  /// Who to look for, when a detail packet arrived. Null for an SOS, and
  /// for a lost-person alert whose detail packet hasn't landed yet — the
  /// two travel separately and either can arrive first.
  String? get lostSummary {
    final n = lostName;
    if (n == null || n.isEmpty) return null;
    final a = lostAge;
    return (a == null || a.isEmpty) ? n : '$n, age $a';
  }

  String? get distanceLabel {
    final d = distanceMetres;
    if (d == null) return null;
    if (d < 1000) return '${d.round()} m away';
    return '${(d / 1000).toStringAsFixed(1)} km away';
  }

  String? get directionLabel {
    final b = bearingDegrees;
    if (b == null) return null;
    const points = [
      'north', 'north-east', 'east', 'south-east',
      'south', 'south-west', 'west', 'north-west',
    ];
    return points[(((b % 360) + 360) % 360 / 45).round() % 8];
  }

  /// "4 min ago" — deliberately coarse. A volunteer triaging a queue needs
  /// to know which alert is oldest, not the second it arrived.
  String get ageLabel {
    final mins = DateTime.now().difference(receivedAt).inMinutes;
    if (mins < 1) return 'just now';
    if (mins < 60) return '$mins min ago';
    final hours = mins ~/ 60;
    if (hours < 24) return '${hours}h ago';
    return '${hours ~/ 24}d ago';
  }

  /// Sort key for the queue: unresolved before resolved, SOS before lost
  /// person, unclaimed before claimed, then oldest first. Nothing here is
  /// clever — a volunteer scanning a screen while walking needs the order
  /// to be the same every time they look at it.
  int get triageRank {
    if (isResolved) return 40;
    if (isClaimed) return isSos ? 20 : 30;
    return isSos ? 0 : 10;
  }

  Map<String, Object?> toMap() => {
        'msg_id': msgId,
        'category': category,
        'sender_label': senderLabel,
        'sender_name': senderName,
        'group_tag': groupTag,
        'received_at': receivedAt.millisecondsSinceEpoch,
        'hops': hops,
        'mine': mine ? 1 : 0,
        'lost_name': lostName,
        'lost_age': lostAge,
        'latitude': latitude,
        'longitude': longitude,
        'claimed_by': claimedBy,
        'claimed_at': claimedAt?.millisecondsSinceEpoch,
        'resolved_by': resolvedBy,
        'resolved_reason': resolvedReason,
        'resolved_at': resolvedAt?.millisecondsSinceEpoch,
      };

  static AlertRecord fromMap(Map<String, Object?> map) => AlertRecord(
        msgId: map['msg_id'] as int,
        category: map['category'] as int,
        senderLabel: map['sender_label'] as String,
        senderName: map['sender_name'] as String?,
        groupTag: map['group_tag'] as String?,
        receivedAt: DateTime.fromMillisecondsSinceEpoch(map['received_at'] as int),
        hops: (map['hops'] as int?) ?? 0,
        mine: ((map['mine'] as int?) ?? 0) == 1,
        lostName: map['lost_name'] as String?,
        lostAge: map['lost_age'] as String?,
        latitude: map['latitude'] as double?,
        longitude: map['longitude'] as double?,
        claimedBy: map['claimed_by'] as String?,
        claimedAt: _time(map['claimed_at']),
        resolvedBy: map['resolved_by'] as String?,
        resolvedReason: map['resolved_reason'] as int?,
        resolvedAt: _time(map['resolved_at']),
      );

  static DateTime? _time(Object? raw) =>
      raw == null ? null : DateTime.fromMillisecondsSinceEpoch(raw as int);
}

/// A single line in the live activity feed.
class LogEntry {
  final String text;
  final String kind; // Sent / Received / Relayed / Final hop / Warning / Demo
  final DateTime time;
  LogEntry(this.text, this.kind) : time = DateTime.now();
}

/// Fixed, literal-only icon + color palettes for lost-person avatars.
///
/// Deliberately NOT built from a dynamic codepoint (`IconData(n, ...)`) —
/// that pattern breaks under Flutter's release-mode icon tree-shaking,
/// which only keeps icons it can see referenced as constant literals.
/// A DB row just stores an index into these fixed lists.
class AvatarPalette {
  static const List<IconDataLike> icons = [
    IconDataLike('person'),
    IconDataLike('face'),
    IconDataLike('child_care'),
    IconDataLike('elderly'),
    IconDataLike('boy'),
    IconDataLike('girl'),
    IconDataLike('man'),
    IconDataLike('woman'),
  ];

  static const List<int> colors = [
    0xFFCC4125, // warm red
    0xFF2E6BA3, // blue
    0xFF1D9E75, // green
    0xFFBA7517, // amber
    0xFF6B4EA0, // purple
    0xFF457B9D, // steel blue
  ];
}

/// Tiny marker so [AvatarPalette.icons] stays a list of literal names that
/// screens map to real `Icons.*` constants via a switch — see
/// `screens/report_form_screen.dart`'s `avatarIconFor`.
class IconDataLike {
  final String name;
  const IconDataLike(this.name);
}

/// WariMesh serves two kinds of people on the same mesh: a [warkari] — a
/// pilgrim walking the Wari, who mainly needs to send an SOS and see who's
/// missing — and a [volunteer] — camp/relay staff who also need the mesh
/// diagnostics, background relay service, and activity log. They sign in
/// separately (see role_select_screen.dart) and land on different views
/// (see main.dart's AuthGate).
enum UserRole {
  warkari,
  volunteer;

  String get label => this == UserRole.warkari ? 'Warkari' : 'Volunteer';

  static UserRole fromName(String name) =>
      UserRole.values.firstWhere((r) => r.name == name, orElse: () => UserRole.volunteer);
}

/// The locally-registered person using this phone. WariMesh has no server
/// and no internet dependency, so this is deliberately not an account with
/// a password — it's an on-device identity card: who's carrying this
/// phone, so reports and mesh activity can be attributed to a person
/// instead of just a random device label. Stored only in this phone's own
/// SQLite database (see database_service.dart).
class UserProfile {
  final String name;
  final String phone;
  final UserRole role;
  final String groupOrId; // Dindi/group name for a warkari, volunteer/camp ID for a volunteer
  final String meshId; // persistent mesh identity, e.g. "W7K2M9" — see generateMeshId()
  final DateTime loggedInAt;

  /// Which kind of help point this person is currently staffing, or
  /// [kStationNone]. Only meaningful for a volunteer; a warkari is always
  /// kStationNone. Persisted so going on duty survives an app restart —
  /// a volunteer who has been at the medical tent since 5am should not
  /// have to remember to re-announce it after their phone reboots.
  final int station;

  const UserProfile({
    required this.name,
    required this.phone,
    required this.role,
    required this.groupOrId,
    required this.meshId,
    required this.loggedInAt,
    this.station = kStationNone,
  });

  UserProfile copyWith({String? groupOrId, int? station}) => UserProfile(
        name: name,
        phone: phone,
        role: role,
        groupOrId: groupOrId ?? this.groupOrId,
        meshId: meshId,
        loggedInAt: loggedInAt,
        station: station ?? this.station,
      );

  /// This person's Dindi/camp tag, for the mesh's notification-tiering
  /// decision — see dindiTagFor() and mesh_service.dart.
  String get dindiTag => dindiTagFor(groupOrId);

  Map<String, Object?> toMap() => {
        'name': name,
        'phone': phone,
        'role': role.name,
        'volunteer_id': groupOrId,
        'mesh_id': meshId,
        'logged_in_at': loggedInAt.millisecondsSinceEpoch,
        'station': station,
      };

  static UserProfile fromMap(Map<String, Object?> map) => UserProfile(
        name: map['name'] as String,
        phone: map['phone'] as String,
        role: UserRole.fromName(map['role'] as String? ?? 'volunteer'),
        groupOrId: map['volunteer_id'] as String,
        // Pre-existing rows (signed in before Mesh IDs existed) won't have
        // one yet — generate on first read rather than crash. It's saved
        // back to the DB by UserDb.current() so it becomes permanent from
        // that point on, same as any other profile's Mesh ID.
        meshId: (map['mesh_id'] as String?) ??
            generateMeshId(UserRole.fromName(map['role'] as String? ?? 'volunteer')),
        loggedInAt: DateTime.fromMillisecondsSinceEpoch(map['logged_in_at'] as int),
        station: (map['station'] as int?) ?? kStationNone,
      );
}

class LostReport {
  final int? id;
  final String name;
  final String age;
  final String description;
  final String lastSeenLocation;
  final String contactInfo;
  final int avatarIconIndex;
  final int avatarColorIndex;
  final DateTime createdAt;
  final int? msgId; // set once broadcast over the mesh
  final DateTime? broadcastAt;
  final bool found;

  const LostReport({
    this.id,
    required this.name,
    required this.age,
    required this.description,
    required this.lastSeenLocation,
    required this.contactInfo,
    required this.avatarIconIndex,
    required this.avatarColorIndex,
    required this.createdAt,
    this.msgId,
    this.broadcastAt,
    this.found = false,
  });

  LostReport copyWith({
    int? id,
    int? msgId,
    DateTime? broadcastAt,
    bool? found,
  }) {
    return LostReport(
      id: id ?? this.id,
      name: name,
      age: age,
      description: description,
      lastSeenLocation: lastSeenLocation,
      contactInfo: contactInfo,
      avatarIconIndex: avatarIconIndex,
      avatarColorIndex: avatarColorIndex,
      createdAt: createdAt,
      msgId: msgId ?? this.msgId,
      broadcastAt: broadcastAt ?? this.broadcastAt,
      found: found ?? this.found,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'age': age,
        'description': description,
        'last_seen_location': lastSeenLocation,
        'contact_info': contactInfo,
        'avatar_icon_index': avatarIconIndex,
        'avatar_color_index': avatarColorIndex,
        'created_at': createdAt.millisecondsSinceEpoch,
        'msg_id': msgId,
        'broadcast_at': broadcastAt?.millisecondsSinceEpoch,
        'found': found ? 1 : 0,
      };

  static LostReport fromMap(Map<String, Object?> map) => LostReport(
        id: map['id'] as int?,
        name: map['name'] as String,
        age: map['age'] as String,
        description: map['description'] as String,
        lastSeenLocation: map['last_seen_location'] as String,
        contactInfo: map['contact_info'] as String,
        avatarIconIndex: map['avatar_icon_index'] as int,
        avatarColorIndex: map['avatar_color_index'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        msgId: map['msg_id'] as int?,
        broadcastAt: map['broadcast_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['broadcast_at'] as int),
        found: (map['found'] as int? ?? 0) == 1,
      );
}
