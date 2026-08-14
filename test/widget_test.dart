// Smoke test — the generated counter-app test no longer applies since
// lib/main.dart is the WariMesh relay app, not the Flutter starter
// template. This confirms the widget tree builds and the dashboard's
// primary actions are present. It does not (and cannot, without a real BLE
// stack) verify relay behavior over the air — that needs real devices.
//
// sqflite has no platform channel on a bare `flutter test` host run, so we
// swap in sqflite_common_ffi (an in-memory/host SQLite implementation) just
// for this test process. MeshService.bootstrap() also guards every
// platform-channel call (permissions, notifications, BLE, foreground
// service) with try/catch precisely so a missing plugin implementation
// here — or a real failure on a real device — degrades gracefully instead
// of aborting startup silently.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:warimesh/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('WariMeshApp builds and shows the home dashboard', (tester) async {
    await tester.pumpWidget(const WariMeshApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('WariMesh'), findsWidgets);
    expect(find.text('Send SOS'), findsOneWidget);
    expect(find.text('Report Missing'), findsOneWidget);
  });
}
