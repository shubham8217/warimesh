// Smoke test — the generated counter-app test no longer applies since
// lib/main.dart is the WariMesh relay app, not the Flutter starter
// template. This confirms the role-select → sign-in gate lands a warkari
// and a volunteer on their own (different) shells. It does not (and
// cannot, without a real BLE stack) verify relay behavior over the air —
// that needs real devices.
//
// sqflite has no platform channel on a bare `flutter test` host run, so we
// swap in sqflite_common_ffi (a host-native SQLite implementation) just for
// this test process. Its I/O is real (not fake-clock), and so is the mesh
// service's cooldown timer once a shell is up — both are driven with
// tester.runAsync so their async gaps actually elapse, and both are given a
// moment to settle before the test ends so no real Timer is left pending
// when the widget tree is torn down. MeshService.bootstrap() also guards
// every platform-channel call (permissions, notifications, BLE, foreground
// service) with try/catch precisely so a missing plugin implementation
// here — or a real failure on a real device — degrades gracefully instead
// of aborting startup silently.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:warimesh/database_service.dart';
import 'package:warimesh/main.dart';

/// Stubs the on-device LLM platform channels (warimesh/llm + events) so the
/// volunteer shell's AssistantScreen — which constructs a LlmService — gets
/// a "no model installed" answer instead of a MissingPluginException. The
/// real channels only exist on an Android device; see LlmBridge.kt.
void _stubLlmChannels(WidgetTester tester) {
  const methodChannel = MethodChannel('warimesh/llm');
  const eventChannel = EventChannel('warimesh/llm/events');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    methodChannel,
    (call) async => <String, Object?>{
      'exists': false,
      'path': null,
      'sizeBytes': 0,
    },
  );
  tester.binding.defaultBinaryMessenger.setMockStreamHandler(
    eventChannel,
    MockStreamHandler.inline(
      onListen: (arguments, events) async {},
      onCancel: (arguments) async {},
    ),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // AppDatabase caches one open Database handle for the whole test
    // process (like the app itself does), so between tests we clear the
    // signed-in profile through that same handle rather than deleting the
    // underlying file — deleting a file out from under an already-open
    // handle doesn't reliably reset what it reads back.
    await UserDb.clear();
  });

  testWidgets('a volunteer picks their role, signs in, and reaches the volunteer dashboard', (tester) async {
    _stubLlmChannels(tester);
    await tester.runAsync(() async {
      await tester.pumpWidget(const WariMeshApp());
      await Future.delayed(const Duration(milliseconds: 900));
    });
    await tester.pump();

    // Nobody signed in yet on a fresh DB — role selection comes first.
    expect(find.text('Who\'s signing in?'), findsOneWidget);
    await tester.tap(find.text('Volunteer'));
    await tester.pump();

    expect(find.text('Volunteer sign-in'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Test Volunteer');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '555-0100');
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await Future.delayed(const Duration(milliseconds: 900));
    });
    await tester.pump();

    expect(find.textContaining('WariMesh'), findsWidgets);
    expect(find.text('Send SOS'), findsOneWidget);
    expect(find.text('Report Missing'), findsOneWidget);

    // Let MeshService.bootstrap()'s in-flight real async work (permissions,
    // DB, BLE adapter checks — all try/catch-guarded, see mesh_service.dart)
    // finish before the test ends and tears down the widget tree, so
    // nothing calls notifyListeners() on an already-disposed MeshService.
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 900)));
    await tester.pump();
  });

  testWidgets('a warkari picks their role, signs in, and reaches the warkari home screen', (tester) async {
    _stubLlmChannels(tester);
    await tester.runAsync(() async {
      await tester.pumpWidget(const WariMeshApp());
      await Future.delayed(const Duration(milliseconds: 900));
    });
    await tester.pump();

    expect(find.text('Who\'s signing in?'), findsOneWidget);
    await tester.tap(find.text('Warkari'));
    await tester.pump();

    expect(find.text('Warkari sign-in'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Full name'), 'Test Warkari');
    await tester.enterText(find.widgetWithText(TextFormField, 'Phone number'), '555-0200');
    // The sign-in form scrolls (the warkari flow adds the Create/Join Dindi
    // picker, which can push "Sign in" below the fold) — ListView only
    // inflates children near the viewport, same as ListView.builder, so the
    // button must be scrolled into view before it can be found or tapped.
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Sign in'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await Future.delayed(const Duration(milliseconds: 900));
    });
    await tester.pump();

    // The warkari shell greets by first name and has no volunteer-only
    // mesh diagnostics/report-form entry point.
    expect(find.textContaining('Namaskar, Test'), findsOneWidget);
    expect(find.text('Send SOS'), findsOneWidget);
    expect(find.text('Report Missing'), findsNothing);

    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 900)));
    await tester.pump();
  });
}
