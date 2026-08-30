// Migration tests — can a database written by an OLD build of the app be
// opened by this one?
//
// This runs in its own file, and therefore its own process, on purpose:
// AppDatabase caches a single open handle for the lifetime of the process,
// so the precondition (what is on disk before the first open) can only be
// set up once. database_test.dart owns the fresh-install case; this file
// owns the upgrade case.
//
// It exists because of a bug that took the app down on a real phone. The
// create-table helpers describe today's schema, but `oldVersion < 3` also
// calls one of them — so a sufficiently old database got the modern
// volunteer_profile table (role, mesh_id and station included), and the next
// migration step then tried to ALTER in a `role` column that was already
// there. SQLite raised "duplicate column name: role", openDatabase aborted,
// and the app started with no persistence whatsoever: sign-in failed and
// nothing was kept.
//
// The reason this is not a theoretical case: Android's auto-backup can
// restore an old app database onto what is otherwise a clean install. The
// phone this was found on had been freshly uninstalled and reinstalled, and
// still came up carrying a database from an early build.
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:warimesh/database_service.dart';
import 'package:warimesh/models.dart';

/// seen_messages as an old build wrote it. Deliberately spelled out rather
/// than reusing the app's own helper — the point is to reproduce a database
/// the app can no longer produce, and a fixture built from today's CREATE
/// TABLE statements would prove nothing.
const String _legacySeenMessages = '''
  CREATE TABLE seen_messages (
    msg_id INTEGER PRIMARY KEY,
    category INTEGER NOT NULL,
    sender_label TEXT NOT NULL,
    ttl_at_capture INTEGER NOT NULL,
    captured_at INTEGER NOT NULL,
    synced INTEGER NOT NULL DEFAULT 0
  )
''';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Its own file: `flutter test` runs test files in parallel, and this
    // one and the other database test both rewrite what is on disk before
    // the first open. Sharing a filename makes them race.
    AppDatabase.databaseName = 'warimesh_migration_test.db';

    final path = p.join(await databaseFactory.getDatabasesPath(), AppDatabase.databaseName);
    await databaseFactory.deleteDatabase(path);

    // Version 2, which is what makes this bite. volunteer_profile did not
    // exist yet at v2, so the next open runs `oldVersion < 3` and creates it
    // from today's CREATE TABLE — role, mesh_id and station already present —
    // and then `oldVersion < 4` tries to ALTER in a `role` column that is
    // already there. Seeding a v3 database instead skips that first step
    // entirely and the bug goes into hiding, which is exactly what the first
    // version of this test did.
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          await db.execute(_legacySeenMessages);
          await db.insert('seen_messages', {
            'msg_id': 12345,
            'category': kCategorySos,
            'sender_label': 'W7K2M9',
            'ttl_at_capture': 2,
            'captured_at': DateTime.now().millisecondsSinceEpoch,
          });
        },
      ),
    );
    await legacy.close();
  });

  test('a v2 database opens without throwing', () async {
    // The regression itself. This threw DatabaseException("duplicate column
    // name: role") and left the app with no database at all.
    await expectLater(AppDatabase.instance, completes);
  });

  test('an upgraded database accepts a sign-in using every new column', () async {
    // The user-visible symptom on the phone: signing in did nothing, because
    // the database behind it had failed to open at all.
    await UserDb.save(UserProfile(
      name: 'Sunita Kale',
      phone: '555-0100',
      role: UserRole.volunteer,
      groupOrId: 'Camp 4',
      meshId: 'V7K2M9',
      loggedInAt: DateTime.now(),
      station: kStationMedical,
    ));

    final restored = (await UserDb.current())!;
    expect(restored.name, 'Sunita Kale');
    expect(restored.role, UserRole.volunteer);
    expect(restored.meshId, 'V7K2M9');
    expect(restored.station, kStationMedical);
  });

  test('history written by the old build survives the upgrade', () async {
    // A migration that silently dropped the dedup ledger would make every
    // alert the phone had already seen look new again.
    expect(await SeenMessagesDb.hasSeen(12345), isTrue);
    expect(await SeenMessagesDb.count(), 1);
  });

  test('tables introduced after v3 exist and are usable', () async {
    await AlertsDb.insertIfNew(AlertRecord(
      msgId: 777,
      category: kCategorySos,
      senderLabel: 'W7K2M9',
      receivedAt: DateTime.now(),
    ));
    expect((await AlertsDb.all()).any((a) => a.msgId == 777), isTrue);
  });

  test('help_points (introduced at v9) exists on a database upgraded from v2', () async {
    // Same failure mode this whole file guards against, one migration step
    // later: a database that never saw v9's onUpgrade branch must still end
    // up with a usable help_points table.
    await HelpPointsDb.insertIfNew(HelpPointRecord(
      msgId: 888,
      helpType: kStationMedical,
      senderLabel: 'V7K2M9',
      receivedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    ));
    expect((await HelpPointsDb.all()).any((h) => h.msgId == 888), isTrue);
  });
}
