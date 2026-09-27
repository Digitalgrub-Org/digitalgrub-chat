import 'dart:async';

import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/layout/breakpoints.dart';
import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/calls/application/native_pip.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:dg_chat/features/calls/presentation/call_fullscreen.dart';
import 'package:dg_chat/features/calls/presentation/call_reactions.dart';
import 'package:dg_chat/features/calls/presentation/call_video_view.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/conversation/presentation/conversation_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The in-call screen: a grid of participants and the control row.
///
/// Deliberately dark regardless of theme, the way every camera surface is —
/// video reads better against black, and a blinding white screen next to your
/// face at night is hostile.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    required this.roomId,
    required this.withVideo,
    required this.ring,
    this.guestName,
    super.key,
  });

  final String roomId;
  final bool withVideo;

  /// Set when a meeting guest is joining: their chosen display name. The
  /// join skips Matrix entirely and [roomId] may be a meeting code.
  final String? guestName;

  /// True when this user started the call; joining an existing one must not
  /// re-ring everyone.
  final bool ring;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  CallController? _controller;
  CallFailureCode? _failure;
  bool _speakerOn = false;
  bool _reactionsOpen = false;

  /// Whether the room's messages are open beside (or over) the video.
  ///
  /// A guest has no account and so no room to read; for everyone else this is
  /// the same conversation the call lives in, which is what people expect
  /// when they type "can you hear me?" mid-call.
  bool _chatOpen = false;

  /// Android has shrunk the app to a floating window. Only the video is
  /// worth the space; the header, the controls and the chat go.
  bool _inPip = false;
  Timer? _clock;

  bool get _canChat => widget.guestName == null;

  /// The participant list, live for as long as it is open.
  ///
  /// A sheet rather than a pane: it is consulted, not watched. The video and
  /// controls stay behind it and a swipe puts it away.
  Future<void> _showPeople(CallController controller) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StreamBuilder<CallSnapshot>(
        stream: controller.changes,
        initialData: controller.current,
        builder: (context, snapshot) => CallPeopleSheet(
          call: snapshot.data ?? controller.current,
          onMute: (id) => controller.requestMute(participantId: id),
          onMuteAll: () => controller.requestMute(),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    NativePip.listen((inPip) {
      if (mounted) setState(() => _inPip = inPip);
    });
    unawaited(NativePip.setEligible(true));
    unawaited(_join());
    // Redraws the duration readout; nothing else changes once connected.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _join() async {
    // The call now outlives this screen, so coming back to it must pick up
    // the one already running rather than start a second one in the room.
    final existing = ref.read(activeCallProvider);
    if (existing != null && existing.current.roomId == widget.roomId) {
      setState(() => _controller = existing);
      return;
    }
    // Read once, up front: this notifier outlives the screen, and the clear
    // below has to run even when the screen is gone.
    final joining = ref.read(joiningCallRoomProvider.notifier);
    try {
      final repository = await ref.read(callRepositoryProvider.future);
      // Marked after that first await rather than before it: this method is
      // started from initState, which runs inside a build, and Riverpod
      // rightly refuses provider writes there. Still well ahead of the
      // connect, which is all the marker has to beat -- it exists to stop the
      // banner ringing for a call already being joined.
      joining.state = widget.roomId;
      final guestName = widget.guestName;
      final controller = guestName != null
          ? await repository.joinMeetingAsGuest(
              widget.roomId,
              displayName: guestName,
              withVideo: widget.withVideo,
            )
          : await repository.startOrJoin(
              widget.roomId,
              withVideo: widget.withVideo,
              ring: widget.ring,
            );
      if (!mounted) {
        await controller.hangUp();
        return;
      }
      setState(() => _controller = controller);
      // A meeting guest's [widget.roomId] is the meeting code while the
      // controller carries the room id the code resolved to, so the re-entry
      // check at the top of this method can never match for them. Whatever the
      // previous call was, it is not this one: end it rather than leave it
      // connected with an open microphone and nothing on screen to stop it.
      final replaced = ref.read(activeCallProvider);
      if (replaced != null && !identical(replaced, controller)) {
        unawaited(replaced.hangUp());
      }
      ref.read(activeCallProvider.notifier).state = controller;
      if (!kIsWeb) {
        // Both directions, always. Only ever switching the speaker ON left a
        // voice call on whatever route the platform happened to choose, and on
        // iOS that is the loudspeaker -- so voice calls came out of the back of
        // the phone with the earpiece silent, which is not a call, it is a
        // broadcast. A video call in the ear is nobody's intent either, hence
        // the one place the speaker is wanted.
        _speakerOn = widget.withVideo || controller.current.isGroup;
        unawaited(controller.setSpeakerphone(_speakerOn));
      }
    } on CallFailure catch (failure) {
      if (mounted) setState(() => _failure = failure.code);
    } catch (_) {
      if (mounted) setState(() => _failure = CallFailureCode.unknown);
    } finally {
      // Deliberately not gated on `mounted`. Backing out while the call is
      // still connecting disposes this screen, and a marker left behind
      // silences every later ring for the room -- the banner reads it to
      // avoid re-ringing a call you are already joining.
      if (joining.state == widget.roomId) joining.state = null;
    }
  }

  Future<void> _hangUp() async {
    final controller = _controller;
    _controller = null;
    ref.read(activeCallProvider.notifier).state = null;
    await controller?.hangUp();
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      // A guest arrived straight from a link, so there is nothing under this
      // screen to pop back to. Splash sorts out where they belong.
      context.go(AppRoutes.splash);
    }
  }

  @override
  void dispose() {
    unawaited(NativePip.setEligible(false));
    NativePip.stopListening();
    _clock?.cancel();
    // Leaving the screen deliberately does NOT leave the call any more. That
    // rule existed because an ongoing call nobody can see is an open
    // microphone; the shell now carries a bar for the live call, so it is
    // visible from everywhere and stepping into a chat mid-call costs
    // nothing. Hanging up is the hang-up button's job, here or on the bar.
    super.dispose();
  }

  String _durationText(CallSnapshot snapshot) {
    final started = snapshot.startedAt;
    if (started == null || snapshot.state != CallConnectionState.connected) {
      return '';
    }
    final elapsed = DateTime.now().difference(started);
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final hours = elapsed.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    if (failure != null) {
      return _CallScaffold(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.call_end_rounded,
                color: Colors.white70,
                size: 48,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                failure == CallFailureCode.permissionDenied
                    ? context.l10n.callPermissionDenied
                    : context.l10n.callFailed,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(context.l10n.close),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return _CallScaffold(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.callConnecting,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<CallSnapshot>(
      stream: controller.changes,
      initialData: controller.current,
      builder: (context, snapshot) {
        final call = snapshot.data ?? controller.current;
        if (call.state == CallConnectionState.ended) {
          // The far side hung up, or the connection died for good.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_hangUp());
          });
        }
        if (_inPip) {
          // The floating window: video only, edge to edge. Tapping it brings
          // the app back, and the full screen with it.
          return _CallScaffold(child: _ParticipantGrid(call: call));
        }
        // Messages arriving while the panel is closed put a dot on the
        // button. Open, the panel is the room and reads them itself.
        final unread = !_canChat || _chatOpen
            ? 0
            : ref
                      .watch(chatListProvider)
                      .valueOrNull
                      ?.where((chat) => chat.roomId == widget.roomId)
                      .firstOrNull
                      ?.unreadCount ??
                  0;
        final sidePanel = context.windowSize.hasSidePanes;
        final grid = Stack(
          fit: StackFit.expand,
          children: [
            _ParticipantGrid(call: call),
            CallReactionsOverlay(reactions: controller.reactions),
          ],
        );
        final chat = _chatOpen
            ? _InCallChat(
                roomId: widget.roomId,
                onClose: () => setState(() => _chatOpen = false),
              )
            : null;
        return _CallScaffold(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    children: [
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              call.state == CallConnectionState.reconnecting
                                  ? context.l10n.callReconnecting
                                  : _durationText(call),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        context.l10n.callParticipantCount(
                          call.participants.length,
                        ),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                  ),
                ),
                Expanded(
                  // Wide: the panel sits beside the video, the way a meeting
                  // app does it, so a shared screen and the chat about it are
                  // both in view. Narrow: the panel takes the video's place
                  // and the controls stay put underneath -- you can still
                  // mute or hang up while reading, which a sheet drawn over
                  // the whole call would take away.
                  child: chat == null
                      ? grid
                      : sidePanel
                      ? Row(
                          children: [
                            Expanded(child: grid),
                            SizedBox(width: 380, child: chat),
                          ],
                        )
                      : chat,
                ),
                if (_reactionsOpen)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Center(
                      child: CallReactionBar(
                        onPick: (emoji) {
                          unawaited(controller.sendReaction(emoji));
                          setState(() => _reactionsOpen = false);
                        },
                      ),
                    ),
                  ),
                _ControlBar(
                  call: call,
                  speakerOn: _speakerOn,
                  onToggleMic: () => controller.setMicEnabled(!call.micEnabled),
                  onToggleCamera: () =>
                      controller.setCameraEnabled(!call.cameraEnabled),
                  onSwitchCamera: controller.switchCamera,
                  reactionsOpen: _reactionsOpen,
                  onToggleReactions: () =>
                      setState(() => _reactionsOpen = !_reactionsOpen),
                  chatOpen: _chatOpen,
                  unreadChat: unread,
                  onToggleChat: _canChat
                      ? () => setState(() => _chatOpen = !_chatOpen)
                      : null,
                  onToggleHand: () => controller.setHandRaised(
                    !(call.participants
                            .where((p) => p.isLocal && !p.isScreenShare)
                            .firstOrNull
                            ?.handRaised ??
                        false),
                  ),
                  onShowPeople: () => _showPeople(controller),
                  onToggleScreenShare: kIsWeb
                      ? () => controller.setScreenShareEnabled(
                          !call.isScreenSharing,
                        )
                      : null,
                  onToggleSpeaker: kIsWeb
                      ? null
                      : () async {
                          await controller.setSpeakerphone(!_speakerOn);
                          if (mounted) {
                            setState(() => _speakerOn = !_speakerOn);
                          }
                        },
                  onHangUp: _hangUp,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CallScaffold extends StatelessWidget {
  const _CallScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF101418), body: child);
  }
}

/// The participant grid, exposed for widget tests.
///
/// The grid is an implementation detail of this screen, but its screen-share
/// behaviour is worth testing on its own -- driving it through the whole call
/// screen would need a live LiveKit room.
@visibleForTesting
typedef ParticipantGridForTest = _ParticipantGrid;

class _ParticipantGrid extends StatefulWidget {
  const _ParticipantGrid({required this.call});

  final CallSnapshot call;

  @override
  State<_ParticipantGrid> createState() => _ParticipantGridState();
}

class _ParticipantGridState extends State<_ParticipantGrid> {
  /// The participant whose tile fills the call area, if any.
  ///
  /// Started as a screen-share escape hatch and then asked for everywhere: a
  /// grid of faces is right for a meeting and wrong for the one person you
  /// are actually talking to. Any tile can be pinned; the pin clears itself
  /// when that participant leaves, so the grid does not come back stuck in a
  /// layout with nothing to fill it.
  String? _expandedId;
  final _fullscreen = createCallFullscreen();

  @override
  void dispose() {
    // Leaving the call while expanded must not strand the browser in
    // fullscreen with no way back to the app.
    if (_expandedId != null) _fullscreen.exit();
    super.dispose();
  }

  @override
  void didUpdateWidget(_ParticipantGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = _expandedId;
    if (id != null && !widget.call.participants.any((p) => p.id == id)) {
      _expandedId = null;
      _fullscreen.exit();
    }
  }

  void _toggle(String id) {
    final wasExpanded = _expandedId != null;
    setState(() => _expandedId = _expandedId == id ? null : id);
    // Called straight from the tap, which is the only time a browser will
    // honour a fullscreen request. Moving the pin from one tile to another
    // stays in fullscreen rather than flickering out and back in.
    if (_expandedId != null && !wasExpanded) {
      _fullscreen.enter();
    } else if (_expandedId == null) {
      _fullscreen.exit();
    }
  }

  Widget _tile(CallParticipantView participant) => Padding(
    padding: const EdgeInsets.all(AppSpacing.xs),
    child: _ExpandableTile(
      expanded: _expandedId == participant.id,
      handRaised: participant.handRaised,
      onToggle: () => _toggle(participant.id),
      child: CallParticipantTile(participant: participant),
    ),
  );

  CallSnapshot get call => widget.call;

  @override
  Widget build(BuildContext context) {
    final participants = call.participants;
    if (participants.isEmpty) {
      return Center(
        child: Text(
          context.l10n.callWaitingForOthers,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    // Pinned: that one tile is the whole call area, whatever else is going
    // on. didUpdateWidget clears the pin when its participant leaves, so a
    // stale id cannot reach this lookup.
    final pinned = participants.where((p) => p.id == _expandedId).firstOrNull;
    if (pinned != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: _tile(pinned),
      );
    }
    // A shared screen is the thing people are looking at, so it takes the top
    // two-thirds and everyone else lines up below it. Only the first shared
    // screen is promoted -- the control bar already limits sharing to one at a
    // time, so a second would only appear mid-handover.
    final screenIndex = participants.indexWhere((p) => p.isScreenShare);
    if (screenIndex >= 0) {
      final screen = participants[screenIndex];
      final rest = [
        for (var i = 0; i < participants.length; i++)
          if (i != screenIndex) participants[i],
      ];
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            // The share takes two-thirds and the faces line up underneath.
            // Pinning either kind is handled above, before this layout.
            Expanded(flex: 2, child: _tile(screen)),
            if (rest.isNotEmpty)
              Expanded(
                child: Row(
                  children: [for (final p in rest) Expanded(child: _tile(p))],
                ),
              ),
          ],
        ),
      );
    }
    // The grid must FIT — a call layout that scrolls is a call layout that
    // hides people, which is exactly how a phone's video ended up invisible
    // in a short browser window while the count read "2 in call". Columns
    // and rows are chosen so every tile is on screen at once, portrait or
    // landscape.
    return LayoutBuilder(
      builder: (context, constraints) {
        final n = participants.length;
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        var columns = 1;
        var best = 0.0;
        for (var candidate = 1; candidate <= n; candidate++) {
          final rows = (n / candidate).ceil();
          final tileWidth = width / candidate;
          final tileHeight = height / rows;
          // The layout with the largest usable tile wins; a mild preference
          // for wider-than-tall keeps faces framed like cameras frame them.
          final score =
              (tileWidth < tileHeight * 1.6 ? tileWidth : tileHeight * 1.6) *
              tileHeight;
          if (score > best) {
            best = score;
            columns = candidate;
          }
        }
        final rows = (n / columns).ceil();
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            children: [
              for (var row = 0; row < rows; row++)
                Expanded(
                  child: Row(
                    children: [
                      for (
                        var index = row * columns;
                        index < (row + 1) * columns && index < n;
                        index++
                      )
                        Expanded(child: _tile(participants[index])),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.call,
    required this.speakerOn,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onSwitchCamera,
    required this.reactionsOpen,
    required this.onToggleReactions,
    required this.chatOpen,
    required this.unreadChat,
    required this.onToggleChat,
    required this.onToggleHand,
    required this.onShowPeople,
    required this.onToggleScreenShare,
    required this.onToggleSpeaker,
    required this.onHangUp,
  });

  final CallSnapshot call;
  final bool speakerOn;
  final bool reactionsOpen;
  final VoidCallback onToggleReactions;
  final bool chatOpen;
  final int unreadChat;

  /// Null for a guest, who has no room to read. The control is then absent
  /// rather than disabled -- a button that can only ever say no is noise.
  final VoidCallback? onToggleChat;
  final Future<void> Function() onToggleHand;
  final VoidCallback onShowPeople;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final Future<void> Function() onSwitchCamera;
  final Future<void> Function()? onToggleScreenShare;
  final Future<void> Function()? onToggleSpeaker;
  final Future<void> Function() onHangUp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          _RoundControl(
            tooltip: call.micEnabled
                ? context.l10n.callMuteMic
                : context.l10n.callUnmuteMic,
            icon: call.micEnabled ? Icons.mic_rounded : Icons.mic_off_rounded,
            active: call.micEnabled,
            onPressed: onToggleMic,
          ),
          _RoundControl(
            tooltip: call.cameraEnabled
                ? context.l10n.callCameraOff
                : context.l10n.callCameraOn,
            icon: call.cameraEnabled
                ? Icons.videocam_rounded
                : Icons.videocam_off_rounded,
            active: call.cameraEnabled,
            onPressed: onToggleCamera,
          ),
          if (call.cameraEnabled && !kIsWeb)
            _RoundControl(
              tooltip: context.l10n.callSwitchCamera,
              icon: Icons.cameraswitch_rounded,
              active: true,
              onPressed: () => onSwitchCamera(),
            ),
          _RoundControl(
            tooltip: context.l10n.callReact,
            icon: reactionsOpen
                ? Icons.emoji_emotions_rounded
                : Icons.emoji_emotions_outlined,
            active: reactionsOpen,
            onPressed: onToggleReactions,
          ),
          Builder(
            builder: (context) {
              final me = call.participants
                  .where((p) => p.isLocal && !p.isScreenShare)
                  .firstOrNull;
              final raised = me?.handRaised ?? false;
              return _RoundControl(
                tooltip: raised
                    ? context.l10n.callLowerHand
                    : context.l10n.callRaiseHand,
                icon: raised ? Icons.pan_tool_rounded : Icons.pan_tool_outlined,
                active: raised,
                onPressed: () => onToggleHand(),
              );
            },
          ),
          _RoundControl(
            tooltip: context.l10n.callPeople,
            icon: Icons.people_alt_rounded,
            active: false,
            // Hands up while the list is closed are the one thing worth a
            // dot: they are asking for you, not merely present.
            badge: call.participants
                .where((p) => p.handRaised && !p.isLocal)
                .length,
            onPressed: onShowPeople,
          ),
          if (onToggleChat != null)
            _RoundControl(
              tooltip: chatOpen
                  ? context.l10n.callCloseChat
                  : context.l10n.callChat,
              icon: chatOpen
                  ? Icons.chat_bubble_rounded
                  : Icons.chat_bubble_outline_rounded,
              active: chatOpen,
              badge: unreadChat,
              onPressed: onToggleChat,
            ),
          if (onToggleScreenShare != null)
            Builder(
              builder: (context) {
                // Single sharer at a time: the SFU would carry two, but two
                // shared screens in a small grid is noise. If someone else is
                // already sharing, the button says so and does nothing.
                final othersSharing = call.participants.any(
                  (p) => p.isScreenShare && !p.isLocal,
                );
                final sharing = call.isScreenSharing;
                return _RoundControl(
                  tooltip: othersSharing
                      ? context.l10n.callSomeoneSharing
                      : sharing
                      ? context.l10n.callStopSharing
                      : context.l10n.callShareScreen,
                  icon: sharing
                      ? Icons.stop_screen_share_rounded
                      : Icons.screen_share_rounded,
                  active: sharing,
                  onPressed: othersSharing
                      ? null
                      : () => onToggleScreenShare!(),
                );
              },
            ),
          if (onToggleSpeaker != null)
            _RoundControl(
              tooltip: context.l10n.callSpeaker,
              icon: speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
              active: speakerOn,
              onPressed: () => onToggleSpeaker!(),
            ),
          _RoundControl(
            tooltip: context.l10n.callHangUp,
            icon: Icons.call_end_rounded,
            active: true,
            background: const Color(0xFFD93025),
            onPressed: () => onHangUp(),
          ),
        ],
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
    this.background,
    this.badge = 0,
  });

  final String tooltip;
  final IconData icon;
  final bool active;

  /// Unread count shown as a dot on the control. A dot rather than the
  /// number: at this size a number is unreadable, and "something new" is the
  /// whole message.
  final int badge;

  /// Null disables the control -- used when someone else is already sharing.
  final VoidCallback? onPressed;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final control = Material(
      color: background ?? (active ? Colors.white24 : Colors.white10),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Icon(
            icon,
            color: callControlIconColor(
              active: active,
              enabled: onPressed != null,
              hasBackground: background != null,
            ),
            size: 26,
          ),
        ),
      ),
    );
    return Tooltip(
      message: tooltip,
      child: badge <= 0
          ? control
          : Stack(
              clipBehavior: Clip.none,
              children: [
                control,
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    key: const ValueKey('call-control-badge'),
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFE5484D),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Colour for a call-control icon, against the screen's near-black.
///
/// Three states, not two. The old rule had only "active" and "everything
/// else", and everything else was white38 -- fine for a muted microphone,
/// where dimness reads as "off", but wrong for screen sharing, whose resting
/// state is simply "not sharing". At 38% on black that button looked disabled
/// every moment it was usable, which is most of them.
Color callControlIconColor({
  required bool active,
  required bool enabled,
  required bool hasBackground,
}) {
  // Genuinely unavailable -- someone else is already sharing.
  if (!enabled) return Colors.white24;
  // On, or a control that carries its own colour (hang up).
  if (active || hasBackground) return Colors.white;
  // Available, just not on. Legible enough to invite a press.
  return Colors.white70;
}

/// A participant tile with a corner control to fill the call area and put
/// it back.
///
/// The whole tile is also a tap target: reaching for a small icon is the
/// wrong ask on a phone, and double-tapping video to fill the screen is a
/// gesture people already have. The button stays because a tap target with
/// no visible affordance is one nobody discovers.
class _ExpandableTile extends StatelessWidget {
  const _ExpandableTile({
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.handRaised = false,
  });

  final bool expanded;
  final bool handRaised;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onDoubleTap: onToggle,
          // Opaque so the double-tap lands on the video rather than falling
          // through to whatever is behind it.
          behavior: HitTestBehavior.opaque,
          child: child,
        ),
        if (handRaised)
          Positioned(
            left: AppSpacing.sm,
            top: AppSpacing.sm,
            child: Container(
              key: const ValueKey('hand-chip'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFFBE00),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.pan_tool_rounded,
                    size: 14,
                    color: Colors.black,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.callHandRaised,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          right: AppSpacing.sm,
          top: AppSpacing.sm,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: expanded
                  ? context.l10n.callExitFullScreen
                  : context.l10n.callFullScreen,
              iconSize: 20,
              onPressed: onToggle,
              icon: Icon(
                expanded
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The room's conversation, drawn as a panel inside the call.
///
/// The same screen as the chat itself, so the composer, attachments, replies
/// and read marking all come along -- there is no second, lesser chat to keep
/// in step. It also marks the room as on screen, so a push for it is
/// suppressed rather than notifying about a message you are reading.
///
/// The call surface is black regardless of theme; the panel is not, because
/// messages are prose and prose reads best on the theme's own surface.
class _InCallChat extends StatelessWidget {
  const _InCallChat({required this.roomId, required this.onClose});

  final String roomId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: ConversationScreen(
          key: ValueKey('in-call-chat:$roomId'),
          roomId: roomId,
          embedded: true,
          onClose: onClose,
        ),
      ),
    );
  }
}

/// Who is in the call, with what a moderator may do about them.
///
/// Screen-share tiles are folded into their person: the list is of people,
/// and a person sharing a screen is still one person.
class CallPeopleSheet extends StatelessWidget {
  const CallPeopleSheet({
    required this.call,
    required this.onMute,
    required this.onMuteAll,
    super.key,
  });

  final CallSnapshot call;
  final Future<void> Function(String participantId) onMute;
  final Future<void> Function() onMuteAll;

  @override
  Widget build(BuildContext context) {
    final people = call.participants.where((p) => !p.isScreenShare).toList()
      // Hands first: they are the ones asking for a turn. Then the local
      // person, then everyone else as they came.
      ..sort((a, b) {
        if (a.handRaised != b.handRaised) return a.handRaised ? -1 : 1;
        if (a.isLocal != b.isLocal) return a.isLocal ? -1 : 1;
        return 0;
      });
    final scheme = Theme.of(context).colorScheme;
    final anyoneToMute = people.any((p) => !p.isLocal && p.hasAudio);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.callParticipantCount(people.length),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (call.canModerate)
                  TextButton.icon(
                    onPressed: anyoneToMute ? () => onMuteAll() : null,
                    icon: const Icon(Icons.mic_off_rounded, size: 18),
                    label: Text(context.l10n.callMuteAll),
                  ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final person in people)
                  ListTile(
                    leading: Icon(
                      person.hasAudio
                          ? Icons.mic_rounded
                          : Icons.mic_off_rounded,
                      color: person.hasAudio
                          ? (person.isSpeaking ? const Color(0xFFFFBE00) : null)
                          : scheme.onSurfaceVariant,
                    ),
                    title: Text(
                      person.isLocal
                          ? context.l10n.callYou(person.displayName)
                          : person.displayName,
                    ),
                    subtitle: person.handRaised
                        ? Text(context.l10n.callHandRaised)
                        : null,
                    trailing: person.handRaised
                        ? const Icon(
                            Icons.pan_tool_rounded,
                            color: Color(0xFFFFBE00),
                          )
                        : call.canModerate && !person.isLocal && person.hasAudio
                        ? TextButton(
                            onPressed: () => onMute(person.id),
                            child: Text(context.l10n.callMute),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
