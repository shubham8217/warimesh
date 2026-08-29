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
      final packet = LocationPacket(msgId: 3141592653, latitude: 17.679076, longitude: 75.323997);
      final decoded = LocationPacket.decode(packet.encode())!;

      expect(decoded.msgId, packet.msgId);
      expect(decoded.latitude, closeTo(packet.latitude, 0.0000001));
      expect(decoded.longitude, closeTo(packet.longitude, 0.0000001));
    });

    test('round-trips negative coordinates', () {
      final packet = LocationPacket(msgId: 1, latitude: -33.8688, longitude: -70.6693);
      final decoded = LocationPacket.decode(packet.encode())!;
      expect(decoded.latitude, closeTo(-33.8688, 0.0000001));
      expect(decoded.longitude, closeTo(-70.6693, 0.0000001));
    });

    test('survives a msgId in the top half of the uint32 range', () {
      // msgIds are random uint32s, so anything above 2^31 must not come
      // back as a negative number through the int/uint boundary.
      final packet = LocationPacket(msgId: 0xFFFFFFFE, latitude: 18.5, longitude: 73.85);
      expect(LocationPacket.decode(packet.encode())!.msgId, 0xFFFFFFFE);
    });

    test('fits in one BLE advertisement', () {
      // A legacy advertisement leaves ~24 usable bytes of manufacturer
      // data. Every packet format has to stay under that or it silently
      // never transmits.
      expect(LocationPacket(msgId: 1, latitude: 1, longitude: 1).encode().length, lessThanOrEqualTo(24));
    });

    test('rejects a packet of the wrong type', () {
      final alert = MeshPacket(ttl: 2, msgId: 7, category: kCategorySos, senderLabel: 'W7K2M9');
      expect(LocationPacket.decode(alert.encode()), isNull);
    });

    test('rejects coordinates that are not on Earth', () {
      final bytes = LocationPacket(msgId: 1, latitude: 0, longitude: 0).encode();
      bytes[5] = 0x7F; // corrupt the latitude into an out-of-range value
      bytes[6] = 0xFF;
      expect(LocationPacket.decode(bytes), isNull);
    });

    test('rejects a truncated packet', () {
      final short = LocationPacket(msgId: 1, latitude: 1, longitude: 1).encode().sublist(0, 8);
      expect(LocationPacket.decode(short), isNull);
    });
  });

  group('IncomingAlert location labels', () {
    IncomingAlert alertAt({double? distance, double? bearing}) => IncomingAlert(
          packet: MeshPacket(ttl: 2, msgId: 1, category: kCategorySos, senderLabel: 'W7K2M9'),
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
      final p = MeshPacket(ttl: 2, msgId: 424242, category: kCategoryLostPerson, senderLabel: 'W7K2M9', groupTag: 'K7');
      final d = MeshPacket.decode(p.encode())!;
      expect(d.ttl, 2);
      expect(d.msgId, 424242);
      expect(d.category, kCategoryLostPerson);
      expect(d.senderLabel, 'W7K2M9');
      expect(d.groupTag, 'K7');
    });

    test('PresencePacket truncates a long name instead of overflowing', () {
      final p = PresencePacket(meshId: 'W7K2M9', groupTag: 'K7', name: 'Bhagyashree');
      expect(p.encode().length, kPresencePacketLength);
      expect(PresencePacket.decode(p.encode())!.name, 'Bhagyashre');
    });

    test('a non-ASCII name degrades rather than throwing', () {
      // Names on the Wari are very plausibly Devanagari; ascii.encode()
      // would throw on them and take a whole broadcast down with it.
      final p = PresencePacket(meshId: 'W7K2M9', groupTag: 'K7', name: 'प्रिया');
      expect(() => p.encode(), returnsNormally);
    });

    test('dindiTagFor is stable across case and whitespace', () {
      expect(dindiTagFor('Sant Tukaram Dindi'), dindiTagFor('  sant tukaram dindi '));
      expect(dindiTagFor(''), '--');
      expect(dindiTagFor('—'), '--');
    });
  });

  group('text fragmentation', () {
    ({TextHeadPacket head, List<TextPartPacket> parts}) frag(String body) => fragmentText(
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
      return [for (var i = 0; i < head.fragTotal; i++) chunks[i]!].join().trimRight();
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
      final head = TextHeadPacket.decode(frag('hello there friend').head.encode())!;
      expect(head.msgId, 7654321);
      expect(head.senderLabel, 'W7K2M9');
      expect(head.groupTag, '53');
      expect(head.kind, kTextKindChat);
      expect(head.ttl, kDefaultTtl);
    });

    test('an announcement is distinguishable from chat on the wire', () {
      final head = TextHeadPacket.decode(fragmentText(
        msgId: 1, ttl: 2, kind: kTextKindAnnouncement,
        groupTag: '53', senderLabel: 'V7K2M9', body: 'Route changed',
      ).head.encode())!;
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
}
