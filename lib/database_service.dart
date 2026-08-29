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
  static const int _version = 4;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'warimesh.db');
    _db = await openDatabase(
      path,
      version: _version,
      onCreate: (db, version) async {
        await _createSeenMessages(db);
        await _createLostReports(db);
        await _createVolunteerProfile(db);
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
          await db.execute("ALTER TABLE volunteer_profile ADD COLUMN role TEXT NOT NULL DEFAULT 'volunteer'");
        }
      },
    );
    return _db!;
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
        logged_in_at INTEGER NOT NULL
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

  static Future<void> markSeen(MeshPacket packet) async {
    final db = await AppDatabase.instance;
    await db.insert(
      'seen_messages',
      {
        'msg_id': packet.msgId,
        'category': packet.category,
        'sender_label': packet.senderLabel,
        'ttl_at_capture': packet.ttl,
        'captured_at': DateTime.now().millisecondsSinceEpoch,
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<int> count() async {
    final db = await AppDatabase.instance;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM seen_messages');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}

// ===================== lost_reports =====================

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
    final rows = await db.query('lost_reports', orderBy: 'found ASC, created_at DESC');
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
    await db.insert(
      'volunteer_profile',
      {'id': 1, ...profile.toMap()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<UserProfile?> current() async {
    final db = await AppDatabase.instance;
    final rows = await db.query('volunteer_profile', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return null;
    return UserProfile.fromMap(rows.first);
  }

  static Future<void> clear() async {
    final db = await AppDatabase.instance;
    await db.delete('volunteer_profile', where: 'id = 1');
  }
}
