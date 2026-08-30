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
import 'package:warimesh/l10n/app_strings.dart';
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
      p.join(
        await databaseFactory.getDatabasesPath(),
        AppDatabase.databaseName,
      ),
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
      await UserDb.save(
        UserProfile(
          name: 'Aarav Patil',
          phone: '555-0101',
          role: UserRole.warkari,
          groupOrId: 'Sant Tukaram Dindi',
          meshId: 'W4B2XY',
          loggedInAt: DateTime.now(),
        ),
      );

      final restored = (await UserDb.current())!;
      expect(restored.role, UserRole.warkari);
      expect(restored.station, kStationNone);
    });

    test(
      'copyWith persists a station change without disturbing identity',
      () async {
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
      },
    );

    test('a fresh database accepts a Dindi Lead flag', () async {
      final profile = UserProfile(
        name: 'Rahul Jadhav',
        phone: '555-0200',
        role: UserRole.warkari,
        groupOrId: 'Dindi 127',
        meshId: 'W4B2XY',
        loggedInAt: DateTime.now(),
        isDindiLead: true,
      );
      await UserDb.save(profile);

      final restored = (await UserDb.current())!;
      expect(restored.isDindiLead, isTrue);
      expect(restored.role, UserRole.warkari);
    });

    test(
      'copyWith toggles isDindiLead without disturbing station or identity',
      () async {
        final original = UserProfile(
          name: 'Rahul Jadhav',
          phone: '555-0200',
          role: UserRole.warkari,
          groupOrId: 'Dindi 127',
          meshId: 'W4B2XY',
          loggedInAt: DateTime.now(),
        );
        await UserDb.save(original);
        await UserDb.save(original.copyWith(isDindiLead: true));

        var restored = (await UserDb.current())!;
        expect(restored.isDindiLead, isTrue);

        // Switching Dindi (the regression the copyWith fix in warkari_shell.dart
        // guards against) must not silently un-declare the Lead.
        await UserDb.save(restored.copyWith(groupOrId: 'Dindi 88'));
        restored = (await UserDb.current())!;
        expect(restored.isDindiLead, isTrue);
        expect(restored.groupOrId, 'Dindi 88');
      },
    );
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
      var stored = (await AlertsDb.all()).firstWhere(
        (a) => a.msgId == record.msgId,
      );
      expect(stored.claimedBy, 'V4B2XY');
      expect(stored.isClaimed, isTrue);

      await AlertsDb.setResolved(
        record.msgId,
        'V4B2XY',
        kResolveFound,
        DateTime.now(),
      );
      stored = (await AlertsDb.all()).firstWhere(
        (a) => a.msgId == record.msgId,
      );
      expect(stored.isResolved, isTrue);
      expect(stored.resolvedReason, kResolveFound);

      await AlertsDb.reopen(record.msgId);
      stored = (await AlertsDb.all()).firstWhere(
        (a) => a.msgId == record.msgId,
      );
      expect(stored.isResolved, isFalse);
      // Reopening restores the queue entry, and the claim on it stands — the
      // volunteer who was responding did not stop responding.
      expect(stored.claimedBy, 'V4B2XY');
    });

    test(
      're-hearing an alert never clobbers a claim already made on it',
      () async {
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
      },
    );

    test('the first claim heard wins over a later one', () async {
      await AlertsDb.insertIfNew(
        AlertRecord(
          msgId: 7,
          category: kCategorySos,
          senderLabel: 'W7K2M9',
          receivedAt: DateTime.now(),
        ),
      );
      await AlertsDb.setClaim(7, 'V1AAAA', DateTime.now());
      await AlertsDb.setClaim(7, 'V2BBBB', DateTime.now());

      final stored = (await AlertsDb.all()).firstWhere((a) => a.msgId == 7);
      expect(stored.claimedBy, 'V1AAAA');
    });

    test(
      'a detail packet arriving after its alert fills in who to look for',
      () async {
        await AlertsDb.insertIfNew(
          AlertRecord(
            msgId: 99,
            category: kCategoryLostPerson,
            senderLabel: 'W7K2M9',
            receivedAt: DateTime.now(),
          ),
        );
        await AlertsDb.setLostDetail(99, 'Aarav', '8');
        await AlertsDb.setLocation(99, 17.679076, 75.323997);

        final stored = (await AlertsDb.all()).firstWhere((a) => a.msgId == 99);
        expect(stored.lostSummary, 'Aarav, age 8');
        expect(stored.hasLocation, isTrue);
        expect(stored.latitude, closeTo(17.679076, 1e-9));
      },
    );
  });

  group('app_settings — language choice', () {
    test('a fresh database stores and returns the chosen language', () async {
      expect(await SettingsDb.get(SettingsDb.keyLanguage), isNull);

      await SettingsDb.set(SettingsDb.keyLanguage, kLanguageEnglish);
      expect(await SettingsDb.get(SettingsDb.keyLanguage), kLanguageEnglish);

      // Changing it replaces rather than accumulating rows.
      await SettingsDb.set(SettingsDb.keyLanguage, kLanguageMarathi);
      expect(await SettingsDb.get(SettingsDb.keyLanguage), kLanguageMarathi);
    });

    test('an unknown or missing code falls back to Marathi', () async {
      // The default has to survive a corrupt value as well as a missing
      // one — nobody should get an app with no strings at all.
      expect(appStringsForCode(null).languageCode, kLanguageMarathi);
      expect(appStringsForCode('zz').languageCode, kLanguageMarathi);
      expect(
        appStringsForCode(kLanguageEnglish).languageCode,
        kLanguageEnglish,
      );
    });

    test('both languages implement the whole contract', () {
      // Guards the promise that switching is one call and not a rewrite: if
      // either class ever falls behind, this is where it shows up rather
      // than as a crash on a phone in a field.
      for (final lang in const <AppStrings>[
        MarathiStrings(),
        EnglishStrings(),
      ]) {
        expect(lang.languageName, isNotEmpty);
        expect(lang.sosSend, isNotEmpty);
        expect(lang.dindiLead, isNotEmpty);
        expect(lang.station(kStationMedical), isNotEmpty);
        expect(lang.sosReason(kSosReasonMedical), isNotEmpty);
        expect(lang.helpStatus(kHelpStatusOpen), isNotEmpty);
        expect(lang.distance(240), isNotEmpty);
        expect(lang.direction(45), isNotEmpty);
        expect(lang.whereLabel(hasLocation: false), isNotEmpty);
      }
    });
  });

  group('alerts table — SOS reason and sightings', () {
    test('a fresh database accepts an SOS reason and reads it back', () async {
      await AlertsDb.insertIfNew(
        AlertRecord(
          msgId: 5001,
          category: kCategorySos,
          senderLabel: 'W7K2M9',
          groupTag: 'AB',
          receivedAt: DateTime.now(),
          reason: kSosReasonMedical,
        ),
      );
      final stored = (await AlertsDb.all()).firstWhere((a) => a.msgId == 5001);
      expect(stored.reason, kSosReasonMedical);
      expect(stored.reasonLabel, 'Medical');
    });

    test('an alert stored without a reason survives as unspecified', () async {
      await AlertsDb.insertIfNew(
        AlertRecord(
          msgId: 5002,
          category: kCategorySos,
          senderLabel: 'W7K2M9',
          receivedAt: DateTime.now(),
        ),
      );
      final stored = (await AlertsDb.all()).firstWhere((a) => a.msgId == 5002);
      expect(stored.reason, kSosReasonUnspecified);
      expect(stored.reasonLabel, isNull);
    });

    test(
      'a sighting is recorded without disturbing the report location',
      () async {
        await AlertsDb.insertIfNew(
          AlertRecord(
            msgId: 5003,
            category: kCategoryLostPerson,
            senderLabel: 'W7K2M9',
            receivedAt: DateTime.now(),
            latitude: 17.679076,
            longitude: 75.323997,
          ),
        );
        await AlertsDb.setSpotted(
          5003,
          'V4B2XY',
          DateTime.now(),
          latitude: 18.5,
          longitude: 73.85,
        );

        final stored = (await AlertsDb.all()).firstWhere(
          (a) => a.msgId == 5003,
        );
        expect(stored.isSpotted, isTrue);
        expect(stored.spottedBy, 'V4B2XY');
        expect(stored.spottedLatitude, closeTo(18.5, 1e-9));
        // The whole point: where the report was FILED from is untouched, so
        // the search still knows where to work back from.
        expect(stored.latitude, closeTo(17.679076, 1e-9));
      },
    );

    test('a later sighting replaces an earlier one', () async {
      // Opposite rule to a claim, and deliberately so — the newest sighting
      // of someone who is moving is the useful one.
      await AlertsDb.insertIfNew(
        AlertRecord(
          msgId: 5004,
          category: kCategoryLostPerson,
          senderLabel: 'W7K2M9',
          receivedAt: DateTime.now(),
        ),
      );
      await AlertsDb.setSpotted(5004, 'V1AAAA', DateTime.now());
      await AlertsDb.setSpotted(5004, 'V2BBBB', DateTime.now());

      final stored = (await AlertsDb.all()).firstWhere((a) => a.msgId == 5004);
      expect(stored.spottedBy, 'V2BBBB');
    });

    test(
      'a sighting with no GPS stores no coordinates rather than zeros',
      () async {
        await AlertsDb.insertIfNew(
          AlertRecord(
            msgId: 5005,
            category: kCategoryLostPerson,
            senderLabel: 'W7K2M9',
            receivedAt: DateTime.now(),
          ),
        );
        await AlertsDb.setSpotted(5005, 'V4B2XY', DateTime.now());

        final stored = (await AlertsDb.all()).firstWhere(
          (a) => a.msgId == 5005,
        );
        expect(stored.isSpotted, isTrue);
        expect(stored.hasSpottedLocation, isFalse);
        expect(stored.spottedLatitude, isNull);
      },
    );

    test(
      're-hearing an alert never clobbers a sighting already recorded',
      () async {
        final record = AlertRecord(
          msgId: 5006,
          category: kCategoryLostPerson,
          senderLabel: 'W7K2M9',
          receivedAt: DateTime.now(),
        );
        await AlertsDb.insertIfNew(record);
        await AlertsDb.setSpotted(5006, 'V4B2XY', DateTime.now());
        await AlertsDb.insertIfNew(record); // the sender re-airs it all airtime

        final stored = (await AlertsDb.all()).firstWhere(
          (a) => a.msgId == 5006,
        );
        expect(stored.spottedBy, 'V4B2XY');
      },
    );
  });

  group('help_points table', () {
    HelpPointRecord record(
      int msgId, {
      int helpType = kStationMedical,
      bool mine = false,
    }) => HelpPointRecord(
      msgId: msgId,
      helpType: helpType,
      senderLabel: 'V7K2M9',
      senderName: 'Sunita',
      receivedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
      mine: mine,
    );

    test('a fresh database accepts a help point announcement', () async {
      await HelpPointsDb.insertIfNew(record(1));
      final stored = (await HelpPointsDb.all()).firstWhere((h) => h.msgId == 1);
      expect(stored.helpType, kStationMedical);
      expect(stored.isOpen, isTrue);
      expect(stored.isActive, isTrue);
    });

    test(
      'closing a help point sets status and closedBy, and it drops out of active',
      () async {
        await HelpPointsDb.insertIfNew(record(2));
        await HelpPointsDb.setStatus(
          2,
          kHelpStatusClosed,
          closedBy: 'V7K2M9',
          closedAt: DateTime.now(),
        );

        final stored = (await HelpPointsDb.all()).firstWhere(
          (h) => h.msgId == 2,
        );
        expect(stored.isClosed, isTrue);
        expect(stored.closedBy, 'V7K2M9');
        expect(stored.isActive, isFalse);
      },
    );

    test(
      're-hearing the same announcement never clobbers a status already set',
      () async {
        // Same reasoning as the alerts-table test above: the sender re-airs
        // the announcement for its whole airtime, so insertIfNew runs
        // repeatedly for the same help point.
        await HelpPointsDb.insertIfNew(record(3));
        await HelpPointsDb.setStatus(3, kHelpStatusLimited);
        await HelpPointsDb.insertIfNew(record(3));

        final stored = (await HelpPointsDb.all()).firstWhere(
          (h) => h.msgId == 3,
        );
        expect(stored.isLimited, isTrue);
      },
    );

    test('"I\'m going there" persists locally', () async {
      await HelpPointsDb.insertIfNew(record(4));
      await HelpPointsDb.setAcknowledged(4, true);
      final stored = (await HelpPointsDb.all()).firstWhere((h) => h.msgId == 4);
      expect(stored.acknowledged, isTrue);
    });

    test('reapExpired drops only what expired more than a day ago', () async {
      final fresh = HelpPointRecord(
        msgId: 5,
        helpType: kStationWater,
        senderLabel: 'V7K2M9',
        receivedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      final longExpired = HelpPointRecord(
        msgId: 6,
        helpType: kStationWater,
        senderLabel: 'V7K2M9',
        receivedAt: DateTime.now().subtract(const Duration(days: 3)),
        expiresAt: DateTime.now().subtract(const Duration(days: 2)),
      );
      await HelpPointsDb.insertIfNew(fresh);
      await HelpPointsDb.insertIfNew(longExpired);
      await HelpPointsDb.reapExpired();

      final ids = (await HelpPointsDb.all()).map((h) => h.msgId).toSet();
      expect(ids.contains(5), isTrue);
      expect(ids.contains(6), isFalse);
    });
  });
}
