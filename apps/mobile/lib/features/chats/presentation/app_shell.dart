import 'dart:async';

import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/layout/breakpoints.dart';
import 'package:dg_chat/core/widgets/brand_mark.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/calls/presentation/incoming_call_banner.dart';
import 'package:dg_chat/features/conversation/application/selected_room_scope.dart';
import 'package:dg_chat/features/meetings/presentation/join_meeting_dialog.dart';
import 'package:dg_chat/features/meetings/presentation/meeting_invite_dialog.dart';
import 'package:dg_chat/features/conversation/presentation/conversation_screen.dart';
import 'package:dg_chat/core/diagnostics/pointer_diagnostics.dart';
import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/calls/application/native_call_launch.dart';
import 'package:flutter/foundation.dart';
import 'package:dg_chat/features/notifications/domain/push_notification.dart';
import 'package:dg_chat/features/notifications/application/push_message_router.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:dg_chat/features/calls/presentation/live_call_bar.dart';
import 'package:dg_chat/features/calls/presentation/ongoing_call_bar.dart';
import 'package:dg_chat/features/notifications/application/notification_providers.dart';
import 'package:dg_chat/features/notifications/application/web_notification_listener.dart';
import 'package:dg_chat/features/notifications/presentation/web_notification_prompt.dart';
import 'package:dg_chat/features/notifications/application/push_providers.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Branch indices of the [StatefulShellRoute] this shell drives.
const _chatsBranch = 0;
const _contactsBranch = 1;
const _settingsBranch = 2;

/// Width of the icon rail, and the button inside it. The button is the rail
/// minus its horizontal padding, so the selected indicator fills the rail's
/// width rather than hugging the icon.
const _railWidth = 72.0;
const _railButtonSize = Size(_railWidth - AppSpacing.sm * 2, 44);

