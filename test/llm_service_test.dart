// Round-trip test for the on-device LLM path: what happens on a real phone
// is LlmService (Dart) <-> LlmBridge (Kotlin) <-> Gemma model. No model
// file is present in CI, so this test replaces only the Kotlin side with a
// faithful mock that behaves exactly like LlmBridge.kt does on the platform
// channels ("warimesh/llm" + "warimesh/llm/events"): getModelInfo reports a
// model present, loadModel succeeds, and generate() streams back token
// events (kind=token, requestId, text, done) followed by kind=done — which
// is precisely what the ProgressListener in LlmBridge.kt emits.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:warimesh/llm_service.dart';

void main() {
  const methodChannel = MethodChannel('warimesh/llm');
  const eventChannel = EventChannel('warimesh/llm/events');

  final tokens = [
    'For heat',
    'stroke: move to shade,',
    ' cool with water, and',
    ' seek help.',
  ];
  final replies = <String>[];

  setUp(() {
    replies.clear();
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'getModelInfo':
              return <String, Object?>{
                'exists': true,
                'path':
                    '/data/user/0/com.example.warimesh/files/llm/gemma-3n-e2b-it-int4.litertlm',
                'sizeBytes': 3930000000,
              };
            case 'loadModel':
              return 'loaded';
            case 'generate':
              // Mimic LlmBridge.kt's ProgressListener: stream the reply in
              // token chunks on the event channel, then a done event.
              final args = (call.arguments as Map).cast<String, Object?>();
              final requestId = args['requestId'] as String? ?? '';
              Timer.run(() {
                for (final t in tokens) {
                  TestDefaultBinaryMessengerBinding
                      .instance
                      .defaultBinaryMessenger
                      .handlePlatformMessage(
                        eventChannel.name,
                        const StandardMethodCodec()
                            .encodeSuccessEnvelope(<String, Object?>{
                              'kind': 'token',
                              'requestId': requestId,
                              'text': t,
                              'done': false,
                            }),
                        (_) {},
                      );
                }
                TestDefaultBinaryMessengerBinding
                    .instance
                    .defaultBinaryMessenger
                    .handlePlatformMessage(
                      eventChannel.name,
                      const StandardMethodCodec().encodeSuccessEnvelope(
                        <String, Object?>{
                          'kind': 'done',
                          'requestId': requestId,
                        },
                      ),
                      (_) {},
                    );
              });
              return true;
            default:
              return null;
          }
        });
  });

  test(
    'prompt in → streamed reply out through LlmService.generate()',
    () async {
      final llm = LlmService();
      await llm.init();

      // Model file present on the mocked device → 'downloaded' (on disk,
      // not yet in memory). This is the Download → Load → Run flow.
      expect(llm.status, LlmStatus.downloaded);

      // Load (idempotent on the native side) → ready to chat.
      expect(await llm.loadModel(), isTrue);
      expect(llm.status, LlmStatus.ready);

      // Fire a real prompt through the same channel path the UI uses.
      final reply = await llm.generate('What do I do for heatstroke?');

      expect(reply, isNotNull);
      expect(
        reply,
        'For heatstroke: move to shade, cool with water, and seek help.',
      );
      expect(llm.history.length, 2);
      expect(llm.history[0].role, 'user');
      expect(llm.history[1].role, 'assistant');
      expect(llm.history[1].text, reply);
      expect(llm.busy, isFalse);

      llm.dispose();
    },
  );
}
