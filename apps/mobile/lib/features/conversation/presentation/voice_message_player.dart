import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

/// Plays a voice message in place: play/pause, a position bar, and the
/// remaining time. No filename — a spoken message is not a document.
class VoiceMessagePlayer extends StatefulWidget {
  const VoiceMessagePlayer({required this.attachment, super.key});

  final MessageAttachment attachment;

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  final _player = AudioPlayer();
  bool _preparing = false;
  bool _prepared = false;
  bool _failed = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final url = widget.attachment.url;
    if (url == null) {
      setState(() => _failed = true);
      return;
    }
    setState(() => _preparing = true);
    try {
      if (kIsWeb) {
        // A browser's media element cannot send the authorization header the
        // media endpoint requires, so the bytes are fetched with credentials
        // and handed over as a data URI. Voice notes are small enough that
        // this stays cheap.
        final response = await http.get(
          url,
          headers: widget.attachment.headers,
        );
        if (response.statusCode != 200) throw Exception('media unavailable');
        await _player.setUrl(
          Uri.dataFromBytes(
            response.bodyBytes,
            mimeType: widget.attachment.mimeType ?? 'audio/webm',
          ).toString(),
        );
      } else {
        await _player.setAudioSource(
          AudioSource.uri(url, headers: widget.attachment.headers),
        );
      }
      if (mounted) setState(() => _prepared = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _toggle() async {
    if (!_prepared) {
      await _prepare();
      if (!_prepared || !mounted) return;
    }
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  String _format(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_off_rounded, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Text(
            context.l10n.attachmentUnavailable,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      );
    }

    final total = Duration(milliseconds: widget.attachment.durationMs ?? 0);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: StreamBuilder<PlayerState>(
        stream: _player.playerStateStream,
        builder: (context, stateSnapshot) {
          final playing = stateSnapshot.data?.playing ?? false;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filledTonal(
                tooltip: playing
                    ? context.l10n.voicePause
                    : context.l10n.voicePlay,
                onPressed: _preparing ? null : _toggle,
                icon: _preparing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  builder: (context, positionSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;
                    final length = _player.duration ?? total;
                    final progress = length.inMilliseconds == 0
                        ? 0.0
                        : (position.inMilliseconds / length.inMilliseconds)
                              .clamp(0.0, 1.0);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _format(
                            playing || position > Duration.zero
                                ? position
                                : (length == Duration.zero ? total : length),
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
