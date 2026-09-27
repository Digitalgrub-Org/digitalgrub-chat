import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// One person's tile: their video when it flows, their initial when it
/// doesn't.
///
/// This is the only widget that knows what the domain's opaque video handle
/// contains, which keeps the engine swap-out surface to exactly one file.
class CallParticipantTile extends StatelessWidget {
  const CallParticipantTile({required this.participant, super.key});

  final CallParticipantView participant;

  @override
  Widget build(BuildContext context) {
    final track = participant.videoTrack;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1D242B),
          // The speaking ring is the only affordance that scales to a grid:
          // names are too small to scan while someone talks.
          border: participant.isSpeaking
              ? Border.all(color: const Color(0xFFFFBE00), width: 2)
              : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (track is lk.VideoTrack)
              lk.VideoTrackRenderer(
                track,
                // A shared screen is fit whole -- cropping a document to fill
                // a tile hides the edges of what someone is trying to show.
                // A camera fills the tile, the way faces are framed.
                fit: participant.isScreenShare
                    ? lk.VideoViewFit.contain
                    : lk.VideoViewFit.cover,
                // Seeing your own camera unmirrored reads as wrong -- but a
                // shared screen must never be mirrored, or its text is
                // backwards.
                mirrorMode: participant.isLocal && !participant.isScreenShare
                    ? lk.VideoViewMirrorMode.mirror
                    : lk.VideoViewMirrorMode.off,
              )
            else
              Center(
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: const Color(0xFFFFBE00),
                  child: Text(
                    participant.displayName.isEmpty
                        ? '?'
                        : participant.displayName[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101418),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 8,
              bottom: 8,
              right: 8,
              child: Row(
                children: [
                  if (!participant.hasAudio)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.mic_off_rounded,
                        size: 16,
                        color: Colors.white70,
                      ),
                    ),
                  Flexible(
                    child: Text(
                      participant.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        shadows: [Shadow(blurRadius: 4)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
