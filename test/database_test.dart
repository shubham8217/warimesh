// Schema tests — does a freshly created database actually accept the rows
// the app writes into it?
//
// These exist because of a real bug that reached a phone. The station column
// (see kStationNone in models.dart) was added to volunteer_profile in the
// v7→v8 migration, but not to the CREATE TABLE in onCreate. Every phone
// upgrading from v7 got the column; every *fresh install* did not, and since
// UserProfile.toMap() always writes 'station', signing in failed outright on
// a clean install with "no such column: station".
//
// That's the failure mode worth guarding: onCreate and onUpgrade drifting
// apart. Upgrades get exercised constantly during development, because the
// developer's phone already has a database. The fresh-install path is the
// one nobody sees until someone installs the app for the first time — which
// is to say, every real user.
//
// Like widget_test.dart, this runs against sqflite_common_ffi rather than a
// platform channel, so the SQLite here is real.
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:warimesh/database_service.dart';
import 'package:warimesh/models.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Its own file: `flutter test` runs test files in parallel, and this
    // one and the other database test both rewrite what is on disk before
    // the first open. Sharing a filename makes them race.
    AppDatabase.databaseName = 'warimesh_fresh_test.db';

    // Delete the database file first, so onCreate genuinely runs. Without
    // this the file left behind by a previous test run is reused, the
    // CREATE TABLE statements never execute again, and the whole point of
    // this file evaporates — which is exactly what happened the first time
    // these tests were written: they passed against the very schema bug
    // they were added to catch.
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), AppDatabase.databaseName),
    );
  });

  setUp(() async {
    await UserDb.clear();
  });

  group('volunteer_profile', () {
    test('a fresh database accepts a full profile, station included', () async {
      final profile = UserProfile(
        name: 'Sunita Kale',
        phone: '555-0100',
        role: UserRole.volunteer,
        groupOrId: 'Camp 4',
        meshId: 'V7K2M9',
        loggedInAt: DateTime.now(),
        station: kStationMedical,
      );

      // The exact call sign-in makes. It threw on a clean install.
      await UserDb.save(profile);

      final restored = (await UserDb.current())!;
      expect(restored.name, 'Sunita Kale');
      expect(restored.role, UserRole.volunteer);
      expect(restored.meshId, 'V7K2M9');
      expect(restored.station, kStationMedical);
    });

    test('a warkari round-trips with no station', () async {
      await UserDb.save(UserProfile(
        name: 'Aarav Patil',
        phone: '555-0101',
        role: UserRole.warkari,
        groupOrId: 'Sant Tukaram Dindi',
        meshId: 'W4B2XY',
        loggedInAt: DateTime.now(),
      ));

      final restored = (await UserDb.current())!;
      expect(restored.role, UserRole.warkari);
      expect(restored.station, kStationNone);
    });

    test('copyWith persists a station change without disturbing identity', () async {
      final original = UserProfile(
        name: 'Sunita Kale',
        phone: '555-0100',
        role: UserRole.volunteer,
        groupOrId: 'Camp 4',
        meshId: 'V7K2M9',
        loggedInAt: DateTime.now(),
      );
      await UserDb.save(original);
      await UserDb.save(original.copyWith(station: kStationWater));

      final restored = (await UserDb.current())!;
      expect(restored.station, kStationWater);
      // The Mesh ID must survive going on duty — it is this phone's identity
      // on the air, and regenerating it would orphan every alert it sent.
      expect(restored.meshId, 'V7K2M9');
    });
  });

  group('alerts table', () {
    test('a fresh database accepts an alert and its lifecycle', () async {
      final record = AlertRecord(
        msgId: 3141592653,
        category: kCategorySos,
        senderLabel: 'W7K2M9',
        senderName: 'Aarav',
        groupTag: 'AB',
        receivedAt: DateTime.now(),
        hops: 1,
      );
      await AlertsDb.insertIfNew(record);

      await AlertsDb.setClaim(record.msgId, 'V4B2XY', DateTime.now());
      var stored = (await AlertsDb.all()).firstWhere((a) => a.msgId == record.msgId);
      expect(stored.claimedBy, 'V4B2XY');
      expect(stored.isClaimed, isTrue);

      await AlertsDb.setResolved(record.msgId, 'V4B2XY', kResolveFound, DateTime.now());
      stored = (await AlertsDb.all()).firstWhere((a) => a.msgId == record.msgId);
      expect(stored.isResolved, isTrue);
      expect(stored.resolvedReason, kResolveFound);

      await AlertsDb.reopen(record.msgId);
      stored = (await AlertsDb.all()).firstWhere((a) => a.msgId == record.msgId);
      expect(stored.isResolved, isFalse);
      // Reopening restores the queue entry, and the claim on it stands — the
      // volunteer who was responding did not stop responding.
      expect(stored.claimedBy, 'V4B2XY');
    });

    test('re-hearing an alert never clobbers a claim already made on it', () async {
      // The case this protects: neighbours re-air the same alert for its
      // whole airtime, so insertIfNew runs repeatedly for one incident. If
      // it overwrote, a volunteer's claim would be wiped seconds after they
      // made it and the alert would look unanswered again.
      final record = AlertRecord(
        msgId: 42,
        category: kCategoryLostPerson,
        senderLabel: 'W7K2M9',
        receivedAt: DateTime.now(),
      );
      await AlertsDb.insertIfNew(record);
      await AlertsDb.setClaim(42, 'V4B2XY', DateTime.now());
      await AlertsDb.insertIfNew(record);

      final stored = (await AlertsDb.all()).firstWhere((a) => a.msgId == 42);
      expect(stored.claimedBy, 'V4B2XY');
    });

    test('the first claim heard wins over a later one', () async {
      await AlertsDb.insertIfNew(AlertRecord(
        msgId: 7,
        category: kCategorySos,
        senderLabel: 'W7K2M9',
        receivedAt: DateTime.now(),
      ));
      await AlertsDb.setClaim(7, 'V1AAAA', DateTime.now());
      await AlertsDb.setClaim(7, 'V2BBBB', DateTime.now());

      final stored = (await AlertsDb.all()).firstWhere((a) => a.msgId == 7);
      expect(stored.claimedBy, 'V1AAAA');
    });

    test('a detail packet arriving after its alert fills in who to look for', () async {
      await AlertsDb.insertIfNew(AlertRecord(
        msgId: 99,
        category: kCategoryLostPerson,
        senderLabel: 'W7K2M9',
        receivedAt: DateTime.now(),
      ));
      await AlertsDb.setLostDetail(99, 'Aarav', '8');
      await AlertsDb.setLocation(99, 17.679076, 75.323997);

      final stored = (await AlertsDb.all()).firstWhere((a) => a.msgId == 99);
      expect(stored.lostSummary, 'Aarav, age 8');
      expect(stored.hasLocation, isTrue);
      expect(stored.latitude, closeTo(17.679076, 1e-9));
    });
  });
}
