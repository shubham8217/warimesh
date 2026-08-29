// WariMesh — Dart side of the on-device LLM assistant (Gemma-3n E2B).
//
// Talks to LlmBridge.kt over the "warimesh/llm" MethodChannel (control)
// and "warimesh/llm/events" EventChannel (token streaming). Everything is
// local: the model file lives in app-private storage and inference never
// touches the network — the app's whole reason for being is offline
// operation, and this is the "ask a volunteer-knowledgeable assistant"
// feature for when there's no signal to reach a camp coordinator.
//
// System prompt + live mesh context: the prompt builder below injects the
// signed-in volunteer's name, the current mesh state, and any active
// missing-person reports into the system prompt, so the assistant can
// answer "what's happening around me" questions without any connectivity.
// The wire protocol and report data are local-only by design (see the
// honesty note at the top of models.dart) — what the model "knows" is
// exactly what this phone knows.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'database_service.dart';
import 'mesh_service.dart';

/// The model file this build expects, resolved to app-private storage by
/// the native side. Keep in sync with LlmBridge.kt's MODEL_FILE.
const String kLlmModelFile = 'gemma-3n-e2b-it-int4.litertlm';

/// Download source for the Gemma-3n E2B (int4, LiteRT) model.
///
/// PRIMARY: this repo's GitHub Release `gemma-3n-e2b-v1` — the 3.65 GB
/// model is too big for a single git/GitHub file (100 MB cap), so it is
/// split into 4 equal assets (part00..part03) that the app downloads and
/// concatenates. No auth, no LFS, no license gate.
///
/// FALLBACK: ModelScope mirror of google/gemma-3n-E2B-it-litert-lm as a
/// single URL, used only if the release chunks fail.
const String kLlmReleaseBaseUrl =
    'https://github.com/RohitSwami33/Warimesh1/releases/download/gemma-3n-e2b-v1';
const int kLlmModelParts = 4;
const int kLlmModelPartBytes = 913956864; // every chunk is exactly this size
const int kLlmModelTotalBytes = 3655827456; // assembled size; verified after download
const String kLlmModelFallbackUrl =
    'https://modelscope.cn/models/google/gemma-3n-E2B-it-litert-lm/resolve/master/gemma-3n-E2B-it-int4.litertlm';

class LlmService extends ChangeNotifier {
  static const MethodChannel _method =
      MethodChannel('warimesh/llm');
  static const EventChannel _events =
      EventChannel('warimesh/llm/events');

  LlmService({this.mesh, this.volunteerName});

  /// Optional live context used to enrich the system prompt.
  final MeshService? mesh;
  final String? volunteerName;

  LlmStatus _status = LlmStatus.noModel;
  bool _modelExists = false;
  String? _modelPath;
  int _modelSizeBytes = 0;
  String? _lastError;
  double _downloadProgress = 0;
  bool _downloading = false;
  String _thinkingText = '';

  final List<LlmMessage> _history = [];
  StreamSubscription<dynamic>? _eventSub;
  int _requestCounter = 0;
  String _currentRequestId = '';
  bool _busy = false;

  // Single-subscription routing for token streaming (EventChannel can only
  // be listened once — see generate() vs _listen() double-subscribe bug).
  Completer<String>? _pendingCompleter;
  StringBuffer? _pendingBuffer;
  String _pendingRequestId = '';
  void Function(String partial)? _pendingOnDelta;

  LlmStatus get status => _status;
  bool get modelExists => _modelExists;
  String? get modelPath => _modelPath;
  int get modelSizeBytes => _modelSizeBytes;
  String? get lastError => _lastError;
  double get downloadProgress => _downloadProgress;
  bool get downloading => _downloading;
  String get thinkingText => _thinkingText;
  bool get busy => _busy;
  bool get canChat => _status == LlmStatus.ready && !_busy;
  List<LlmMessage> get history => List.unmodifiable(_history);

