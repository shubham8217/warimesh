// Round-trip tests for the mesh wire formats.
//
// These are pure functions with no BLE stack involved, which makes them the
// one part of the protocol that can be verified without two phones in a
// field. A packing bug here is invisible until the moment it matters — an
// alert that decodes to the wrong coordinates points a search party at the
// wrong place — so the encodings are pinned down here rather than trusted.
import 'package:flutter_test/flutter_test.dart';
import 'package:warimesh/models.dart';

void main() {
  group('LocationPacket', () {
    test('round-trips a position to roughly centimetre precision', () {
      // Pandharpur, the destination of the Wari.
      final packet = LocationPacket(
        msgId: 3141592653,
        latitude: 17.679076,
        longitude: 75.323997,
      );
      final decoded = LocationPacket.decode(packet.encode())!;

      expect(decoded.msgId, packet.msgId);
      expect(decoded.latitude, closeTo(packet.latitude, 0.0000001));
      expect(decoded.longitude, closeTo(packet.longitude, 0.0000001));
    });

    test('round-trips negative coordinates', () {
      final packet = LocationPacket(
        msgId: 1,
        latitude: -33.8688,
        longitude: -70.6693,
      );
      final decoded = LocationPacket.decode(packet.encode())!;
      expect(decoded.latitude, closeTo(-33.8688, 0.0000001));
      expect(decoded.longitude, closeTo(-70.6693, 0.0000001));
    });

    test('survives a msgId in the top half of the uint32 range', () {
      // msgIds are random uint32s, so anything above 2^31 must not come
      // back as a negative number through the int/uint boundary.
      final packet = LocationPacket(
        msgId: 0xFFFFFFFE,
        latitude: 18.5,
        longitude: 73.85,
      );
      expect(LocationPacket.decode(packet.encode())!.msgId, 0xFFFFFFFE);
    });

    test('fits in one BLE advertisement', () {
      // A legacy advertisement leaves ~24 usable bytes of manufacturer
      // data. Every packet format has to stay under that or it silently
      // never transmits.
      expect(
        LocationPacket(msgId: 1, latitude: 1, longitude: 1).encode().length,
        lessThanOrEqualTo(24),
      );
    });

    test('rejects a packet of the wrong type', () {
      final alert = MeshPacket(
        ttl: 2,
        msgId: 7,
        category: kCategorySos,
        senderLabel: 'W7K2M9',
      );
      expect(LocationPacket.decode(alert.encode()), isNull);
    });

    test('rejects coordinates that are not on Earth', () {
      final bytes = LocationPacket(
        msgId: 1,
        latitude: 0,
        longitude: 0,
      ).encode();
      bytes[5] = 0x7F; // corrupt the latitude into an out-of-range value
      bytes[6] = 0xFF;
      expect(LocationPacket.decode(bytes), isNull);
    });

    test('rejects a truncated packet', () {
      final short = LocationPacket(
        msgId: 1,
        latitude: 1,
        longitude: 1,
      ).encode().sublist(0, 8);
      expect(LocationPacket.decode(short), isNull);
    });
  });

  group('IncomingAlert location labels', () {
    IncomingAlert alertAt({double? distance, double? bearing}) => IncomingAlert(
      packet: MeshPacket(
        ttl: 2,
        msgId: 1,
        category: kCategorySos,
        senderLabel: 'W7K2M9',
      ),
      senderName: 'Priya',
      receivedAt: DateTime.now(),
      senderLatitude: 18.5,
      senderLongitude: 73.85,
      distanceMetres: distance,
      bearingDegrees: bearing,
    );

    test('shows metres below a kilometre and kilometres above', () {
      expect(alertAt(distance: 240).distanceLabel, '240 m away');
      expect(alertAt(distance: 1440).distanceLabel, '1.4 km away');
    });

    test('maps a bearing to a compass word, including the wrap at north', () {
      expect(alertAt(bearing: 0).directionLabel, 'north');
      expect(alertAt(bearing: 45).directionLabel, 'north-east');
      expect(alertAt(bearing: 225).directionLabel, 'south-west');
      // 200° is nearer south (180°) than south-west (225°) and must round
      // that way — the point of eight compass words is that each covers a
      // 45° arc centred on its own heading.
      expect(alertAt(bearing: 200).directionLabel, 'south');
      // Bearings just under 360 must read as north, not fall off the list.
      expect(alertAt(bearing: 359).directionLabel, 'north');
      // Geolocator returns signed bearings, so negatives must normalise.
      expect(alertAt(bearing: -90).directionLabel, 'west');
    });

    test('has no labels when there is nothing to say', () {
      expect(alertAt().distanceLabel, isNull);
      expect(alertAt().directionLabel, isNull);
    });
  });

  group('other packet formats still round-trip', () {
    test('MeshPacket', () {
      final p = MeshPacket(
        ttl: 2,
        msgId: 424242,
        category: kCategoryLostPerson,
        senderLabel: 'W7K2M9',
        groupTag: 'K7',
      );
      final d = MeshPacket.decode(p.encode())!;
      expect(d.ttl, 2);
      expect(d.msgId, 424242);
      expect(d.category, kCategoryLostPerson);
      expect(d.senderLabel, 'W7K2M9');
      expect(d.groupTag, 'K7');
    });

    test('PresencePacket truncates a long name instead of overflowing', () {
      final p = PresencePacket(
        meshId: 'W7K2M9',
        groupTag: 'K7',
        name: 'Bhagyashree',
      );
      expect(p.encode().length, kPresenceFullLength);
      expect(PresencePacket.decode(p.encode())!.name, 'Bhagyashre');
    });

    test('a non-ASCII name degrades rather than throwing', () {
      // Names on the Wari are very plausibly Devanagari; ascii.encode()
      // would throw on them and take a whole broadcast down with it.
      final p = PresencePacket(
        meshId: 'W7K2M9',
        groupTag: 'K7',
        name: 'प्रिया',
      );
      expect(() => p.encode(), returnsNormally);
    });

    test('dindiTagFor is stable across case and whitespace', () {
      expect(
        dindiTagFor('Sant Tukaram Dindi'),
        dindiTagFor('  sant tukaram dindi '),
      );
      expect(dindiTagFor(''), '--');
      expect(dindiTagFor('—'), '--');
    });
  });

  group('response packets — ACK and RESOLVE', () {
    test('an ACK round-trips and fits one advertisement', () {
      final ack = AckPacket(msgId: 3141592653, responderMeshId: 'V7K2M9');
      final bytes = ack.encode();
      expect(bytes.length, kAckPacketLength);
      expect(bytes.length, lessThanOrEqualTo(24));

      final decoded = AckPacket.decode(bytes)!;
      expect(decoded.msgId, 3141592653);
      expect(decoded.responderMeshId, 'V7K2M9');
    });

    test('a RESOLVE carries its reason and fits one advertisement', () {
      for (final reason in [
        kResolveFound,
        kResolveHandled,
        kResolveFalseAlarm,
      ]) {
        final res = ResolvePacket(
          msgId: 42,
          resolverMeshId: 'V4B2XY',
          reason: reason,
        );
        final bytes = res.encode();
        expect(bytes.length, kResolvePacketLength);
        expect(bytes.length, lessThanOrEqualTo(24));

        final decoded = ResolvePacket.decode(bytes)!;
        expect(decoded.msgId, 42);
        expect(decoded.resolverMeshId, 'V4B2XY');
        expect(decoded.reason, reason);
      }
    });

    test(
      'an unknown reason code degrades to "handled" rather than decoding as found',
      () {
        // Direction matters here. A newer build inventing reason code 9 must
        // never be read as "found safe" by an older phone — that would close a
        // search on a guess.
        final bytes = ResolvePacket(
          msgId: 1,
          resolverMeshId: 'VZZZZZ',
        ).encode();
        bytes[11] = 9;
        expect(ResolvePacket.decode(bytes)!.reason, kResolveHandled);
      },
    );

    test('the response decoders reject each other and anything truncated', () {
      final ack = AckPacket(msgId: 7, responderMeshId: 'V11111').encode();
      final res = ResolvePacket(msgId: 7, resolverMeshId: 'V11111').encode();
      expect(ResolvePacket.decode(ack), isNull);
      expect(AckPacket.decode(res), isNull);
      expect(AckPacket.decode(ack.sublist(0, kAckPacketLength - 1)), isNull);
      expect(
        ResolvePacket.decode(res.sublist(0, kResolvePacketLength - 1)),
        isNull,
      );
    });

    test(
      'a blank responder id is rejected rather than attributed to nobody',
      () {
        final ack = AckPacket(msgId: 7, responderMeshId: '      ').encode();
        expect(AckPacket.decode(ack), isNull);
      },
    );
  });

  group('PresencePacket station byte', () {
    test('round-trips every defined station', () {
      for (final station in kStationTypes) {
        final packet = PresencePacket(
          meshId: 'V7K2M9',
          groupTag: 'AB',
          name: 'Sunita',
          station: station,
        );
        final decoded = PresencePacket.decode(packet.encode())!;
        expect(decoded.station, station);
        expect(decoded.name, 'Sunita');
        expect(decoded.isHelpPoint, station != kStationNone);
      }
    });

    test(
      'still fits one advertisement at 21 bytes, station + Lead flag included',
      () {
        final bytes = PresencePacket(
          meshId: 'V7K2M9',
          groupTag: 'AB',
          name: 'Sunita',
          station: kStationMedical,
        ).encode();
        expect(bytes.length, kPresenceFullLength);
        expect(bytes.length, lessThanOrEqualTo(24));
      },
    );

    test(
      'a 19-byte beacon from an older build still decodes, as no help point',
      () {
        // The backward-compatibility guarantee that lets the station byte ship
        // without a flag day — see the note on kPresencePacketLength. A phone
        // that cannot be updated must not fall off the mesh.
        final full = PresencePacket(
          meshId: 'W7K2M9',
          groupTag: 'AB',
          name: 'Aarav',
          station: kStationWater,
        ).encode();
        final legacy = full.sublist(0, kPresenceBaseLength);

        final decoded = PresencePacket.decode(legacy)!;
        expect(decoded.meshId, 'W7K2M9');
        expect(decoded.name, 'Aarav');
        expect(decoded.station, kStationNone);
        expect(decoded.isHelpPoint, isFalse);
        expect(decoded.isDindiLead, isFalse);
      },
    );

    test(
      'an unknown station code from a newer build reads as no help point',
      () {
        // Same direction of caution as the resolve reason: never render an
        // undefined code as some kind of help, which would send someone
        // walking towards a tent that isn't there.
        final bytes = PresencePacket(
          meshId: 'V7K2M9',
          groupTag: 'AB',
          name: 'X',
        ).encode();
        bytes[kPresenceBaseLength] = 99;
        expect(PresencePacket.decode(bytes)!.station, kStationNone);
      },
    );
  });

  group('presence rejects ambient Bluetooth noise', () {
    // Regression tests for something a real phone found: kManufacturerId is
    // 0xFFFF, the BT SIG "reserved for testing" ID that unbranded BLE
    // gadgets also use, so their advertisements reach the decoder. On an
    // ordinary street the app logged 65 such sightings in 20 seconds and
    // turned each into a person in the Dindi headcount.

    test('accepts identifiers this app actually generates', () {
      for (final role in UserRole.values) {
        expect(isPlausibleMeshId(generateMeshId(role)), isTrue);
      }
      expect(isPlausibleMeshId('W7K2M9'), isTrue);
      expect(isPlausibleMeshId('V4B2XY'), isTrue);
    });

    test('rejects the shapes random bytes actually produce', () {
      expect(isPlausibleMeshId(''), isFalse);
      expect(isPlausibleMeshId('W7K2M'), isFalse); // too short
      expect(isPlausibleMeshId('W7K2M99'), isFalse); // too long
      expect(isPlausibleMeshId('X7K2M9'), isFalse); // not a role letter
      expect(isPlausibleMeshId('w7k2m9'), isFalse); // lower case
      // 0, O, 1, I and L are deliberately absent from the alphabet because
      // they are ambiguous when read aloud — so they are also a good signal
      // that something did not come from generateMeshId.
      expect(isPlausibleMeshId('W0K2M9'), isFalse);
      expect(isPlausibleMeshId('W1K2M9'), isFalse);
      expect(isPlausibleMeshId('W K2M9'), isFalse);
      expect(isPlausibleMeshId('W?K2M9'), isFalse);
    });

    test('a beacon with a garbage identifier is dropped entirely', () {
      // The actual defence: decode() returns null rather than handing back a
      // packet that a caller would file as a nearby person.
      final bytes = PresencePacket(
        meshId: 'W7K2M9',
        groupTag: 'AB',
        name: 'Rahul',
      ).encode();
      // Corrupt the identifier the way a foreign advertisement would.
      bytes[1] = 0x00;
      bytes[2] = 0xFF;
      expect(PresencePacket.decode(bytes), isNull);
    });

    test('a genuine beacon still decodes in all three wire lengths', () {
      // The rejection must not cost backward compatibility — a phone that
      // cannot be updated mid-Wari has to stay visible.
      final full = PresencePacket(
        meshId: 'W7K2M9',
        groupTag: 'AB',
        name: 'Rahul',
        station: kStationWater,
        isDindiLead: true,
      ).encode();

      expect(PresencePacket.decode(full)!.meshId, 'W7K2M9');
      expect(
        PresencePacket.decode(full.sublist(0, kPresencePacketLength))!.meshId,
        'W7K2M9',
      );
      expect(
        PresencePacket.decode(full.sublist(0, kPresenceBaseLength))!.meshId,
        'W7K2M9',
      );
    });
  });

  group('PresencePacket Dindi Lead flag', () {
    test('round-trips true and false', () {
      for (final lead in [true, false]) {
        final packet = PresencePacket(
          meshId: 'W7K2M9',
          groupTag: 'AB',
          name: 'Rahul',
          isDindiLead: lead,
        );
        expect(PresencePacket.decode(packet.encode())!.isDindiLead, lead);
      }
    });

    test(
      'a 20-byte beacon (station, no Lead flag) from an older build decodes as not-Lead',
      () {
        // Same append-only guarantee the station byte relies on, one layer
        // further — see the note on kPresenceFullLength. A phone that shipped
        // with station support but not yet the Lead flag must not fall off
        // the mesh, and must not be mistaken for a Lead by a newer phone.
        final full = PresencePacket(
          meshId: 'W7K2M9',
          groupTag: 'AB',
          name: 'Rahul',
          station: kStationMedical,
          isDindiLead: true,
        ).encode();
        final legacy = full.sublist(0, kPresencePacketLength);

        final decoded = PresencePacket.decode(legacy)!;
        expect(decoded.station, kStationMedical);
        expect(decoded.isDindiLead, isFalse);
      },
    );

    test('station and Lead flag are independent', () {
      final packet = PresencePacket(
        meshId: 'W7K2M9',
        groupTag: 'AB',
        name: 'Rahul',
        station: kStationNone,
        isDindiLead: true,
      );
      final decoded = PresencePacket.decode(packet.encode())!;
      expect(decoded.station, kStationNone);
      expect(decoded.isDindiLead, isTrue);
    });
  });

  group(
    'responderRoleLabel and responderVerb — Wari Emergency Response Network',
    () {
      test('a V-prefixed Mesh ID is always a Volunteer, Lead flag or not', () {
        expect(responderRoleLabel('V7K2M9', isDindiLead: false), 'Volunteer');
        expect(responderRoleLabel('V7K2M9', isDindiLead: true), 'Volunteer');
      });

      test('a W-prefixed Mesh ID flagged as Lead is the Dindi Lead', () {
        expect(responderRoleLabel('W7K2M9', isDindiLead: true), 'Dindi Lead');
      });

      test('a W-prefixed Mesh ID with no Lead flag is an ordinary Warkari', () {
        // The "Join anyway" case — ACK doesn't discriminate who's allowed to
        // claim, so an ordinary Dindi member can still show up here.
        expect(responderRoleLabel('W7K2M9', isDindiLead: false), 'Warkari');
      });

      test('a Lead coordinates, everyone else responds', () {
        expect(responderVerb('Dindi Lead'), 'is coordinating');
        expect(responderVerb('Volunteer'), 'is responding');
        expect(responderVerb('Warkari'), 'is responding');
      });
    },
  );

  group('isDindiEmergency — the Dindi Lead\'s queue filter', () {
    AlertRecord makeAlert({
      int category = kCategorySos,
      String groupTag = 'AB',
      bool mine = false,
      bool resolved = false,
    }) => AlertRecord(
      msgId: 1,
      category: category,
      senderLabel: 'W7K2M9',
      groupTag: groupTag,
      receivedAt: DateTime.now(),
      mine: mine,
      resolvedAt: resolved ? DateTime.now() : null,
    );

    test('an SOS from the Lead\'s own Dindi qualifies', () {
      expect(isDindiEmergency(makeAlert(groupTag: 'AB'), 'AB'), isTrue);
    });

    test('an SOS from a different Dindi does not', () {
      expect(isDindiEmergency(makeAlert(groupTag: 'ZZ'), 'AB'), isFalse);
    });

    test('a missing person from the same Dindi also qualifies', () {
      // Broadened deliberately: a Lead has to coordinate a search for one
      // of their own people, not just an SOS. See isDindiEmergency's note.
      expect(
        isDindiEmergency(
          makeAlert(category: kCategoryLostPerson, groupTag: 'AB'),
          'AB',
        ),
        isTrue,
      );
    });

    test('a missing person from a different Dindi does not', () {
      expect(
        isDindiEmergency(
          makeAlert(category: kCategoryLostPerson, groupTag: 'ZZ'),
          'AB',
        ),
        isFalse,
      );
    });

    test('a resolved alert drops off the Lead\'s queue', () {
      // The queue is what still needs coordinating; closed cases belong in
      // history, not at the top of a home screen.
      expect(
        isDindiEmergency(makeAlert(groupTag: 'AB', resolved: true), 'AB'),
        isFalse,
      );
    });

    test('this phone\'s own SOS never appears as something to coordinate', () {
      expect(
        isDindiEmergency(makeAlert(groupTag: 'AB', mine: true), 'AB'),
        isFalse,
      );
    });

    test(
      'a warkari with no Dindi (tag "--") never matches a Lead\'s empty tag either',
      () {
        // Edge case 12: "Warkari without Dindi → SOS still reaches volunteers
        // normally." Confirms it does NOT also masquerade as a Dindi
        // Emergency for a Lead who also has no Dindi set.
        expect(isDindiEmergency(makeAlert(groupTag: '--'), '--'), isTrue);
        // But a Lead's own un-set groupTag deliberately still doesn't create
        // a false match with a genuinely tagged Dindi.
        expect(isDindiEmergency(makeAlert(groupTag: 'AB'), '--'), isFalse);
      },
    );
  });

  group('AlertRecord triage', () {
    AlertRecord make(
      int category, {
      String? claimedBy,
      DateTime? resolvedAt,
      int minutesAgo = 0,
    }) => AlertRecord(
      msgId: category * 1000 + minutesAgo,
      category: category,
      senderLabel: 'W7K2M9',
      receivedAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
      claimedBy: claimedBy,
      resolvedAt: resolvedAt,
    );

    test('an unclaimed SOS outranks everything else', () {
      final sos = make(kCategorySos);
      final lost = make(kCategoryLostPerson);
      final claimedSos = make(kCategorySos, claimedBy: 'V1');
      final closed = make(kCategorySos, resolvedAt: DateTime.now());

      expect(sos.triageRank, lessThan(lost.triageRank));
      expect(lost.triageRank, lessThan(claimedSos.triageRank));
      expect(claimedSos.triageRank, lessThan(closed.triageRank));
    });

    test('the three states are mutually exclusive', () {
      expect(make(kCategorySos).isOpen, isTrue);
      expect(make(kCategorySos, claimedBy: 'V1').isClaimed, isTrue);
      expect(make(kCategorySos, claimedBy: 'V1').isOpen, isFalse);

      // A resolved alert is not "claimed" even when someone had claimed it —
      // otherwise the queue would offer to respond to a closed incident.
      final closed = make(
        kCategorySos,
        claimedBy: 'V1',
        resolvedAt: DateTime.now(),
      );
      expect(closed.isResolved, isTrue);
      expect(closed.isClaimed, isFalse);
      expect(closed.isOpen, isFalse);
    });

    test('claimedByMe distinguishes my response from a colleague\'s', () {
      final mine = make(kCategorySos, claimedBy: 'V7K2M9');
      expect(mine.claimedByMe('V7K2M9'), isTrue);
      expect(mine.claimedByMe('V4B2XY'), isFalse);
    });

    test('a lost-person summary appears only once the detail packet lands', () {
      final alert = make(kCategoryLostPerson);
      expect(alert.lostSummary, isNull);
      alert.lostName = 'Aarav';
      alert.lostAge = '8';
      expect(alert.lostSummary, 'Aarav, age 8');
    });

    test('survives a round-trip through the database map', () {
      final original =
          make(kCategoryLostPerson, claimedBy: 'V4B2XY', minutesAgo: 3)
            ..lostName = 'Aarav'
            ..lostAge = '8'
            ..latitude = 17.679076
            ..longitude = 75.323997;

      final restored = AlertRecord.fromMap(
        original.toMap().cast<String, Object?>(),
      );
      expect(restored.msgId, original.msgId);
      expect(restored.category, kCategoryLostPerson);
      expect(restored.claimedBy, 'V4B2XY');
      expect(restored.lostName, 'Aarav');
      expect(restored.latitude, closeTo(17.679076, 1e-9));
      expect(restored.isClaimed, isTrue);
    });
  });

  group('text fragmentation', () {
    ({TextHeadPacket head, List<TextPartPacket> parts}) frag(String body) =>
        fragmentText(
          msgId: 7654321,
          ttl: kDefaultTtl,
          kind: kTextKindChat,
          groupTag: '53',
          senderLabel: 'W7K2M9',
          body: body,
        );

    /// Round-trips a message the way the mesh does: encode every fragment,
    /// decode it back, and reassemble — which is what actually has to work.
    String roundTrip(String body) {
      final f = frag(body);
      final head = TextHeadPacket.decode(f.head.encode())!;
      final chunks = <int, String>{0: head.chunk};
      for (final p in f.parts) {
        final part = TextPartPacket.decode(p.encode())!;
        chunks[part.index] = part.chunk;
      }
      return [
        for (var i = 0; i < head.fragTotal; i++) chunks[i]!,
      ].join().trimRight();
    }

    test('a message shorter than one fragment needs exactly one', () {
      final f = frag('Water');
      expect(f.head.fragTotal, 1);
      expect(f.parts, isEmpty);
      expect(roundTrip('Water'), 'Water');
    });

    test('a message exactly filling the head still needs only one', () {
      final body = 'a' * kTextHeadChars;
      expect(frag(body).head.fragTotal, 1);
      expect(roundTrip(body), body);
    });

    test('one character past the head spills into a second fragment', () {
      final body = 'a' * (kTextHeadChars + 1);
      expect(frag(body).head.fragTotal, 2);
      expect(roundTrip(body), body);
    });

    test('a realistic message round-trips intact', () {
      const body = 'Water point at the next turn, left side after the bridge';
      expect(roundTrip(body), body);
    });

    test('a maximum-length message round-trips and stays within the cap', () {
      final body = 'x' * kMaxTextLength;
      final f = frag(body);
      expect(f.head.fragTotal, lessThanOrEqualTo(kMaxTextFragments));
      expect(roundTrip(body), body);
    });

    test('over-long input is truncated rather than dropped', () {
      final body = 'y' * (kMaxTextLength + 50);
      expect(roundTrip(body).length, kMaxTextLength);
    });

    test('every fragment fits one advertisement', () {
      final f = frag('z' * kMaxTextLength);
      expect(f.head.encode().length, lessThanOrEqualTo(24));
      for (final p in f.parts) {
        expect(p.encode().length, lessThanOrEqualTo(24));
      }
    });

    test('identity and kind survive the head round-trip', () {
      final head = TextHeadPacket.decode(
        frag('hello there friend').head.encode(),
      )!;
      expect(head.msgId, 7654321);
      expect(head.senderLabel, 'W7K2M9');
      expect(head.groupTag, '53');
      expect(head.kind, kTextKindChat);
      expect(head.ttl, kDefaultTtl);
    });

    test('an announcement is distinguishable from chat on the wire', () {
      final head = TextHeadPacket.decode(
        fragmentText(
          msgId: 1,
          ttl: 2,
          kind: kTextKindAnnouncement,
          groupTag: '53',
          senderLabel: 'V7K2M9',
          body: 'Route changed',
        ).head.encode(),
      )!;
      expect(head.kind, kTextKindAnnouncement);
    });

    test('relaying decrements ttl and preserves everything else', () {
      final head = frag('hello there friend').head.relayed();
      expect(head.ttl, kDefaultTtl - 1);
      expect(head.chunk, isNotEmpty);
      final part = frag('hello there friend').parts.first.relayed();
      expect(part.ttl, kDefaultTtl - 1);
    });

    test('interior spaces are preserved across a fragment boundary', () {
      // Padding is stripped only at the very end, so a space that lands on
      // a fragment edge must not be eaten.
      const body = 'meet me  at   the gate';
      expect(roundTrip(body), body);
    });

    test('rejects a corrupt fragment count', () {
      final bytes = frag('hello').head.encode();
      bytes[6] = 0x00; // kind 0, fragTotal 0 — impossible
      expect(TextHeadPacket.decode(bytes), isNull);
    });

    test('rejects a part index outside the allowed range', () {
      final bytes = frag('a much longer message here').parts.first.encode();
      bytes[6] = 0; // index 0 belongs to the head, never a part
      expect(TextPartPacket.decode(bytes), isNull);
    });

    test('head and part decoders reject each other', () {
      final f = frag('a much longer message here please');
      expect(TextPartPacket.decode(f.head.encode()), isNull);
      expect(TextHeadPacket.decode(f.parts.first.encode()), isNull);
    });

    test('a non-ASCII message degrades rather than throwing', () {
      expect(() => frag('पाणी इथे आहे').head.encode(), returnsNormally);
    });
  });

  group('HelpPointPacket — the Wari Seva Network', () {
    test('round-trips every defined station and fits one advertisement', () {
      for (final station in kStationTypes.where((s) => s != kStationNone)) {
        final packet = HelpPointPacket(
          ttl: kDefaultTtl,
          msgId: 3141592653,
          helpType: station,
          senderLabel: 'V7K2M9',
          status: kHelpStatusOpen,
          expiresInMinutesDiv5: 24,
        );
        final bytes = packet.encode();
        expect(bytes.length, kHelpPointPacketLength);
        expect(bytes.length, lessThanOrEqualTo(24));

        final decoded = HelpPointPacket.decode(bytes)!;
        expect(decoded.helpType, station);
        expect(decoded.msgId, 3141592653);
        expect(decoded.senderLabel, 'V7K2M9');
        expect(decoded.status, kHelpStatusOpen);
        expect(decoded.expiryDuration, const Duration(minutes: 120));
      }
    });

    test('carries the LIMITED status', () {
      final packet = HelpPointPacket(
        ttl: 2,
        msgId: 1,
        helpType: kStationNightHalt,
        senderLabel: 'V1AAAA',
        status: kHelpStatusLimited,
      );
      expect(
        HelpPointPacket.decode(packet.encode())!.status,
        kHelpStatusLimited,
      );
    });

    test('relaying decrements ttl and preserves identity, type and expiry', () {
      final original = HelpPointPacket(
        ttl: kDefaultTtl,
        msgId: 55,
        helpType: kStationWater,
        senderLabel: 'V4B2XY',
        expiresInMinutesDiv5: 10,
      );
      final relayed = original.relayed();
      expect(relayed.ttl, kDefaultTtl - 1);
      expect(relayed.msgId, 55);
      expect(relayed.helpType, kStationWater);
      expect(relayed.senderLabel, 'V4B2XY');
      expect(relayed.expiresInMinutesDiv5, 10);
    });

    test(
      'rejects kStationNone — an announcement must name a real help type',
      () {
        final bytes = HelpPointPacket(
          ttl: 2,
          msgId: 1,
          helpType: kStationMedical,
          senderLabel: 'V1AAAA',
        ).encode();
        bytes[6] = kStationNone;
        expect(HelpPointPacket.decode(bytes), isNull);
      },
    );

    test(
      'an unknown help type from a newer build is rejected rather than shown as something undefined',
      () {
        final bytes = HelpPointPacket(
          ttl: 2,
          msgId: 1,
          helpType: kStationMedical,
          senderLabel: 'V1AAAA',
        ).encode();
        bytes[6] = 200;
        expect(HelpPointPacket.decode(bytes), isNull);
      },
    );

    test('rejects a packet of the wrong type and anything truncated', () {
      final alert = MeshPacket(
        ttl: 2,
        msgId: 7,
        category: kCategorySos,
        senderLabel: 'W7K2M9',
      ).encode();
      expect(HelpPointPacket.decode(alert), isNull);
      final short = HelpPointPacket(
        ttl: 2,
        msgId: 1,
        helpType: kStationMedical,
        senderLabel: 'V1AAAA',
      ).encode().sublist(0, kHelpPointPacketLength - 1);
      expect(HelpPointPacket.decode(short), isNull);
    });
  });

  group('HelpPointStatusPacket — closing or updating a help point', () {
    test('round-trips CLOSED and LIMITED and fits one advertisement', () {
      for (final status in [kHelpStatusClosed, kHelpStatusLimited]) {
        final packet = HelpPointStatusPacket(
          msgId: 42,
          updaterMeshId: 'V4B2XY',
          status: status,
        );
        final bytes = packet.encode();
        expect(bytes.length, kHelpPointStatusPacketLength);
        expect(bytes.length, lessThanOrEqualTo(24));

        final decoded = HelpPointStatusPacket.decode(bytes)!;
        expect(decoded.msgId, 42);
        expect(decoded.updaterMeshId, 'V4B2XY');
        expect(decoded.status, status);
      }
    });

    test('an unknown status code degrades to CLOSED rather than OPEN', () {
      // Same direction of caution as ResolvePacket's unknown-reason test:
      // never let a corrupt or newer-build byte read as "still open", which
      // would send someone walking towards a help point that said it's shut.
      final bytes = HelpPointStatusPacket(
        msgId: 1,
        updaterMeshId: 'VZZZZZ',
      ).encode();
      bytes[11] = 9;
      expect(HelpPointStatusPacket.decode(bytes)!.status, kHelpStatusClosed);
    });

    test('a blank updater id is rejected rather than attributed to nobody', () {
      final bytes = HelpPointStatusPacket(
        msgId: 7,
        updaterMeshId: '      ',
      ).encode();
      expect(HelpPointStatusPacket.decode(bytes), isNull);
    });

    test('rejects a packet of the wrong type and anything truncated', () {
      final ack = AckPacket(msgId: 7, responderMeshId: 'V11111').encode();
      expect(HelpPointStatusPacket.decode(ack), isNull);
      final short = HelpPointStatusPacket(
        msgId: 1,
        updaterMeshId: 'V1AAAA',
      ).encode().sublist(0, kHelpPointStatusPacketLength - 1);
      expect(HelpPointStatusPacket.decode(short), isNull);
    });
  });

  group('HelpPointRecord', () {
    test('isActive is false once closed, even before expiry', () {
      final point = HelpPointRecord(
        msgId: 1,
        helpType: kStationMedical,
        senderLabel: 'V7K2M9',
        receivedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        status: kHelpStatusClosed,
      );
      expect(point.isActive, isFalse);
    });

    test('isActive is false once expired, even if never explicitly closed', () {
      final point = HelpPointRecord(
        msgId: 1,
        helpType: kStationMedical,
        senderLabel: 'V7K2M9',
        receivedAt: DateTime.now().subtract(const Duration(hours: 3)),
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(point.isExpired, isTrue);
      expect(point.isActive, isFalse);
    });

    test('a night halt gets a longer default expiry than other stations', () {
      expect(
        helpPointDefaultExpiry(kStationNightHalt),
        greaterThan(helpPointDefaultExpiry(kStationMedical)),
      );
    });

    test('survives a round-trip through the database map', () {
      final original = HelpPointRecord(
        msgId: 12345,
        helpType: kStationPolice,
        senderLabel: 'V7K2M9',
        senderName: 'Sunita',
        receivedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 2)),
        hops: 2,
        status: kHelpStatusLimited,
      )..acknowledged = true;

      final restored = HelpPointRecord.fromMap(
        original.toMap().cast<String, Object?>(),
      );
      expect(restored.msgId, 12345);
      expect(restored.helpType, kStationPolice);
      expect(restored.hops, 2);
      expect(restored.isLimited, isTrue);
      expect(restored.acknowledged, isTrue);
    });
  });

  group('SOS reason on the wire', () {
    MeshPacket sos(int reason) => MeshPacket(
      ttl: kDefaultTtl,
      msgId: 3141592653,
      category: kCategorySos,
      senderLabel: 'W7K2M9',
      groupTag: 'AB',
      reason: reason,
    );

    test('every reason survives select → encode → decode unchanged', () {
      // The whole point of the feature: a medical emergency must never
      // arrive as a generic SOS, and must never arrive as some other
      // category.
      for (final reason in kSosReasons) {
        final decoded = MeshPacket.decode(sos(reason).encode())!;
        expect(decoded.reason, reason, reason: sosReasonLabel(reason));
        expect(decoded.category, kCategorySos);
        expect(decoded.msgId, 3141592653);
        expect(decoded.senderLabel, 'W7K2M9');
        expect(decoded.groupTag, 'AB');
      }
    });

    test('the alert packet still fits one advertisement at 16 bytes', () {
      final bytes = sos(kSosReasonMedical).encode();
      expect(bytes.length, kPacketFullLength);
      expect(bytes.length, lessThanOrEqualTo(24));
    });

    test(
      'a 15-byte alert from an older build still decodes, as unspecified',
      () {
        // The append-only guarantee that lets the reason byte ship without a
        // flag day — see the note above kPacketFullLength. A phone that
        // cannot be updated mid-Wari must not fall off the mesh, and its SOS
        // must still be an SOS.
        final legacy = sos(
          kSosReasonMedical,
        ).encode().sublist(0, kPacketLength);

        final decoded = MeshPacket.decode(legacy)!;
        expect(decoded.category, kCategorySos);
        expect(decoded.senderLabel, 'W7K2M9');
        expect(decoded.reason, kSosReasonUnspecified);
        expect(sosReasonIsSpecific(decoded.reason), isFalse);
      },
    );

    test('an unknown reason from a newer build degrades to unspecified', () {
      // Direction of caution matters: an unrecognised code must read as "an
      // SOS that didn't say why", never as some other category. Showing the
      // wrong emergency type sends people with the wrong equipment.
      final bytes = sos(kSosReasonMedical).encode();
      bytes[kPacketLength] = 99;
      expect(MeshPacket.decode(bytes)!.reason, kSosReasonUnspecified);
    });

    test('relaying preserves the reason along with everything else', () {
      final relayed = sos(kSosReasonHeat).relayed();
      expect(relayed.reason, kSosReasonHeat);
      expect(relayed.ttl, kDefaultTtl - 1);
      expect(relayed.msgId, 3141592653);
      expect(relayed.category, kCategorySos);
      // And it must survive the second encode/decode too — a two-hop relay
      // is the whole demo.
      final secondHop = MeshPacket.decode(relayed.encode())!;
      expect(secondHop.reason, kSosReasonHeat);
      expect(secondHop.ttl, kDefaultTtl - 1);
    });

    test('a Lost Person alert carries no reason', () {
      final lost = MeshPacket(
        ttl: 2,
        msgId: 1,
        category: kCategoryLostPerson,
        senderLabel: 'W7K2M9',
      );
      expect(MeshPacket.decode(lost.encode())!.reason, kSosReasonUnspecified);
    });

    test('every reason has a distinct label and a glyph', () {
      final labels = kSosReasons.map(sosReasonLabel).toSet();
      expect(labels.length, kSosReasons.length);
      for (final reason in kSosReasons) {
        expect(sosReasonEmoji(reason), isNotEmpty);
        expect(sosReasonIsSpecific(reason), isTrue);
      }
      // Unspecified is deliberately NOT "specific" — every piece of UI keys
      // off this to avoid rendering "Emergency emergency".
      expect(sosReasonIsSpecific(kSosReasonUnspecified), isFalse);
    });
  });

  group('SOS reason priority and triage', () {
    AlertRecord sosWith(int reason) => AlertRecord(
      msgId: reason,
      category: kCategorySos,
      senderLabel: 'W7K2M9',
      receivedAt: DateTime.now(),
      reason: reason,
    );

    test('medical, child and safety are critical; heat and elderly high', () {
      expect(sosReasonPriority(kSosReasonMedical), kSosPriorityCritical);
      expect(sosReasonPriority(kSosReasonChild), kSosPriorityCritical);
      expect(sosReasonPriority(kSosReasonSafety), kSosPriorityCritical);
      expect(sosReasonPriority(kSosReasonHeat), kSosPriorityHigh);
      expect(sosReasonPriority(kSosReasonElderly), kSosPriorityHigh);
      expect(sosReasonPriority(kSosReasonLost), kSosPriorityNormal);
      expect(sosReasonPriority(kSosReasonOther), kSosPriorityNormal);
    });

    test('a medical SOS sorts above a lost-and-separated one', () {
      expect(
        sosWith(kSosReasonMedical).triageRank,
        lessThan(sosWith(kSosReasonLost).triageRank),
      );
    });

    test(
      'an SOS that did not say why still outranks every lost-person alert',
      () {
        // The band boundary that must not move. Priority reorders a list; it
        // must never demote an SOS below a different kind of alert entirely.
        final quietSos = sosWith(kSosReasonUnspecified);
        final lostPerson = AlertRecord(
          msgId: 99,
          category: kCategoryLostPerson,
          senderLabel: 'W7K2M9',
          receivedAt: DateTime.now(),
        );
        expect(quietSos.triageRank, lessThan(lostPerson.triageRank));
      },
    );

    test(
      'an unclaimed low-priority SOS still outranks a claimed critical one',
      () {
        // Somebody is already going to the claimed one. The unanswered call
        // is the one that needs a human, whatever it says.
        final claimedMedical = sosWith(kSosReasonMedical)..claimedBy = 'V1AAAA';
        expect(
          sosWith(kSosReasonOther).triageRank,
          lessThan(claimedMedical.triageRank),
        );
      },
    );

    test('headline names the emergency, or falls back cleanly', () {
      expect(sosWith(kSosReasonMedical).headline, contains('Medical'));
      expect(sosWith(kSosReasonMedical).headline, contains('SOS'));
      expect(sosWith(kSosReasonUnspecified).headline, 'SOS');
      expect(sosWith(kSosReasonUnspecified).reasonLabel, isNull);
    });

    test('reason survives a round-trip through the database map', () {
      final restored = AlertRecord.fromMap(
        sosWith(kSosReasonSafety).toMap().cast<String, Object?>(),
      );
      expect(restored.reason, kSosReasonSafety);
      expect(restored.reasonLabel, 'Safety / Threat');
    });

    test('a row written before reasons existed reads as unspecified', () {
      // What every alert already on a phone looks like after the v11
      // migration: no reason column value at all.
      final legacy = sosWith(kSosReasonMedical).toMap().cast<String, Object?>()
        ..remove('reason');
      expect(AlertRecord.fromMap(legacy).reason, kSosReasonUnspecified);
    });
  });

  group('SOS → Seva mapping', () {
    test('each reason maps to the stations that can actually help', () {
      expect(
        sevaStationsForReason(kSosReasonMedical),
        containsAll([kStationMedical, kStationFirstAid]),
      );
      expect(
        sevaStationsForReason(kSosReasonHeat),
        containsAll([kStationWater, kStationMedical]),
      );
      expect(
        sevaStationsForReason(kSosReasonChild),
        containsAll([kStationLostChildDesk, kStationPolice]),
      );
      expect(sevaStationsForReason(kSosReasonSafety), [kStationPolice]);
      expect(
        sevaStationsForReason(kSosReasonLost),
        containsAll([kStationPolice, kStationLostChildDesk]),
      );
      expect(
        sevaStationsForReason(kSosReasonElderly),
        contains(kStationMedical),
      );
    });

    test('heat puts water first — rehydration before escalation', () {
      expect(sevaStationsForReason(kSosReasonHeat).first, kStationWater);
    });

    test('a reason with nothing specific to offer recommends nothing', () {
      // The no-false-recommendation rule. "Other" and an unspecified SOS
      // must not produce a confident suggestion nobody asked for.
      expect(sevaStationsForReason(kSosReasonOther), isEmpty);
      expect(sevaStationsForReason(kSosReasonUnspecified), isEmpty);
    });

    test('no mapping ever suggests an irrelevant station', () {
      // A medical emergency must never route somebody to a charging point.
      expect(
        sevaStationsForReason(kSosReasonMedical),
        isNot(contains(kStationCharging)),
      );
      expect(
        sevaStationsForReason(kSosReasonSafety),
        isNot(contains(kStationFood)),
      );
    });
  });

  group('help point location', () {
    HelpPointRecord point({
      double? lat,
      double? lon,
      double? dist,
      double? bearing,
    }) =>
        HelpPointRecord(
            msgId: 1,
            helpType: kStationMedical,
            senderLabel: 'V7K2M9',
            receivedAt: DateTime.now(),
            expiresAt: DateTime.now().add(const Duration(hours: 2)),
            latitude: lat,
            longitude: lon,
          )
          ..distanceMetres = dist
          ..bearingDegrees = bearing;

    test('reuses LocationPacket unchanged — no new wire format', () {
      // The point of the design: a help point's position is an ordinary
      // LocationPacket carrying the help point's msgId.
      final loc = LocationPacket(
        msgId: 987654321,
        latitude: 17.679076,
        longitude: 75.323997,
      );
      final decoded = LocationPacket.decode(loc.encode())!;
      expect(decoded.msgId, 987654321);
      expect(decoded.latitude, closeTo(17.679076, 1e-6));
    });

    test('shows a distance and direction once both ends have a position', () {
      final p = point(lat: 17.6, lon: 75.3, dist: 240, bearing: 45);
      expect(p.hasLocation, isTrue);
      expect(p.distanceLabel, '240 m away');
      expect(p.directionLabel, 'north-east');
      expect(p.whereLabel, '240 m away, to your north-east');
    });

    test('switches to kilometres past a kilometre', () {
      expect(point(lat: 1, lon: 1, dist: 1440).distanceLabel, '1.4 km away');
    });

    test('never invents a distance when the volunteer had no fix', () {
      // The honesty rule. A help point with no position is still worth
      // showing — it just says so.
      final p = point();
      expect(p.hasLocation, isFalse);
      expect(p.distanceLabel, isNull);
      expect(p.whereLabel, contains('Location unavailable'));
    });

    test('says so when the help point is located but this phone is not', () {
      // Position known, no fix here to measure from — a real and different
      // state from "no position at all".
      final p = point(lat: 17.6, lon: 75.3);
      expect(p.hasLocation, isTrue);
      expect(p.distanceLabel, isNull);
      expect(p.whereLabel, contains('no fix on this phone'));
    });

    test('coordinates survive a round-trip through the database map', () {
      final restored = HelpPointRecord.fromMap(
        point(lat: 17.679076, lon: 75.323997).toMap().cast<String, Object?>(),
      );
      expect(restored.latitude, closeTo(17.679076, 1e-9));
      expect(restored.longitude, closeTo(75.323997, 1e-9));
      expect(restored.hasLocation, isTrue);
    });

    test(
      'a row written before help points had coordinates reads as unlocated',
      () {
        final legacy = point(lat: 1, lon: 1).toMap().cast<String, Object?>()
          ..remove('latitude')
          ..remove('longitude');
        expect(HelpPointRecord.fromMap(legacy).hasLocation, isFalse);
      },
    );
  });

  group('SpottedPacket — missing-person sightings', () {
    test('round-trips a sighting with a position', () {
      final packet = SpottedPacket(
        msgId: 3141592653,
        spotterMeshId: 'V7K2M9',
        latitude: 17.679076,
        longitude: 75.323997,
      );
      final bytes = packet.encode();
      expect(bytes.length, kSpottedPacketLength);
      expect(bytes.length, lessThanOrEqualTo(24));

      final decoded = SpottedPacket.decode(bytes)!;
      expect(decoded.msgId, 3141592653);
      expect(decoded.spotterMeshId, 'V7K2M9');
      expect(decoded.hasLocation, isTrue);
      expect(decoded.latitude, closeTo(17.679076, 1e-6));
      expect(decoded.longitude, closeTo(75.323997, 1e-6));
    });

    test('round-trips a sighting with no position, rather than faking one', () {
      // A sighting without GPS is still enormously useful and must survive
      // the wire as exactly that — never as coordinates of 0,0, which is in
      // the Atlantic.
      final packet = SpottedPacket(msgId: 42, spotterMeshId: 'W4B2XY');
      final decoded = SpottedPacket.decode(packet.encode())!;
      expect(decoded.hasLocation, isFalse);
      expect(decoded.latitude, isNull);
      expect(decoded.longitude, isNull);
      expect(decoded.spotterMeshId, 'W4B2XY');
    });

    test('rejects coordinates that are not on Earth, keeping the sighting', () {
      // Same guard as LocationPacket, but the failure mode is gentler: drop
      // the garbage position, keep the fact that somebody saw them.
      final bytes = SpottedPacket(
        msgId: 1,
        spotterMeshId: 'V1AAAA',
        latitude: 0,
        longitude: 0,
      ).encode();
      bytes[12] = 0x7F;
      bytes[13] = 0xFF;

      final decoded = SpottedPacket.decode(bytes)!;
      expect(decoded.hasLocation, isFalse);
      expect(decoded.spotterMeshId, 'V1AAAA');
    });

    test('a blank spotter id is rejected rather than attributed to nobody', () {
      final bytes = SpottedPacket(msgId: 7, spotterMeshId: '      ').encode();
      expect(SpottedPacket.decode(bytes), isNull);
    });

    test('rejects other packet types and anything truncated', () {
      final ack = AckPacket(msgId: 7, responderMeshId: 'V11111').encode();
      expect(SpottedPacket.decode(ack), isNull);
      expect(
        AckPacket.decode(
          SpottedPacket(msgId: 7, spotterMeshId: 'V11111').encode(),
        ),
        isNull,
      );
      final short = SpottedPacket(
        msgId: 1,
        spotterMeshId: 'V1AAAA',
      ).encode().sublist(0, kSpottedPacketLength - 1);
      expect(SpottedPacket.decode(short), isNull);
    });

    test(
      'a sighting never collides with the report location on the record',
      () {
        // The rule that keeps a search usable: a sighting is a second, later
        // point, not a correction of where the report was filed from.
        final alert =
            AlertRecord(
                msgId: 1,
                category: kCategoryLostPerson,
                senderLabel: 'W7K2M9',
                receivedAt: DateTime.now(),
                latitude: 17.6,
                longitude: 75.3,
              )
              ..spottedBy = 'V4B2XY'
              ..spottedAt = DateTime.now()
              ..spottedLatitude = 18.5
              ..spottedLongitude = 73.8;

        expect(alert.latitude, 17.6);
        expect(alert.spottedLatitude, 18.5);
        expect(alert.isSpotted, isTrue);
        expect(alert.hasSpottedLocation, isTrue);
      },
    );

    test('a resolved case is no longer "spotted" — found beats seen', () {
      final alert =
          AlertRecord(
              msgId: 1,
              category: kCategoryLostPerson,
              senderLabel: 'W7K2M9',
              receivedAt: DateTime.now(),
            )
            ..spottedBy = 'V4B2XY'
            ..spottedAt = DateTime.now()
            ..resolvedAt = DateTime.now();

      expect(alert.isSpotted, isFalse);
      expect(alert.isResolved, isTrue);
    });

    test('sighting state survives a round-trip through the database map', () {
      final original =
          AlertRecord(
              msgId: 55,
              category: kCategoryLostPerson,
              senderLabel: 'W7K2M9',
              receivedAt: DateTime.now(),
            )
            ..spottedBy = 'V4B2XY'
            ..spottedAt = DateTime.now()
            ..spottedLatitude = 18.5
            ..spottedLongitude = 73.85;

      final restored = AlertRecord.fromMap(
        original.toMap().cast<String, Object?>(),
      );
      expect(restored.spottedBy, 'V4B2XY');
      expect(restored.isSpotted, isTrue);
      expect(restored.spottedLatitude, closeTo(18.5, 1e-9));
    });
  });
}
