import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart' as paths;
import 'package:record/record.dart';

/// Records a voice message and hands back a sendable draft.
///
/// Owns the platform recorder and nothing else: the composer decides when to
/// start, discard or send, and renders its own recording UI from [elapsed].
class VoiceRecorder {
  /// Created on first use: the platform recorder registers itself over a
  /// method channel the instant it is constructed, which explodes in widget
  /// tests and costs startup work in every conversation that never records.
  AudioRecorder? _recorderInstance;
  AudioRecorder get _recorder => _recorderInstance ??= AudioRecorder();
  final _clock = Stream<void>.periodic(const Duration(seconds: 1));

  DateTime? _startedAt;
  StreamSubscription<void>? _ticker;
  void Function()? _onTick;

  bool get isRecording => _startedAt != null;

  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  /// Starts capturing, prompting for the microphone if needed. Returns false
  /// when permission is refused or no recorder is available.
  Future<bool> start({required void Function() onTick}) async {
    if (isRecording) return true;
    try {
      if (!await _recorder.hasPermission()) return false;
      final String path;
      if (kIsWeb) {
        // The web implementation records to a blob and ignores the path.
        path = 'voice.webm';
      } else {
        final dir = await paths.getTemporaryDirectory();
        path = '${dir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _recorder.start(
        RecordConfig(
          // Opus-in-webm is what browsers can produce; AAC is the native
          // container everywhere else. Both play everywhere the app runs.
          encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
          numChannels: 1,
        ),
        path: path,
      );
      _startedAt = DateTime.now();
      _onTick = onTick;
      _ticker = _clock.listen((_) => _onTick?.call());
      return true;
    } catch (_) {
      await _reset();
      return false;
    }
  }

  /// Stops and returns the recording as a draft, or null when it was too
  /// short to mean anything.
  Future<AttachmentDraft?> stop() async {
    if (!isRecording) return null;
    final duration = elapsed;
    try {
      final path = await _recorder.stop();
      await _reset();
      if (path == null) return null;
      // A sub-second blip is a mis-tap, not a message.
      if (duration.inMilliseconds < 800) return null;
      final bytes = await XFile(path).readAsBytes();
      return AttachmentDraft(
        bytes: bytes,
        fileName: kIsWeb ? 'voice-message.webm' : 'voice-message.m4a',
        mimeType: kIsWeb ? 'audio/webm' : 'audio/mp4',
        voiceDurationMs: duration.inMilliseconds,
      );
    } catch (_) {
      await _reset();
      return null;
    }
  }

  /// Stops and throws the recording away.
  Future<void> discard() async {
    if (!isRecording) return;
    try {
      await _recorderInstance?.stop();
    } catch (_) {}
    await _reset();
  }

  Future<void> _reset() async {
    _startedAt = null;
    _onTick = null;
    await _ticker?.cancel();
    _ticker = null;
  }

  Future<void> dispose() async {
    await discard();
    await _recorderInstance?.dispose();
  }
}
