// WariMesh — local persistence.
//
// Two tables in one SQLite file:
//   seen_messages — dedup/loop-prevention ledger for the mesh protocol.
//                   Lets a phone still recognize a message it already saw
//                   after an app restart.
//   lost_reports  — the rich, local-only "who am I looking for" data that
//                   can never travel over the 13-byte mesh packet (see the
//                   note at the top of models.dart).
import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class AppDatabase {
  static Database? _db;
  static const int _version = 13;

  /// The database filename. A constant in the app; overridable only so that
  /// test files can each own their own file.
  ///
  /// `flutter test` runs test files in PARALLEL processes, and they share a
  /// databases directory. database_test.dart deletes the file to exercise
  /// onCreate while migration_test.dart seeds an old schema to exercise
  /// onUpgrade — pointed at one filename, those two races produce a suite
  /// that passes file-by-file and fails when run together, which is the
  /// most expensive kind of test failure to chase.
  static String databaseName = 'warimesh.db';

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, databaseName);
    _db = await openDatabase(
      path,
      version: _version,
      onCreate: (db, version) async {
        await _createSeenMessages(db);
        await _createLostReports(db);
        await _createVolunteerProfile(db);
        await _createKnownDindis(db);
        await _createMessages(db);
        await _createAlerts(db);
        await _createHelpPoints(db);
        await _createAppSettings(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createLostReports(db);
        }
        if (oldVersion < 3) {
          await _createVolunteerProfile(db);
        }
        if (oldVersion < 4) {
          // Two sign-in roles now share this table (see UserRole in
          // models.dart) — a pre-existing row is someone who signed in
          // before roles existed, i.e. a volunteer.
          await _addColumnIfMissing(
            db,
            'volunteer_profile',
            'role',
            "TEXT NOT NULL DEFAULT 'volunteer'",
          );
        }
        if (oldVersion < 5) {
          // Persistent Mesh ID (see generateMeshId() in models.dart). Left
          // NULL for existing rows on purpose — UserProfile.fromMap()
          // generates one on first read after upgrade and UserDb.current()
          // persists it immediately, rather than backfilling here with no
          // access to the role-aware generator.
          await _addColumnIfMissing(db, 'volunteer_profile', 'mesh_id', 'TEXT');
        }
        if (oldVersion < 6) {
          await _createKnownDindis(db);
        }
        if (oldVersion < 7) {
          await _createMessages(db);
        }
        if (oldVersion < 8) {
          await _createAlerts(db);
          // Which kind of help point this volunteer is staffing, broadcast
          // in the presence beacon. Defaults to none: a phone must never
          // claim to be a medical point because of a migration.
          await _addColumnIfMissing(
            db,
            'volunteer_profile',
            'station',
            'INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 9) {
          await _createHelpPoints(db);
        }
        if (oldVersion < 10) {
          // Self-declared Dindi Lead flag (see UserProfile.isDindiLead) —
          // the Wari Emergency Response Network. Defaults to 0 for the same
          // reason station defaults to kStationNone: a phone must never
          // claim to lead a Dindi because of a migration.
          await _addColumnIfMissing(
            db,
            'volunteer_profile',
            'is_dindi_lead',
            'INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 11) {
          // What kind of emergency an SOS is (see kSosReason* in
          // models.dart), and the sighting state of a missing-person search
          // (see kSpottedPacketType). reason defaults to
          // kSosReasonUnspecified so every alert already on this phone stays
          // exactly what it was — an SOS that didn't say why — rather than
          // being retroactively relabelled as some category nobody chose.
          await _addColumnIfMissing(
            db,
            'alerts',
            'reason',
            'INTEGER NOT NULL DEFAULT $kSosReasonUnspecified',
          );
          await _addColumnIfMissing(db, 'alerts', 'spotted_by', 'TEXT');
          await _addColumnIfMissing(db, 'alerts', 'spotted_at', 'INTEGER');
          await _addColumnIfMissing(db, 'alerts', 'spotted_lat', 'REAL');
          await _addColumnIfMissing(db, 'alerts', 'spotted_lon', 'REAL');
        }
        if (oldVersion < 12) {
          // Where a help point actually is. Arrives on an ordinary
          // LocationPacket carrying the help point's msgId — see the note
          // above kHelpPointPacketType for why the announcement itself
          // still carries no coordinates, and why this reverses an earlier
          // decision. Nullable because a volunteer's phone may have had no
          // GPS fix when they went on duty, and a help point with no
          // position is still worth knowing about.
          await _addColumnIfMissing(db, 'help_points', 'latitude', 'REAL');
          await _addColumnIfMissing(db, 'help_points', 'longitude', 'REAL');
        }
        if (oldVersion < 13) {
          await _createAppSettings(db);
        }
      },
    );
    return _db!;
  }

  /// Adds a column only when the table doesn't already have it.
  ///
  /// Every ALTER in the migration chain goes through this, because of a
  /// trap that took the app down on a real phone: the create-table helpers
  /// below describe the schema as it is TODAY, but they are also called from
  /// old migration steps (`oldVersion < 3` creates volunteer_profile). So a
  /// database old enough to hit that step gets the modern table — role,
  /// mesh_id and station included — and then the very next step tries to
  /// ALTER a `role` column that already exists. SQLite raises "duplicate
  /// column name", openDatabase aborts, and the app comes up with no
  /// persistence at all: no sign-in, no queue, nothing kept.
  ///
  /// Checking first makes each step idempotent, which also makes the order
  /// of the steps stop mattering — worth having, since they were not in
  /// version order and nobody had noticed.
  ///
  /// Reached more often than it looks like it should: Android's auto-backup
  /// can restore an old app database onto a fresh install, so "nobody still
  /// has a v2 database" is not an assumption this code gets to make.
  static Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((c) => c['name'] == column);
    if (exists) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  /// Every alert this phone has seen or sent, and where it stands.
  ///
  /// Distinct from seen_messages, which is a bare dedup ledger the relay
  /// consults and nothing more. This table is the volunteer's work queue:
  /// it has to survive an app restart, because an SOS that scrolls out of
  /// an in-memory list the moment the process dies is not a queue, it is a
  /// notification. claimed_by / resolved_by hold a Mesh ID — including this
  /// phone's own when the claim was made here.
  static Future<void> _createAlerts(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS alerts (
        msg_id INTEGER PRIMARY KEY,
        category INTEGER NOT NULL,
        sender_label TEXT NOT NULL,
        sender_name TEXT,
        group_tag TEXT,
        received_at INTEGER NOT NULL,
        hops INTEGER NOT NULL DEFAULT 0,
        mine INTEGER NOT NULL DEFAULT 0,
        lost_name TEXT,
        lost_age TEXT,
        latitude REAL,
        longitude REAL,
        claimed_by TEXT,
        claimed_at INTEGER,
        resolved_by TEXT,
        resolved_reason INTEGER,
        resolved_at INTEGER,
        -- Kept in step with the v11 ALTERs in onUpgrade. Every column added
        -- by a migration has to be added here too, or a fresh install and an
        -- upgraded install end up with different tables — and the fresh one
        -- breaks, which is the case that gets tested least. See
        -- database_test.dart, which exists because exactly that happened.
        reason INTEGER NOT NULL DEFAULT 0,
        spotted_by TEXT,
        spotted_at INTEGER,
        spotted_lat REAL,
        spotted_lon REAL
      )
    """);
  }

  /// The Wari Seva Network's storage — see [HelpPointRecord] for why this
  /// is a durable table and not just an in-memory list, same reasoning as
  /// _createAlerts above. closed_by/closed_at mirror resolved_by/resolved_at
  /// on the alerts table on purpose: a HELP_POINT_STATUS_UPDATE is the
  /// HELP_POINT equivalent of a RESOLVE.
  static Future<void> _createHelpPoints(Database db) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS help_points (
        msg_id INTEGER PRIMARY KEY,
        help_type INTEGER NOT NULL,
        sender_label TEXT NOT NULL,
        sender_name TEXT,
        received_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        hops INTEGER NOT NULL DEFAULT 0,
        mine INTEGER NOT NULL DEFAULT 0,
        status INTEGER NOT NULL DEFAULT 0,
        closed_by TEXT,
        closed_at INTEGER,
        acknowledged INTEGER NOT NULL DEFAULT 0,
        -- Kept in step with the v12 ALTERs in onUpgrade. See _createAlerts
        -- for why every migration column must be repeated here.
        latitude REAL,
        longitude REAL
      )
    """);
  }

  /// Small key-value store for app-level preferences that belong to the
  /// PHONE rather than to whoever is signed in on it — language being the
  /// first. Deliberately not a column on volunteer_profile: the language
  /// someone can read does not change when they sign out, and it has to be
  /// readable before anyone has signed in at all.
  static Future<void> _createAppSettings(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  static Future<void> _createSeenMessages(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seen_messages (
        msg_id INTEGER PRIMARY KEY,
        category INTEGER NOT NULL,
        sender_label TEXT NOT NULL,
        ttl_at_capture INTEGER NOT NULL,
        captured_at INTEGER NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _createVolunteerProfile(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS volunteer_profile (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'volunteer',
        volunteer_id TEXT NOT NULL,
        mesh_id TEXT,
        logged_in_at INTEGER NOT NULL,
        -- Kept in step with the v8/v10 ALTERs in onUpgrade. Every column
        -- added by a migration has to be added here too, or a fresh install
        -- and an upgraded install end up with different tables — and the
        -- fresh one breaks, which is the case that gets tested least.
        station INTEGER NOT NULL DEFAULT 0,
        is_dindi_lead INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // Dindi names this phone has created or joined. There's no server, so
  // this is a per-phone memory only — it makes "Create" vs "Join" a real,
  // structured choice instead of a free-text field, and lets a phone used
  // to register several people (e.g. a camp organizer's phone) offer past
  // names back for reselection instead of re-typing. A true cross-phone
  // Dindi directory needs the cloud sync bridge (still unbuilt) — Join
  // here can only offer what THIS phone has already seen.
  static Future<void> _createKnownDindis(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS known_dindis (
        name TEXT PRIMARY KEY,
        tag TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  // Dindi chat and volunteer advisories, reassembled from mesh fragments
  // (see TextHeadPacket in models.dart). msg_id is the primary key, which
  // doubles as dedup: hearing the same message relayed back from three
  // neighbours must not produce three copies in the conversation.
  static Future<void> _createMessages(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        msg_id INTEGER PRIMARY KEY,
        kind INTEGER NOT NULL,
        group_tag TEXT NOT NULL,
        sender_label TEXT NOT NULL,
        sender_name TEXT,
        body TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        outgoing INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _createLostReports(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lost_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        age TEXT NOT NULL,
        description TEXT NOT NULL,
        last_seen_location TEXT NOT NULL,
        contact_info TEXT NOT NULL,
        avatar_icon_index INTEGER NOT NULL,
        avatar_color_index INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        msg_id INTEGER,
        broadcast_at INTEGER,
        found INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }
}

// ===================== seen_messages =====================

class SeenMessagesDb {
  static Future<bool> hasSeen(int msgId) async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      'seen_messages',
      where: 'msg_id = ?',
      whereArgs: [msgId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<void> markSeen(MeshPacket packet) => markSeenRaw(
    packet.msgId,
    category: packet.category,
    senderLabel: packet.senderLabel,
    ttl: packet.ttl,
  );

  /// The generic form [markSeen] delegates to. [hasSeen] above was already
  /// keyed on msgId alone, so it works unmodified for any packet kind — only
  /// the write side was tied to [MeshPacket]. HELP_POINT reuses this same
  /// ledger for dedup/loop-prevention rather than keeping a second one; the
  /// `category` column is diagnostic only (see seen_messages' one caller,
  /// which is dedup-by-msg_id and nothing else) so a HELP_POINT packet type
  /// fits it fine.
  static Future<void> markSeenRaw(
    int msgId, {
    required int category,
    required String senderLabel,
    required int ttl,
  }) async {
    final db = await AppDatabase.instance;
    await db.insert('seen_messages', {
      'msg_id': msgId,
      'category': category,
      'sender_label': senderLabel,
      'ttl_at_capture': ttl,
      'captured_at': DateTime.now().millisecondsSinceEpoch,
      'synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<int> count() async {
    final db = await AppDatabase.instance;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM seen_messages');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}

// ===================== lost_reports =====================

/// The alert queue's storage. See [AlertRecord] for why alerts are stored
/// at all rather than just notified.
class AlertsDb {
  /// Records an alert if it's new. Deliberately does NOT overwrite an
  /// existing row: the same alert arrives repeatedly as neighbours re-air
  /// it, and clobbering the row each time would wipe a claim a volunteer
  /// had already made on it.
  static Future<void> insertIfNew(AlertRecord record) async {
    final db = await AppDatabase.instance;
    await db.insert(
      'alerts',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Fills in the "who to look for" detail, which travels as its own packet
  /// and can land after the alert it belongs to.
  static Future<void> setLostDetail(int msgId, String name, String age) async {
    final db = await AppDatabase.instance;
    await db.update(
      'alerts',
      {'lost_name': name, 'lost_age': age},
      where: 'msg_id = ?',
      whereArgs: [msgId],
    );
  }

  static Future<void> setLocation(int msgId, double lat, double lon) async {
    final db = await AppDatabase.instance;
    await db.update(
      'alerts',
      {'latitude': lat, 'longitude': lon},
      where: 'msg_id = ?',
      whereArgs: [msgId],
    );
  }

  /// Records a claim, but never over-writes an earlier one: when two
  /// volunteers claim the same alert within a few seconds of each other,
  /// the first claim heard is the one that stands on this phone. Whichever
  /// of them actually gets there first is a matter for the two humans; the
  /// mesh's job is to stop the queue flip-flopping between them.
  static Future<void> setClaim(int msgId, String meshId, DateTime at) async {
    final db = await AppDatabase.instance;
    await db.update(
      'alerts',
      {'claimed_by': meshId, 'claimed_at': at.millisecondsSinceEpoch},
      where: 'msg_id = ? AND claimed_by IS NULL',
      whereArgs: [msgId],
    );
  }

  static Future<void> setResolved(
    int msgId,
    String meshId,
    int reason,
    DateTime at,
  ) async {
    final db = await AppDatabase.instance;
    await db.update(
      'alerts',
      {
        'resolved_by': meshId,
        'resolved_reason': reason,
        'resolved_at': at.millisecondsSinceEpoch,
      },
      where: 'msg_id = ?',
      whereArgs: [msgId],
    );
  }

  /// Records a sighting of a missing person (see kSpottedPacketType).
  ///
  /// Unlike [setClaim], a later sighting deliberately DOES overwrite an
  /// earlier one — the newest sighting is the useful one, because the whole
  /// point is tracking someone who is moving. This is the opposite rule to a
  /// claim, where the first responder heard is the one that stands.
  ///
  /// Never touches latitude/longitude: those are where the report was filed
  /// from, which the search is working back from. See AlertRecord.spottedBy.
  static Future<void> setSpotted(
    int msgId,
    String meshId,
    DateTime at, {
    double? latitude,
    double? longitude,
  }) async {
    final db = await AppDatabase.instance;
    await db.update(
      'alerts',
      {
        'spotted_by': meshId,
        'spotted_at': at.millisecondsSinceEpoch,
        'spotted_lat': latitude,
        'spotted_lon': longitude,
      },
      where: 'msg_id = ?',
      whereArgs: [msgId],
    );
  }

  /// Undoes a resolution. Exists because a RESOLVE packet is unsigned and
  /// unverifiable (see kResolvePacketType) — a volunteer must always be
  /// able to say "no, this person is still missing" and put the alert back
  /// in the queue.
  static Future<void> reopen(int msgId) async {
    final db = await AppDatabase.instance;
    await db.update(
      'alerts',
      {'resolved_by': null, 'resolved_reason': null, 'resolved_at': null},
      where: 'msg_id = ?',
      whereArgs: [msgId],
    );
  }

  /// The queue, newest first. Ordering into triage order happens in the UI
  /// against [AlertRecord.triageRank], since that depends on live state.
  static Future<List<AlertRecord>> all() async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      'alerts',
      orderBy: 'received_at DESC',
      limit: 200,
    );
    return rows.map(AlertRecord.fromMap).toList();
  }
}

// ===================== help_points =====================

/// The Wari Seva Network's storage. See [HelpPointRecord] for why help
/// points are stored rather than merely notified — same reasoning as
/// [AlertsDb].
class HelpPointsDb {
  /// Records a help point if it's new. Deliberately does NOT overwrite an
  /// existing row — the same announcement arrives repeatedly as neighbours
  /// re-air it (see kHelpPointAirtime in mesh_service.dart), and clobbering
  /// the row each time would wipe a status change or an "I'm going there"
  /// someone already recorded locally.
  static Future<void> insertIfNew(HelpPointRecord record) async {
    final db = await AppDatabase.instance;
    await db.insert(
      'help_points',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> setStatus(
    int msgId,
    int status, {
    String? closedBy,
    DateTime? closedAt,
  }) async {
    final db = await AppDatabase.instance;
    await db.update(
      'help_points',
      {
        'status': status,
        'closed_by': closedBy,
        'closed_at': closedAt?.millisecondsSinceEpoch,
      },
      where: 'msg_id = ?',
      whereArgs: [msgId],
    );
  }

  /// Fills in where a help point is, from a LocationPacket that arrived
  /// carrying its msgId. Separate from insertIfNew because the announcement
  /// and its position travel as two packets and either can land first.
  static Future<void> setLocation(int msgId, double lat, double lon) async {
    final db = await AppDatabase.instance;
    await db.update(
      'help_points',
      {'latitude': lat, 'longitude': lon},
      where: 'msg_id = ?',
      whereArgs: [msgId],
    );
  }

  static Future<void> setAcknowledged(int msgId, bool value) async {
    final db = await AppDatabase.instance;
    await db.update(
      'help_points',
      {'acknowledged': value ? 1 : 0},
      where: 'msg_id = ?',
      whereArgs: [msgId],
    );
  }

  /// Drops rows that expired more than a day ago. Run at bootstrap and
  /// whenever the list is reloaded — see the note on [AlertRecord] for why
  /// an alert is never deleted (a resolved SOS is still history worth
  /// keeping), but a help point is different: once it is stale there is
  /// nothing useful left to show and no reason to keep it forever. The
  /// one-day grace period, rather than deleting the instant it expires, is
  /// just so a volunteer who reopens the app minutes after a slightly-late
  /// expiry still sees what was there.
  static Future<void> reapExpired() async {
    final db = await AppDatabase.instance;
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 1))
        .millisecondsSinceEpoch;
    await db.delete(
      'help_points',
      where: 'expires_at < ?',
      whereArgs: [cutoff],
    );
  }

  /// The whole table, newest first. Filtering into "active now" happens in
  /// the UI/mesh layer against [HelpPointRecord.isActive], since expiry is a
  /// live computation, not something worth re-querying for.
  static Future<List<HelpPointRecord>> all() async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      'help_points',
      orderBy: 'received_at DESC',
      limit: 200,
    );
    return rows.map(HelpPointRecord.fromMap).toList();
  }
}

// ===================== app_settings =====================

/// Phone-level preferences. See _createAppSettings for why these are not
/// hung off the signed-in profile.
class SettingsDb {
  static const String keyLanguage = 'language';

  static Future<String?> get(String key) async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  static Future<void> set(String key, String value) async {
    final db = await AppDatabase.instance;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

class LostReportsDb {
  static Future<int> insert(LostReport report) async {
    final db = await AppDatabase.instance;
    final map = report.toMap()..remove('id');
    return db.insert('lost_reports', map);
  }

  static Future<void> update(LostReport report) async {
    if (report.id == null) return;
    final db = await AppDatabase.instance;
    await db.update(
      'lost_reports',
      report.toMap(),
      where: 'id = ?',
      whereArgs: [report.id],
    );
  }

  static Future<void> setFound(int id, bool found) async {
    final db = await AppDatabase.instance;
    await db.update(
      'lost_reports',
      {'found': found ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> setBroadcast(int id, int msgId, DateTime at) async {
    final db = await AppDatabase.instance;
    await db.update(
      'lost_reports',
      {'msg_id': msgId, 'broadcast_at': at.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> delete(int id) async {
    final db = await AppDatabase.instance;
    await db.delete('lost_reports', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<LostReport>> all() async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      'lost_reports',
      orderBy: 'found ASC, created_at DESC',
    );
    return rows.map(LostReport.fromMap).toList();
  }
}

// ===================== volunteer_profile =====================
//
// Single-row table (id is always 1) — this phone belongs to whichever
// person (warkari or volunteer — see UserRole) is currently signed in,
// one at a time.

class UserDb {
  static Future<void> save(UserProfile profile) async {
    final db = await AppDatabase.instance;
    await db.insert('volunteer_profile', {
      'id': 1,
      ...profile.toMap(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<UserProfile?> current() async {
    final db = await AppDatabase.instance;
    final rows = await db.query('volunteer_profile', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return null;
    final profile = UserProfile.fromMap(rows.first);
    // A pre-existing row from before Mesh IDs existed gets one generated on
    // read (see UserProfile.fromMap) — persist it immediately so it's
    // permanent from here on, not regenerated on the next launch.
    if (rows.first['mesh_id'] == null) {
      await save(profile);
    }
    return profile;
  }

  static Future<void> clear() async {
    final db = await AppDatabase.instance;
    await db.delete('volunteer_profile', where: 'id = 1');
  }
}

// ===================== known_dindis =====================
//
// This phone's own memory of Dindi names it has created or joined — see
// the note on _createKnownDindis above for why this can't be a real
// cross-phone directory yet.

class KnownDindisDb {
  static Future<void> remember(String name) async {
    final db = await AppDatabase.instance;
    await db.insert('known_dindis', {
      'name': name,
      'tag': dindiTagFor(name),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<String>> all() async {
    final db = await AppDatabase.instance;
    final rows = await db.query('known_dindis', orderBy: 'created_at DESC');
    return rows.map((r) => r['name'] as String).toList();
  }
}

// ===================== messages =====================
//
// One row per text message this phone has sent or fully reassembled. See
// the note on _createMessages for why msg_id is the primary key.

class MessagesDb {
  /// Stores a message, ignoring it if that msgId is already known — the
  /// same message arrives repeatedly as neighbours relay it.
  /// Returns true if this was genuinely new.
  static Future<bool> insertIfNew(MeshTextMessage message) async {
    final db = await AppDatabase.instance;
    final id = await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return id != 0;
  }

  /// Conversation for one Dindi, plus every announcement regardless of
  /// group — an advisory is meant for everyone in range, so it appears in
  /// whichever Dindi's thread the person is reading.
  static Future<List<MeshTextMessage>> forGroup(String groupTag) async {
    final db = await AppDatabase.instance;
    final rows = await db.query(
      'messages',
      where: 'group_tag = ? OR kind = ?',
      whereArgs: [groupTag, kTextKindAnnouncement],
      orderBy: 'created_at ASC',
    );
    return rows.map(MeshTextMessage.fromMap).toList();
  }

  static Future<void> clear() async {
    final db = await AppDatabase.instance;
    await db.delete('messages');
  }
}