  /// Called by the UI once after constructing the service.
  Future<void> init() async {
    _listen();
    await refreshModelInfo();
  }

  /// App-private storage location for the model file. The native side uses
  /// the exact same path (see LlmBridge.kt), so a file downloaded here is
  /// what `loadModel` will load.
  Future<Directory> _modelDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/llm');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Downloads the model into app storage: GitHub Release chunks first
  /// (part00..part03, concatenated), ModelScope single-URL as fallback.
  /// The assembled file is size-verified, then renamed into place for
  /// `loadModel`. Returns true on success.
  Future<bool> downloadModel() async {
    if (_modelExists || _downloading) return false;
    _downloading = true;
    _downloadProgress = 0;
    _lastError = null;
    notifyListeners();

    final dir = await _modelDir();
    final target = File('${dir.path}/$kLlmModelFile');
    final partial = File('${target.path}.part');
    if (await partial.exists()) await partial.delete();

    var ok = await _downloadReleaseChunks(partial);
    if (!ok) {
      if (await partial.exists()) await partial.delete();
      ok = await _downloadSingleUrl(kLlmModelFallbackUrl, partial);
    }
    if (!ok) {
      if (await partial.exists()) await partial.delete();
      _lastError = _lastError ?? 'Download failed — check internet and retry.';
      _downloading = false;
      notifyListeners();
      return false;
    }
    // Size guard: catches truncation/corruption before the model ever
    // reaches loadModel.
    final size = await partial.length();
    if (size != kLlmModelTotalBytes) {
      await partial.delete();
      _lastError =
          'Downloaded file has wrong size ($size ≠ $kLlmModelTotalBytes) — retry the download.';
      _downloading = false;
      notifyListeners();
      return false;
    }
    if (await target.exists()) await target.delete();
    await partial.rename(target.path);
    await refreshModelInfo();
    _downloading = false;
    notifyListeners();
    return _modelExists;
  }

  /// Downloads part00..part03 from the GitHub Release and concatenates
  /// them into [dest]. Progress is per-chunk, smoothed within each chunk.
  Future<bool> _downloadReleaseChunks(File dest) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      final sink = dest.openWrite(mode: FileMode.write);
      var written = 0;
      for (var i = 0; i < kLlmModelParts; i++) {
        final partName = 'part${i.toString().padLeft(2, '0')}';
        final url = '$kLlmReleaseBaseUrl/$partName';
        final req = await client.getUrl(Uri.parse(url));
        final resp = await req.close();
        if (resp.statusCode != 200) {
          _lastError =
              'GitHub chunk $partName: HTTP ${resp.statusCode}. Trying fallback…';
          await sink.close();
          return false;
        }
        await for (final chunk in resp) {
          sink.add(chunk);
          written += chunk.length;
          // Smooth progress across all 4 chunks.
          _downloadProgress = (written / kLlmModelTotalBytes).clamp(0.0, 1.0);
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
      _downloadProgress = 1.0;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = 'GitHub chunk download failed: $e';
      return false;
    } finally {
      client.close();
    }
  }

