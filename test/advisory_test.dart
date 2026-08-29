// What a warkari actually gets to see.
//
// Advisories have always travelled correctly — every phone in range stores
// them regardless of Dindi (see MeshService._storeMessage) and the chat
// thread has always rendered them. What was missing was any surface a
// pilgrim would realistically look at: the volunteer side has a whole tab
// for broadcasting an advisory, and the receiving side had a badge on a tab
// most people never open. A route change could sit unread on a hundred
// phones and every part of the system would look like it was working.
//
// These tests pin the selection rule behind the Home-screen card, so
// "somebody broadcast it" and "somebody saw it" cannot drift apart again.
import 'package:flutter_test/flutter_test.dart';

import 'package:warimesh/mesh_service.dart';
import 'package:warimesh/models.dart';

void main() {
  MeshTextMessage message({
    required int msgId,
    required int kind,
    required Duration age,
    String body = 'Route changed at the bridge',
    String groupTag = 'AB',
  }) => MeshTextMessage(
    msgId: msgId,
    kind: kind,
    groupTag: groupTag,
    senderLabel: 'V7K2M9',
    senderName: 'Sunita',
    body: body,
    createdAt: DateTime.now().subtract(age),
    outgoing: false,
  );

  group('recentAdvisories — the Home-screen notice board', () {
    test('picks out advisories and ignores ordinary Dindi chatter', () {
      final mesh = MeshService();
      addTearDown(mesh.dispose);
      mesh.messages.addAll([
        message(
          msgId: 1,
          kind: kTextKindChat,
          age: Duration.zero,
          body: 'where are you',
        ),
        message(msgId: 2, kind: kTextKindAnnouncement, age: Duration.zero),
      ]);

      final advisories = mesh.recentAdvisories;
      expect(advisories.length, 1);
      expect(advisories.single.msgId, 2);
      expect(advisories.single.isAnnouncement, isTrue);
    });

    test('newest first — the current route change outranks the last one', () {
      final mesh = MeshService();
      addTearDown(mesh.dispose);
      mesh.messages.addAll([
        message(
          msgId: 1,
          kind: kTextKindAnnouncement,
          age: const Duration(hours: 1),
        ),
        message(
          msgId: 2,
          kind: kTextKindAnnouncement,
          age: const Duration(minutes: 2),
        ),
        message(
          msgId: 3,
          kind: kTextKindAnnouncement,
          age: const Duration(minutes: 30),
        ),
      ]);

      expect(mesh.recentAdvisories.map((m) => m.msgId), [2, 3, 1]);
    });

    test('a stale advisory stops being promoted', () {
      // "Route closed ahead" has a short life. An old one sitting at the top
      // of the Home screen would compete with a live one.
      final mesh = MeshService();
      addTearDown(mesh.dispose);
      mesh.messages.addAll([
        message(
          msgId: 1,
          kind: kTextKindAnnouncement,
          age: kAdvisoryShelfLife * 2,
        ),
        message(
          msgId: 2,
          kind: kTextKindAnnouncement,
          age: const Duration(minutes: 5),
        ),
      ]);

      expect(mesh.recentAdvisories.map((m) => m.msgId), [2]);
    });

    test('an advisory from another Dindi still counts — that is the point', () {
      // An advisory reaches every phone in range regardless of group; it is
      // the one message type that is deliberately not Dindi-scoped.
      final mesh = MeshService();
      addTearDown(mesh.dispose);
      mesh.messages.add(
        message(
          msgId: 1,
          kind: kTextKindAnnouncement,
          age: Duration.zero,
          groupTag: 'ZZ',
        ),
      );

      expect(mesh.recentAdvisories.length, 1);
    });

    test('nothing to show when nothing has been broadcast', () {
      final mesh = MeshService();
      addTearDown(mesh.dispose);
      expect(mesh.recentAdvisories, isEmpty);
    });
  });
}