class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    required this.navigationShell,
    required this.selectedRoomId,
    this.selectedEventId,
    super.key,
  });

  final StatefulNavigationShell navigationShell;

  /// The room the current location names, or null when none is open.
  final String? selectedRoomId;

  /// A message the location asks to land on, from a search result.
  final String? selectedEventId;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  /// The conversation most recently open. The location is the source of
  /// truth, but it only names a room on the chats branch — peeking at
  /// Contacts must not blank the conversation beside it, the way switching
  /// sections keeps the open channel in a desktop client.
  String? _lastOpenRoom;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The shell only builds for a signed-in session, so this is the first
    // point where registering a pusher is meaningful. It is a no-op when no
    // push gateway is configured.
    //
    // Deferred to the first frame because the pusher carries the wording Apple
    // shows on the lock screen, and localizations cannot be read from
    // initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(pushRegistrationServiceProvider)
            .start(alertText: context.l10n.newMessageNotification),
      );
    });
    unawaited(ref.read(pushMessageListenerProvider).start());
    // Answers to rings raised by the push isolate, including the cold-start
    // case where answering is what launched the app.
    _nativeCallLaunch = NativeCallLaunch((roomId) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          openCall(context, roomId, withVideo: false, ring: false);
        }
      });
    });
    unawaited(_nativeCallLaunch!.start());
    // Web notifications come from this tab's own sync rather than a gateway,
    // and only start when permission has already been granted -- the banner
    // asks for it otherwise.
    unawaited(ref.read(webNotificationListenerProvider).start());
  }

  NativeCallLaunch? _nativeCallLaunch;

  @override
  void dispose() {
    _nativeCallLaunch?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_setRuntimeForeground(true));
      _repaintAfterHiding();
      // The ring channel registers against a token PushKit delivers on its
      // own schedule; every foregrounding is another chance to catch it.
      unawaited(
        ref.read(pushRegistrationServiceProvider).refreshVoipRegistration(),
      );
    } else if ({
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    }.contains(state)) {
      unawaited(_setRuntimeForeground(false));
    }
  }

  /// Forces a frame after the page comes back from being hidden.
  ///
  /// Flutter web draws on `requestAnimationFrame`, which browsers throttle to
  /// nothing for a hidden page — a background tab, a covered window, a
  /// minimised one. Input still arrives and is still handled: tapping a chat
  /// while hidden really does open it. What stops is painting, so the screen
  /// keeps showing whatever was on it, and the app reads as frozen —
  /// click a conversation, nothing happens, click again, still nothing.
  ///
  /// Coming back does not necessarily fix it by itself. The engine resumes,
  /// but with nothing marked dirty there is no frame to schedule, so the stale
  /// picture can survive the return. Asking for one costs nothing when the
  /// display was already correct.
  void _repaintAfterHiding() {
    // Web only. Android and iOS repaint on resume by themselves, and forcing
    // an extra frame there would buy a hitch for nothing.
    if (!kIsWeb || !mounted) return;
    setState(() {});
    WidgetsBinding.instance.scheduleWarmUpFrame();
  }

  Future<void> _setRuntimeForeground(bool foreground) async {
    final runtime = await ref.read(messagingRuntimeProvider.future);
    if (foreground) {
      await runtime.resume();
    } else {
      await runtime.pause();
    }
  }

  void _selectTab(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  Future<void> _showCreateMenu(BuildContext context) async {
    final destination = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_rounded),
                title: Text(context.l10n.startNewChat),
                onTap: () => Navigator.pop(context, AppRoutes.userSearch),
              ),
              ListTile(
                leading: const Icon(Icons.group_add_rounded),
                title: Text(context.l10n.createGroup),
                onTap: () => Navigator.pop(context, AppRoutes.newGroup),
              ),
              ListTile(
                leading: const Icon(Icons.video_call_rounded),
                title: Text(context.l10n.newMeeting),
                onTap: () => Navigator.pop(context, _newMeetingMarker),
              ),
              ListTile(
                leading: const Icon(Icons.keyboard_rounded),
                title: Text(context.l10n.joinWithCode),
                onTap: () => Navigator.pop(context, _joinMeetingMarker),
              ),
            ],
          ),
        ),
      ),
    );

    if (!context.mounted || destination == null) return;
    if (destination == _newMeetingMarker) {
      await startNewMeeting(context, ref);
      return;
    }
    if (destination == _joinMeetingMarker) {
      final code = await showJoinMeetingDialog(context);
      if (code != null && context.mounted)
        context.push(AppRoutes.meetPath(code));
      return;
    }
    context.push(destination);
  }

  /// Says a call has started, for whoever is not looking at this room.
  ///
  /// Tapping opens the conversation rather than the call: the room now carries
  /// a Join button in the timeline and a bar above it, and dropping somebody
  /// into a live call with their microphone on from a single tap on a
  /// notification is not a kindness.
  Future<void> _announceCall(LiveCall call) async {
    // Your own call needs no announcement, and neither does one in the room
    // already on screen -- the bar there is louder than a notification.
    if (ref.read(activeCallProvider) != null) return;
    if (ref.read(activeRoomProvider) == call.roomId) return;

    final presenter = kIsWeb
        ? ref.read(webNotificationPresenterProvider)
        : ref.read(notificationPresenterProvider);
    try {
      await presenter.show(
        PushNotification(
          roomId: call.roomId,
          // Not a message event, but the presenter needs something to key the
          // notification on, and one per room is the behaviour wanted here
          // too.
          eventId: 'call:${call.roomId}',
          body: mounted ? context.l10n.someoneInCall : null,
        ),
        title: call.roomName,
      );
    } catch (_) {
      // A platform that cannot draw a notification — an unsupported target, a
      // test with no plugins, permission never granted — must not take the
      // call itself down with it. The bar and the timeline entry still work.
    }
  }

  static const _newMeetingMarker = '::new-meeting';
  static const _joinMeetingMarker = 'join-meeting';

  @override
  Widget build(BuildContext context) {
    // A tapped notification can land before any navigator exists, from a cold
    // start, so it is held as state and consumed here once one does.
    ref.listen(pendingNotificationRoomProvider, (previous, roomId) {
      if (roomId == null || roomId.isEmpty) return;
      ref.read(pendingNotificationRoomProvider.notifier).state = null;
      openConversation(context, roomId);
    });

    // A call going live is worth a notification of its own. The push the
    // server sends for it arrives labelled "New message", because the gateway
    // is not told it is a call -- Sygnal forwards a fixed field list without
    // tweaks, and the event type is stripped by the push format that keeps
    // message types away from Google and Apple. The client knows, so the
    // client says so.
    ref.listen(liveCallsProvider, (previous, next) {
      final before = previous?.valueOrNull ?? const <LiveCall>[];
      final now = next.valueOrNull ?? const <LiveCall>[];
      final known = before.map((call) => call.roomId).toSet();
      for (final call in now) {
        if (known.contains(call.roomId)) continue;
        unawaited(_announceCall(call));
      }
    });

    ref.listen(authControllerProvider, (previous, next) {
      if (previous?.hasValue == true &&
          previous?.value != null &&
          next.hasValue &&
          next.value == null) {
        // A call outlives the call screen now, which means it can outlive the
        // session too: signing out from Settings mid-call would leave the mic
        // open with the bar gone, since the login screen is outside this
        // shell. Whoever ends the session ends the call.
        final call = ref.read(activeCallProvider);
        if (call != null) {
          ref.read(activeCallProvider.notifier).state = null;
          unawaited(call.hangUp());
        }
        context.go(AppRoutes.login);
      }
    });
    final connectionStatus = ref.watch(messagingStatusProvider).asData?.value;
    final banner = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (connectionStatus != null && _isWorthReporting(connectionStatus))
          _ConnectionBanner(status: connectionStatus),
        // Draws nothing unless this is a browser that has not been asked yet.
        const WebNotificationPrompt(),
        // Draws nothing unless a call is live somewhere behind this screen.
        const OngoingCallBar(),
        // Draws nothing unless somebody else has a call running.
        const LiveCallBar(),
      ],
    );

    if (widget.selectedRoomId != null) _lastOpenRoom = widget.selectedRoomId;

    return SelectedRoomScope(
      roomId: widget.selectedRoomId,
      child: IncomingCallBanner(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final window = AppBreakpoints.of(constraints.maxWidth);
            _reportGeometry(context, constraints, window);
            return window.hasSidePanes
                ? _buildWorkspace(context, window, banner)
                : _buildCompact(context, banner);
          },
        ),
      ),
    );
  }

  /// Logs the three widths that have to agree, for `?diag=1` sessions.
  ///
  /// The panes are sized from the constraints the shell is handed, while the
  /// window is whatever the browser actually has. When a click misses a chat
  /// row by hundreds of pixels, one of these disagrees with the others, and
  /// which one tells you where the fault is: the constraints, the media
  /// query the breakpoints came from, or the view itself. The pixel ratio is
  /// here because zoom and a second monitor both change it, and both survive
  /// the resize that would have cleared a stale size.
  void _reportGeometry(
    BuildContext context,
    BoxConstraints constraints,
    AppWindowSize window,
  ) {
    if (!PointerDiagnostics.enabled) return;
    final view = View.of(context);
    final media = MediaQuery.sizeOf(context);
    final physical = view.physicalSize / view.devicePixelRatio;
    debugPrint(
      'dg-diag layout | constraints ${constraints.maxWidth.toStringAsFixed(0)}'
      'x${constraints.maxHeight.toStringAsFixed(0)}'
      ' | media ${media.width.toStringAsFixed(0)}x${media.height.toStringAsFixed(0)}'
      ' | view ${physical.width.toStringAsFixed(0)}x${physical.height.toStringAsFixed(0)}'
      ' | dpr ${view.devicePixelRatio}'
      ' | sidebar ${window.sidebarWidth}'
      ' | panes ${window.hasSidePanes}',
    );
  }

  /// The phone layout: one pane at a time, tabs along the bottom.
  Widget _buildCompact(BuildContext context, Widget? banner) {
    // Inside a conversation the list-level chrome disappears: the tab bar
    // would steal a row from the keyboard, and the compose FAB would sit on
    // top of the send button. The conversation page carries its own app bar
    // and back affordance.
    final inConversation = widget.selectedRoomId != null;
    return Scaffold(
      body: Column(
        children: [
          ?banner,
          Expanded(child: widget.navigationShell),
        ],
      ),
      floatingActionButton:
          !inConversation && widget.navigationShell.currentIndex == _chatsBranch
          ? FloatingActionButton(
              tooltip: context.l10n.startNewChat,
              onPressed: () => _showCreateMenu(context),
              child: const Icon(Icons.edit_square),
            )
          : null,
      bottomNavigationBar: inConversation
          ? null
          : NavigationBar(
              selectedIndex: widget.navigationShell.currentIndex,
              onDestinationSelected: _selectTab,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  selectedIcon: const Icon(Icons.chat_bubble_rounded),
                  label: context.l10n.chats,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.people_outline_rounded),
                  selectedIcon: const Icon(Icons.people_rounded),
                  label: context.l10n.contacts,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings_rounded),
                  label: context.l10n.settings,
                ),
              ],
            ),
    );
  }

  /// The desktop layout: a rail, the list beside it, and the conversation
  /// open alongside rather than on top of it.
  Widget _buildWorkspace(
    BuildContext context,
    AppWindowSize window,
    Widget? banner,
  ) {
    // Settings is a page rather than a list, so it takes the whole working
    // area instead of being squeezed into a sidebar column.
    final isListBranch = widget.navigationShell.currentIndex != _settingsBranch;

    return Scaffold(
      body: Column(
        children: [
          ?banner,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WorkspaceRail(
                  selectedIndex: widget.navigationShell.currentIndex,
                  onSelected: _selectTab,
                ),
                if (isListBranch) ...[
                  SizedBox(
                    width: window.sidebarWidth,
                    child: Theme(
                      data: AppTheme.sidebar,
                      child: widget.navigationShell,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _DetailPane(
                      roomId: widget.selectedRoomId ?? _lastOpenRoom,
                      eventId: widget.selectedEventId,
                    ),
                  ),
                ] else
                  Expanded(child: widget.navigationShell),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Whether a connection state is worth pushing the whole layout down for.
///
/// [MessagingConnectionState.synchronizing] is deliberately excluded. Matrix
/// sync is a continuous long poll, so every cycle passes through it — showing
/// the banner there inserted and removed a bar above the entire UI every few
/// seconds, and the whole window visibly jumped each time. Routine syncing is
/// background work, not something to report. What remains are the states that
/// persist and that the reader can actually do something about: still starting
/// up, offline, server unreachable, or signed out.
bool _isWorthReporting(MessagingConnectionState status) => switch (status) {
  MessagingConnectionState.online ||
  MessagingConnectionState.synchronizing => false,
  _ => true,
};

/// The conversation shown beside the list, or an invitation to pick one.
class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.roomId, this.eventId});

  final String? roomId;
  final String? eventId;

  @override
  Widget build(BuildContext context) {
    final roomId = this.roomId;
    if (roomId == null) return const _NoConversationSelected();
    // Keyed so switching rooms rebuilds the conversation's state rather than
    // showing the previous room's composer text and scroll position. The
    // event key is included so a second search hit in the same room still
    // triggers a fresh jump.
    return ConversationScreen(
      key: ValueKey('$roomId#${eventId ?? ''}'),
      roomId: roomId,
      embedded: true,
      initialEventId: eventId,
    );
  }
}

class _NoConversationSelected extends StatelessWidget {
  const _NoConversationSelected();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(opacity: 0.35, child: BrandMark(size: 56)),
            const SizedBox(height: AppSpacing.lg),
            Text(
              context.l10n.selectConversationTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.selectConversationBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The narrow icon rail down the left edge. It stays dark in both themes, so
/// the workspace reads top-level-navigation / list / conversation from left to
/// right the way a desktop chat client does.
class _WorkspaceRail extends StatelessWidget {
  const _WorkspaceRail({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.night,
      child: SizedBox(
        width: _railWidth,
        child: SafeArea(
          right: false,
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.md),
              const BrandMark(size: 34),
              const SizedBox(height: AppSpacing.lg),
              _RailButton(
                icon: Icons.chat_bubble_outline_rounded,
                selectedIcon: Icons.chat_bubble_rounded,
                label: context.l10n.chats,
                selected: selectedIndex == _chatsBranch,
                onPressed: () => onSelected(_chatsBranch),
              ),
              _RailButton(
                icon: Icons.people_outline_rounded,
                selectedIcon: Icons.people_rounded,
                label: context.l10n.contacts,
                selected: selectedIndex == _contactsBranch,
                onPressed: () => onSelected(_contactsBranch),
              ),
              const Spacer(),
              const _ComposeButton(),
              const SizedBox(height: AppSpacing.sm),
              _RailButton(
                icon: Icons.settings_outlined,
                selectedIcon: Icons.settings_rounded,
                label: context.l10n.settings,
                selected: selectedIndex == _settingsBranch,
                onPressed: () => onSelected(_settingsBranch),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Semantics(
        selected: selected,
        button: true,
        child: Tooltip(
          message: label,
          child: Material(
            color: selected ? AppColors.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(12),
              // Sized explicitly: the rail's Column centres its children, so
              // without a width the selected indicator shrinks to the icon and
              // reads as a narrow pill rather than a button.
              child: SizedBox(
                width: _railButtonSize.width,
                height: _railButtonSize.height,
                child: Icon(
                  selected ? selectedIcon : icon,
                  size: 22,
                  color: selected
                      ? AppColors.deepTeal
                      : const Color(0xFFB7C7C5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compose lives in the rail on a wide window, where a floating action button
/// would sit in the far corner of the conversation instead of near the list it
/// acts on. A menu is used rather than the phone's bottom sheet.
class _ComposeButton extends ConsumerWidget {
  const _ComposeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MenuAnchor(
      alignmentOffset: const Offset(8, 0),
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.person_add_alt_1_rounded),
          onPressed: () => context.push(AppRoutes.userSearch),
          child: Text(context.l10n.startNewChat),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.group_add_rounded),
          onPressed: () => context.push(AppRoutes.newGroup),
          child: Text(context.l10n.createGroup),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.video_call_rounded),
          onPressed: () => startNewMeeting(context, ref),
          child: Text(context.l10n.newMeeting),
        ),
      ],
      builder: (context, controller, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Tooltip(
          message: context.l10n.newMessage,
          child: Material(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: _railButtonSize.width,
                height: _railButtonSize.height,
                child: const Icon(
                  Icons.edit_square,
                  size: 20,
                  color: AppColors.deepTeal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.status});

  final MessagingConnectionState status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCritical = {
      MessagingConnectionState.serverUnavailable,
      MessagingConnectionState.sessionExpired,
    }.contains(status);
    final backgroundColor = switch (status) {
      MessagingConnectionState.offline => scheme.primaryContainer,
      _ when isCritical => scheme.errorContainer,
      _ => scheme.secondaryContainer,
    };
    final (icon, label) = switch (status) {
      MessagingConnectionState.connecting => (
        Icons.cloud_sync_outlined,
        context.l10n.connecting,
      ),
      MessagingConnectionState.synchronizing => (
        Icons.sync_rounded,
        context.l10n.synchronizing,
      ),
      MessagingConnectionState.offline => (
        Icons.cloud_off_rounded,
        context.l10n.offlineCachedContent,
      ),
      MessagingConnectionState.serverUnavailable => (
        Icons.cloud_off_rounded,
        context.l10n.serverUnavailable,
      ),
      MessagingConnectionState.sessionExpired => (
        Icons.lock_clock_outlined,
        context.l10n.sessionExpired,
      ),
      MessagingConnectionState.online => (
        Icons.cloud_done_outlined,
        context.l10n.online,
      ),
    };
    return Material(
      color: backgroundColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