  Future<bool> _downloadSingleUrl(String url, File dest) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 20);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        _lastError =
            'Fallback download failed (HTTP ${response.statusCode}).';
        return false;
      }
      final total = response.contentLength;
      final sink = dest.openWrite(mode: FileMode.write);
      int received = 0, lastPct = -1;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final pct = (received * 100 / total).toInt();
          if (pct != lastPct) {
            lastPct = pct;
            _downloadProgress = pct / 100.0;
            notifyListeners();
          }
        }
      }
      await sink.flush();
      await sink.close();
      client.close();
      _downloadProgress = 1.0;
      notifyListeners();
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  /// Removes the model file from the device. Returns true if a file was
  /// deleted.
  Future<bool> deleteModel() async {
    final dir = await _modelDir();
    final target = File('${dir.path}/$kLlmModelFile');
    final partial = File('${target.path}.part');
    var deleted = false;
    if (await target.exists()) {
      await target.delete();
      deleted = true;
    }
    if (await partial.exists()) {
      await partial.delete();
      deleted = true;
    }
    await refreshModelInfo();
    return deleted;
  }

  Future<void> refreshModelInfo() async {
    try {
      final info = await _method.invokeMethod<Map<Object?, Object?>>('getModelInfo');
      _modelExists = info?['exists'] == true;
      _modelPath = info?['path'] as String?;
      _modelSizeBytes = (info?['sizeBytes'] as num?)?.toInt() ?? 0;
      // 'downloaded' = file on disk but not yet loaded into memory (this
      // is the state after an app restart, or right after a download
      // before the user taps Load).
      _status = !_modelExists
          ? LlmStatus.noModel
          : (_status == LlmStatus.ready ? LlmStatus.ready : LlmStatus.downloaded);
    } on PlatformException catch (e) {
      _lastError = e.message;
      _status = LlmStatus.error;
    } on MissingPluginException {
      // Host platform channel absent (e.g. `flutter test` host run) —
      // behave as if no model is installed rather than crashing startup.
      _modelExists = false;
      _status = LlmStatus.noModel;
    }
    notifyListeners();
  }

  /// Loads the model into memory (cold start takes several seconds on
  /// device). Safe to call repeatedly; native side is idempotent.
  Future<bool> loadModel() async {
    _lastError = null;
    _status = LlmStatus.loading;
    notifyListeners();
    try {
      final res = await _method.invokeMethod<String>('loadModel');
      _status = res == 'loaded' || res == 'already_loaded'
          ? LlmStatus.ready
          : LlmStatus.error;
    } on PlatformException catch (e) {
      _lastError = e.message;
      _status = LlmStatus.error;
    }
    notifyListeners();
    return _status == LlmStatus.ready;
  }

  /// Streams a full response for [prompt]. Returns the accumulated text, or
  /// null if the request could not start. Token events arrive on the event
  /// channel; [onDelta] (optional) is called with each partial token for
  /// live typing UI.
  Future<String?> generate(String prompt, {void Function(String partial)? onDelta}) async {
    if (!canChat) return null;
    _busy = true;
    _currentRequestId = 'req${_requestCounter++}';
    _thinkingText = '';
    notifyListeners();

    final sb = StringBuffer();
    _pendingBuffer = sb;
    _pendingRequestId = _currentRequestId;
    _pendingOnDelta = onDelta;
    final completer = Completer<String>();
    _pendingCompleter = completer;
    try {
      await _method.invokeMethod<bool>('generate', {
        'requestId': _currentRequestId,
        'prompt': await _buildPrompt(prompt),
      });
      // Tokens/done arrive on _listen()'s single EventChannel subscription
      // and are routed via _pending* above. This double-subscribe was the bug:
      // EventChannel only supports one listener — second listen throws
      // PlatformException 'already listening' / Bad state, so busy never cleared.
      // (handler moved to _listen — see below)
      final text = await completer.future.timeout(const Duration(minutes: 5));
      _history.add(LlmMessage(role: 'user', text: prompt));
      _history.add(LlmMessage(role: 'assistant', text: text));
      return text;
    } on PlatformException catch (e) {
      _lastError = e.message;
      return null;
    } on TimeoutException {
      _lastError = 'Response timed out — the model may be busy or the phone is thermal-throttling.';
      return null;
    } finally {
      _pendingCompleter = null;
      _pendingBuffer = null;
      _pendingRequestId = '';
      _pendingOnDelta = null;
      _busy = false;
      _thinkingText = '';
      notifyListeners();
    }
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  /// Builds the prompt sent to the model: a system prompt that turns the
  /// model into a field assistant for WariMesh volunteers and warkaris,
  /// plus a compact snapshot of this phone's live mesh/report state (the
  /// only context an offline model can have), then the user's question.
  Future<String> _buildPrompt(String userText) async {
    final b = StringBuffer()
      ..writeln('You are the WariMesh assistant, an offline field companion on a phone at a walking pilgrimage (the Wari). You help VOLUNTEERS and WARKARIS (pilgrims) in emergencies when there is no mobile network and no healthcare worker nearby.')
      ..writeln()
      ..writeln('Your job:')
      ..writeln('- Answer queries about first aid and emergencies: snake bites, heat stroke, dehydration, dizziness, exhaustion, wounds, insect stings, and similar.')
      ..writeln('- Respond with the IMMEDIATE steps to take, in short numbered points.')
      ..writeln('- Always end with: contact a healthcare worker ASAP. These are only immediate first-aid suggestions, not professional medical advice.')
      ..writeln('- Keep answers short, calm, and practical. Use simple language.')
      ..writeln('- If asked anything unrelated to the pilgrimage/emergency context, briefly answer and steer back to safety.')
      ..writeln('- Never claim to be a doctor. Always remind that professional help is needed as soon as possible.');

    final name = volunteerName?.trim();
    if (name != null && name.isNotEmpty) {
      b.writeln('The person asking is named $name.');
    }

    final m = mesh;
    if (m != null) {
      b.writeln('Live mesh status on this phone:');
      b.writeln('- device label: ${m.deviceLabel}');
      b.writeln('- scanning: ${m.scanning}');
      b.writeln('- bluetooth on: ${m.bluetoothOn}');
      b.writeln('- demo mode: ${m.demoMode}');
      b.writeln('- messages seen: ${m.seenCount}');
      if (m.log.isNotEmpty) {
        b.writeln('- recent activity: ${m.log.take(5).map((e) => e.text).join(' | ')}');
      }
    }

    try {
      final reports = await LostReportsDb.all();
      final active = reports.where((r) => !r.found).toList();
      if (active.isNotEmpty) {
        b.writeln('Active missing-person reports on this phone:');
        for (final r in active.take(5)) {
          b.writeln('- ${r.name} (${r.age.isEmpty ? 'age unknown' : r.age}): ${r.description} — last seen: ${r.lastSeenLocation.isEmpty ? 'unknown' : r.lastSeenLocation}');
        }
      } else {
        b.writeln('No active missing-person reports on this phone.');
      }
    } catch (_) {
      b.writeln('(Could not read local missing-person reports.)');
    }

    b
      ..writeln()
      ..writeln('The person asks: $userText');
    return b.toString();
  }

  void _listen() {
    try {
      _eventSub ??= _events.receiveBroadcastStream().listen((event) {
        final c = _pendingCompleter;
        if (c == null || c.isCompleted) return;
        final map = event as Map;
        if (map['requestId'] != _pendingRequestId) return;
        if (map['kind'] == 'token') {
          var text = (map['text'] as String? ?? '')
              .replaceAll('<end_of_turn>', '')
              .replaceAll('<start_of_turn>', '')
              .replaceAll('<eos>', '')
              .replaceAll('\u200D', '')
              .replaceAll('\u200B', '')
              .replaceAll('\uFE0F', '')
              .replaceAll('\uD83E\uDD39', '');
          text = text.replaceAllMapped(RegExp(r'(.)\1{4,}'), (m) => m.group(1)!);
          if (text.isEmpty) return;
          _pendingBuffer?.write(text);
          _thinkingText = _pendingBuffer.toString();
          _pendingOnDelta?.call(text);
          notifyListeners();
        } else if (map['kind'] == 'done') {
          c.complete(_pendingBuffer.toString().trimRight());
        }
      });
    } on MissingPluginException {
      // No host implementation (e.g. `flutter test` host run) — generation
      // simply won't be available; nothing to stream.
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}

enum LlmStatus {
  noModel, // no file on disk — show Download
  downloaded, // file on disk, not in memory — show Load
  loading, // loadModel in progress
  ready, // loaded and ready to chat
  error,
}

class LlmMessage {
  final String role; // 'user' | 'assistant'
  final String text;
  const LlmMessage({required this.role, required this.text});
}
