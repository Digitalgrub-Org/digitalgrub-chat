import 'dart:async';

import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/authentication/application/auth_controller.dart';
import 'package:dg_chat/features/meetings/application/meeting_providers.dart';
import 'package:dg_chat/features/meetings/domain/meeting_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The landing point of a meeting link.
///
/// This screen is the doorman, not the room: it signs the visitor in if
/// needed (preserving where they were headed), joins the meeting room on
/// first contact, and hands over to the call screen. A cold link on the web
/// arrives here directly without passing through the splash flow, so every
/// state — starting up, signed out, join failure — has to be handled in
/// place.
class MeetScreen extends ConsumerStatefulWidget {
  const MeetScreen({required this.roomId, super.key});

  final String roomId;

  @override
  ConsumerState<MeetScreen> createState() => _MeetScreenState();
}

class _MeetScreenState extends ConsumerState<MeetScreen> {
  MeetingFailureCode? _failure;
  bool _started = false;

  /// Signed out with guest access available: ask for a name instead of
  /// forcing an account on someone who was only invited to a call.
  bool _askGuestName = false;
  final _guestNameController = TextEditingController();

  @override
  void dispose() {
    _guestNameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_enter()));
  }

  Future<void> _enter() async {
    if (_started || !mounted) return;
    _started = true;
    try {
      final session = await ref.read(authControllerProvider.future);
      if (!mounted) return;
      if (session == null) {
        // Guests are the common case for a meeting link. The account door
        // stays one tap away; it is just not the front door any more.
        if (ref.read(appConfigProvider).meetGuestUrl != null) {
          setState(() => _askGuestName = true);
          return;
        }
        _goToLogin();
        return;
      }
      final repository = await ref.read(meetingRepositoryProvider.future);
      // The link may carry a short code; only the repository knows how to
      // turn either form into the canonical room id.
      final roomId = await repository.ensureJoined(widget.roomId);
      if (!mounted) return;
      // Replacing keeps /meet out of the back stack: leaving the call should
      // land in the app, not bounce back through the doorman and rejoin.
      context.pushReplacement(
        AppRoutes.callPath(roomId, withVideo: true, ring: false),
      );
    } on MeetingFailure catch (failure) {
      if (mounted) setState(() => _failure = failure.code);
    } catch (_) {
      if (mounted) setState(() => _failure = MeetingFailureCode.unknown);
    }
  }

  void _goToLogin() {
    final next = Uri.encodeComponent(
      '/meet/${Uri.encodeComponent(widget.roomId)}',
    );
    context.go('${AppRoutes.login}?next=$next');
  }

  void _joinAsGuest() {
    final name = _guestNameController.text.trim();
    if (name.isEmpty) return;
    // Replacing keeps the doorman out of the back stack, same as the
    // signed-in path.
    context.pushReplacement(
      '${AppRoutes.callPath(widget.roomId, withVideo: true, ring: false)}'
      '&guest=${Uri.encodeComponent(name)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: failure == null
              ? (_askGuestName
                    ? _GuestNameForm(
                        controller: _guestNameController,
                        onJoin: _joinAsGuest,
                        onSignIn: _goToLogin,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: AppSpacing.md),
                          Text(context.l10n.meetJoining),
                        ],
                      ))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link_off_rounded, size: 44),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      failure == MeetingFailureCode.notJoinable
                          ? context.l10n.meetLinkDead
                          : context.l10n.meetJoinFailed,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: () => context.go(AppRoutes.chats),
                      child: Text(context.l10n.close),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Name in, call out. The one form a guest ever sees.
class _GuestNameForm extends StatelessWidget {
  const _GuestNameForm({
    required this.controller,
    required this.onJoin,
    required this.onSignIn,
  });

  final TextEditingController controller;
  final VoidCallback onJoin;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.videocam_rounded, size: 44),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.l10n.meetGuestTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => onJoin(),
            decoration: InputDecoration(
              labelText: context.l10n.meetGuestNameLabel,
              counterText: '',
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: onJoin,
            icon: const Icon(Icons.call_rounded),
            label: Text(context.l10n.meetJoinAsGuest),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: onSignIn,
            child: Text(context.l10n.meetSignInInstead),
          ),
        ],
      ),
    );
  }
}
