// The volunteer's network overview must not lie.
//
// Every number on that dashboard is a claim about the world — "twelve
// Dindis are around you", "eight Dindi Leads are here" — and a volunteer
// deciding where to walk will act on it. The two ways a mesh dashboard
// goes wrong are inflation (the same phone or Dindi counted once per path
// it arrived by) and overreach (presenting what one phone can hear as a
// census of the Wari). These tests pin the first; the wording in
// app_strings.dart handles the second.
//
// See DindiSummary and WariNetworkStats in mesh_service.dart.
import 'package:flutter_test/flutter_test.dart';

import 'package:warimesh/mesh_service.dart';
import 'package:warimesh/models.dart';

void main() {
  /// A volunteer phone that has heard nothing yet. Identity is set through
  /// the test seam rather than bootstrap(), which would need a BLE stack.
  MeshService volunteerPhone() {
    final mesh = MeshService();
    mesh.debugSetIdentity(
      meshId: 'V7K2M9',
      groupTag: '--', // a volunteer at a camp, not walking with a Dindi
      role: UserRole.volunteer,
      isLead: false,
    );
    return mesh;
  }

  PresencePacket person(
    String meshId,
    String groupTag, {
    String name = 'Aarav',
    bool lead = false,
    int station = kStationNone,
  }) => PresencePacket(
    meshId: meshId,
    groupTag: groupTag,
    name: name,
    station: station,
    isDindiLead: lead,
  );

  group('Dindi discovery and deduplication', () {
    test('counts each Dindi once however many of its phones are heard', () {
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      // Five phones, two Dindis.
      mesh.debugIngestPresence(person('W11111', 'AG'));
      mesh.debugIngestPresence(person('W22222', 'AG'));
      mesh.debugIngestPresence(person('W33333', 'AG'));
      mesh.debugIngestPresence(person('W44444', 'ZQ'));
      mesh.debugIngestPresence(person('W55555', 'ZQ'));

      expect(mesh.knownDindis.length, 2);
      expect(mesh.wariNetwork.dindis, 2);
    });

    test('the same phone heard repeatedly is still one participant', () {
      // The case that inflates a dashboard: a beacon re-aired continuously
      // and arriving over several paths.
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      for (var i = 0; i < 20; i++) {
        mesh.debugIngestPresence(person('W11111', 'AG'));
      }

      final dindi = mesh.knownDindis.single;
      expect(dindi.visibleMembers, 1);
      // The volunteer's own phone is the +1; it is counted exactly once.
      expect(mesh.wariNetwork.participants, 2);
    });

    test('phones with no Dindi never invent one', () {
      // '--' is what a phone carries when its owner has not joined a Dindi.
      // Counting it would manufacture a Dindi out of people who are not in
      // one — and would always show at least 1 on any volunteer's screen.
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      mesh.debugIngestPresence(person('W11111', '--'));
      mesh.debugIngestPresence(person('W22222', '--'));

      expect(mesh.knownDindis, isEmpty);
      expect(mesh.wariNetwork.dindis, 0);
      // They are still participants — they exist, they just have no Dindi.
      expect(mesh.wariNetwork.participants, 3);
    });

    test('hearing nothing reports nothing, not a phantom Dindi', () {
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      expect(mesh.knownDindis, isEmpty);
      expect(mesh.wariNetwork.dindis, 0);
      expect(mesh.wariNetwork.leads, 0);
      // Only this phone.
      expect(mesh.wariNetwork.participants, 1);
    });
  });

  group('roles are read from what the protocol actually carries', () {
    test('splits Warkaris and Volunteers by the Mesh ID role letter', () {
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      mesh.debugIngestPresence(person('W11111', 'AG'));
      mesh.debugIngestPresence(person('W22222', 'AG'));
      mesh.debugIngestPresence(person('V33333', 'AG'));

      final stats = mesh.wariNetwork;
      expect(stats.warkaris, 2);
      // Two heard, plus this phone, which is itself a volunteer.
      expect(stats.volunteers, 2);
      expect(stats.participants, 4);
    });

    test('counts a Dindi Lead once, and names them on their Dindi', () {
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      mesh.debugIngestPresence(
        person('W11111', 'AG', name: 'Rahul', lead: true),
      );
      mesh.debugIngestPresence(person('W22222', 'AG', name: 'Aarav'));

      expect(mesh.wariNetwork.leads, 1);
      final dindi = mesh.knownDindis.single;
      expect(dindi.hasLead, isTrue);
      expect(dindi.leadName, 'Rahul');
      expect(dindi.leadMeshId, 'W11111');
    });

    test('a Dindi with no Lead heard says so rather than picking someone', () {
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      mesh.debugIngestPresence(person('W11111', 'AG'));

      final dindi = mesh.knownDindis.single;
      expect(dindi.hasLead, isFalse);
      expect(dindi.leadName, isNull);
      expect(mesh.wariNetwork.leads, 0);
    });

    test('a repeated Lead beacon does not become several Leads', () {
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      for (var i = 0; i < 5; i++) {
        mesh.debugIngestPresence(person('W11111', 'AG', lead: true));
      }
      expect(mesh.wariNetwork.leads, 1);
    });
  });

  group('what the mesh cannot know, it does not claim', () {
    test('a Dindi heard over the air has no name — only its code', () {
      // Dindi names never travel (see dindiTagFor): the wire carries a
      // two-character hash. Inventing a name here is the single easiest way
      // this dashboard could start lying.
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      mesh.debugIngestPresence(person('W11111', 'AG'));

      final dindi = mesh.knownDindis.single;
      expect(dindi.tag, 'AG');
      expect(dindi.name, isNull);
    });

    test('a Dindi has no location, because presence carries none', () {
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      mesh.debugIngestPresence(person('W11111', 'AG'));

      final dindi = mesh.knownDindis.single;
      expect(dindi.hasLocation, isFalse);
      expect(dindi.latitude, isNull);
      expect(dindi.locationAt, isNull);
    });

    test('a Dindi with nothing wrong reports no emergencies', () {
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      mesh.debugIngestPresence(person('W11111', 'AG'));

      final dindi = mesh.knownDindis.single;
      expect(dindi.activeSos, 0);
      expect(dindi.activeMissing, 0);
      expect(dindi.hasEmergency, isFalse);
      expect(mesh.wariNetwork.quiet, isTrue);
    });

    test(
      'leadIsNearby is about when a beacon was last heard, not "online"',
      () {
        final mesh = volunteerPhone();
        addTearDown(mesh.dispose);
        mesh.debugIngestPresence(person('W11111', 'AG', lead: true));

        final dindi = mesh.knownDindis.single;
        expect(dindi.leadIsNearby(const Duration(seconds: 45)), isTrue);
        // A window of zero means "heard within no time at all", which nothing
        // can satisfy — the check is genuinely time-based rather than a flag
        // that says someone is present.
        expect(dindi.leadIsNearby(Duration.zero), isFalse);
      },
    );
  });

  group('emergencies are attributed to the right Dindi', () {
    test('an SOS counts only against the Dindi that sent it', () {
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      mesh.debugIngestPresence(person('W11111', 'AG'));
      mesh.debugIngestPresence(person('W44444', 'ZQ'));

      // Straight into the queue, as _recordAlert would leave it.
      mesh.alerts.add(
        AlertRecord(
          msgId: 1,
          category: kCategorySos,
          senderLabel: 'W11111',
          groupTag: 'AG',
          receivedAt: DateTime.now(),
          reason: kSosReasonMedical,
        ),
      );

      final ag = mesh.knownDindis.firstWhere((d) => d.tag == 'AG');
      final zq = mesh.knownDindis.firstWhere((d) => d.tag == 'ZQ');
      expect(ag.activeSos, 1);
      expect(ag.hasEmergency, isTrue);
      expect(zq.activeSos, 0);
      expect(zq.hasEmergency, isFalse);
      expect(mesh.wariNetwork.activeSos, 1);
    });

    test('a resolved alert stops counting', () {
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      mesh.debugIngestPresence(person('W11111', 'AG'));
      mesh.alerts.add(
        AlertRecord(
          msgId: 1,
          category: kCategorySos,
          senderLabel: 'W11111',
          groupTag: 'AG',
          receivedAt: DateTime.now(),
          resolvedAt: DateTime.now(),
        ),
      );

      expect(mesh.knownDindis.single.activeSos, 0);
      expect(mesh.wariNetwork.activeSos, 0);
    });

    test('missing persons are counted apart from SOS', () {
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      mesh.debugIngestPresence(person('W11111', 'AG'));
      mesh.alerts.addAll([
        AlertRecord(
          msgId: 1,
          category: kCategorySos,
          senderLabel: 'W11111',
          groupTag: 'AG',
          receivedAt: DateTime.now(),
        ),
        AlertRecord(
          msgId: 2,
          category: kCategoryLostPerson,
          senderLabel: 'W11111',
          groupTag: 'AG',
          receivedAt: DateTime.now(),
        ),
      ]);

      final dindi = mesh.knownDindis.single;
      expect(dindi.activeSos, 1);
      expect(dindi.activeMissing, 1);
      expect(mesh.wariNetwork.activeSos, 1);
      expect(mesh.wariNetwork.activeMissing, 1);
    });

    test('Dindis in trouble sort above quiet ones', () {
      // A volunteer scanning this list needs trouble at the top.
      final mesh = volunteerPhone();
      addTearDown(mesh.dispose);
      // The quiet Dindi is larger, so size alone would put it first.
      mesh.debugIngestPresence(person('W11111', 'ZQ'));
      mesh.debugIngestPresence(person('W22222', 'ZQ'));
      mesh.debugIngestPresence(person('W33333', 'ZQ'));
      mesh.debugIngestPresence(person('W44444', 'AG'));
      mesh.alerts.add(
        AlertRecord(
          msgId: 1,
          category: kCategorySos,
          senderLabel: 'W44444',
          groupTag: 'AG',
          receivedAt: DateTime.now(),
        ),
      );

      expect(mesh.knownDindis.first.tag, 'AG');
    });
  });

  group('this phone counts itself, exactly once', () {
    test('a Lead sees their own Dindi even when alone', () {
      // A Dindi Lead standing by themselves is still a Dindi the mesh
      // knows about — leaving them out would show an empty screen to the
      // one person most likely to be looking at it.
      final mesh = MeshService();
      addTearDown(mesh.dispose);
      mesh.debugSetIdentity(
        meshId: 'W7K2M9',
        groupTag: 'AG',
        role: UserRole.warkari,
        isLead: true,
      );

      final dindi = mesh.knownDindis.single;
      expect(dindi.tag, 'AG');
      expect(dindi.visibleMembers, 1);
      expect(dindi.leadMeshId, 'W7K2M9');
      expect(mesh.wariNetwork.leads, 1);
      expect(mesh.wariNetwork.participants, 1);
      expect(mesh.wariNetwork.warkaris, 1);
    });

    test('own Dindi members include this phone alongside those heard', () {
      final mesh = MeshService();
      addTearDown(mesh.dispose);
      mesh.debugSetIdentity(
        meshId: 'W7K2M9',
        groupTag: 'AG',
        role: UserRole.warkari,
        isLead: false,
      );
      mesh.debugIngestPresence(person('W11111', 'AG'));

      expect(mesh.knownDindis.single.visibleMembers, 2);
      expect(mesh.wariNetwork.participants, 2);
    });
  });
}
