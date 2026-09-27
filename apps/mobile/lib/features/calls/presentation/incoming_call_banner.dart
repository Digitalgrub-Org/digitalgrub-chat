import 'dart:async';
import 'dart:math';

import 'package:dg_chat/app/localization/localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Foreground ring: a banner over the top of the shell while someone calls.
///
/// This is deliberately an overlay rather than a screen takeover — the person
/// may be mid-sentence in another conversation, and an incoming call is an
/// offer, not a seizure. When the app is backgrounded the ordinary push
/// notification carries the news instead; the OS-level ringing experience is
/// CallKit/ConnectionService work, deferred with intent.
class IncomingCallBanner extends ConsumerStatefulWidget {
  const IncomingCallBanner({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<IncomingCallBanner> createState() => _IncomingCallBannerState();
}

class _IncomingCallBannerState extends ConsumerState<IncomingCallBanner> {
  IncomingCallRing? _ring;
  Timer? _expiry;

  /// Native incoming-call sessions in flight, by the uuid CallKit demands.
  final _nativeRings = <String, IncomingCallRing>{};
  StreamSubscription<CallEvent?>? _callkitEvents;
  final _random = Random.secure();

  /// Subscribed on the first native ring, not in initState: touching the
  /// plugin's event channel registers platform machinery that widget tests
  /// and ring-free sessions have no use for.
  void _ensureCallkitEvents() {
    _callkitEvents ??= FlutterCallkitIncoming.onEvent.listen(
      _onNativeEvent,
      onError: (Object _) {},
    );
  }

  void _onNativeEvent(CallEvent? event) {
    if (event == null) return;
    final id = event.body is Map ? event.body['id'] as String? : null;
    final ring = id == null ? null : _nativeRings[id];
    switch (event.event) {
      case Event.actionCallAccept:
        if (id != null) _nativeRings.remove(id);
        _stopRinging();
        if (ring != null && mounted) {
          // CallKit has one answer button; joining audio-first mirrors it,
          // and the camera is one tap away inside the call.
          openCall(context, ring.roomId, withVideo: false, ring: false);
          unawaited(FlutterCallkitIncoming.endCall(id!));
        }
      case Event.actionCallDecline || Event.actionCallTimeout:
        if (id != null) _nativeRings.remove(id);
        _stopRinging();
      default:
        break;
    }
  }

  String _uuid() {
    // CallKit insists on a uuid-shaped id; this is a plain v4.
    String hex(int n) =>
        List.generate(n, (_) => _random.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-'
        '${(8 + _random.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
  }

  Future<void> _showNative(IncomingCallRing ring) async {
    _ensureCallkitEvents();
    final id = _uuid();
    _nativeRings[id] = ring;
    await FlutterCallkitIncoming.showCallkitIncoming(
      CallKitParams(
        id: id,
        nameCaller: ring.senderName,
        appName: 'Digitalgrub Chat',
        handle: ring.roomName,
        type: 0,
        duration: 30000,
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          actionColor: '#FFBE00',
        ),
        ios: const IOSParams(
          supportsVideo: true,
          // voiceChat, not default: the mode decides the route iOS picks when
          // the session activates, and `default` lands on the loudspeaker.
          // voiceChat routes to the earpiece and turns on the echo cancellation
          // a call needs.
          audioSessionMode: 'voiceChat',
          ringtonePath: 'system_ringtone_default',
        ),
      ),
    );
  }

  void _show(IncomingCallRing ring) {
    // Recorded before the platform split: both surfaces ring, so both must
    // suppress the message notification for the same push.
    ref.read(ringingRoomProvider.notifier).state = ring.roomId;
    if (!kIsWeb) {
      // Phones ring like phones: system incoming-call surface and ringtone.
      // The in-app banner remains the web experience, where no such surface
      // exists.
      unawaited(_showNative(ring));
      return;
    }
    _expiry?.cancel();
    setState(() => _ring = ring);
    // Rings are short-lived by spec; a banner that lingers after the caller
    // gave up is an invitation to join an empty room.
    _expiry = Timer(const Duration(seconds: 30), _dismiss);
  }

  void _dismiss() {
    _expiry?.cancel();
    _stopRinging();
    if (mounted) setState(() => _ring = null);
  }

  void _stopRinging() {
    if (!mounted) return;
    ref.read(ringingRoomProvider.notifier).state = null;
  }

  void _accept(IncomingCallRing ring, {required bool video}) {
    _dismiss();
    openCall(context, ring.roomId, withVideo: video, ring: false);
  }

  @override
  void dispose() {
    _expiry?.cancel();
    unawaited(_callkitEvents?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(incomingRingsProvider, (previous, next) {
      final ring = next.asData?.value;
      if (ring == null) return;
      // Already talking, or already answering this very call: the banner
      // stays quiet rather than shouting over it. The joining check is what
      // stops the sync-delivered copy of a ring you answered from the lock
      // screen ringing at you again while the media connects.
      if (ref.read(activeCallProvider) != null) return;
      if (ref.read(joiningCallRoomProvider) == ring.roomId) return;
      _show(ring);
    });

    final ring = _ring;
    return Stack(
      children: [
        widget.child,
        if (ring != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(16),
                  color: Theme.of(context).colorScheme.inverseSurface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.ring_volume_rounded,
                          color: Theme.of(context).colorScheme.onInverseSurface,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.l10n.incomingCallFrom(ring.senderName),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onInverseSurface,
                                ),
                              ),
                              Text(
                                ring.roomName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface
                                      .withValues(alpha: .8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: context.l10n.callAcceptAudio,
                          onPressed: () => _accept(ring, video: false),
                          icon: const Icon(
                            Icons.call_rounded,
                            color: Color(0xFF34A853),
                          ),
                        ),
                        IconButton(
                          tooltip: context.l10n.callAcceptVideo,
                          onPressed: () => _accept(ring, video: true),
                          icon: const Icon(
                            Icons.videocam_rounded,
                            color: Color(0xFF34A853),
                          ),
                        ),
                        IconButton(
                          tooltip: context.l10n.callDecline,
                          onPressed: _dismiss,
                          icon: const Icon(
                            Icons.call_end_rounded,
                            color: Color(0xFFD93025),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
