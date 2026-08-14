// WariMesh — shared data models + the mesh packet protocol.
//
// Packet protocol (13 bytes, carried as BLE manufacturer data):
//   [0]     packetType   (always 1 = ALERT, reserved for future packet kinds)
//   [1]     ttl          (hop budget; each relay decrements by 1)
//   [2..5]  msgId        (uint32, random per send; dedup + loop prevention)
//   [6]     category     (0 = SOS, 1 = Lost Person)
//   [7..12] senderLabel  (6 ASCII chars, e.g. "DEV482")
//
// This 13-byte packet is intentionally tiny — it's what can hop phone to
// phone over BLE advertising with no internet and no pairing. A name,
// description or photo can never ride the mesh itself: that richer data
// (LostReport below) lives only on the reporting phone's own SQLite
// database. What travels over the mesh is a lightweight "look out for
// this" beacon; the human details are meant to sync separately once a
// phone reaches internet or a camp coordinator — that sync isn't built
// yet, so today a LostReport is local-only until you show someone the
// phone directly.

import 'dart:convert';
import 'dart:typed_data';

const int kManufacturerId = 0xFFFF; // BT SIG "reserved for testing" ID — fine for a prototype, not for shipped hardware.
const int kPacketType = 1;
const int kDefaultTtl = 2;
const int kPacketLength = 13;
const int kCategorySos = 0;
const int kCategoryLostPerson = 1;

String categoryLabel(int category) =>
    category == kCategorySos ? 'SOS' : 'Lost Person';

class MeshPacket {
  final int ttl;
  final int msgId;
  final int category;
  final String senderLabel;

  MeshPacket({
    required this.ttl,
    required this.msgId,
    required this.category,
    required this.senderLabel,
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
    return MeshPacket(
      ttl: ttl,
      msgId: msgId,
      category: category,
      senderLabel: label,
    );
  }

  /// The packet this device re-advertises after deciding to relay: same
  /// identity (msgId/category/sender), TTL down by one hop.
  MeshPacket relayed() => MeshPacket(
        ttl: ttl - 1,
        msgId: msgId,
        category: category,
        senderLabel: senderLabel,
      );
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
