import 'dart:async';

import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The bar that says a call is still running while you are somewhere else.
///
/// It is what makes leaving the call screen safe: without it an ongoing call
/// is an open microphone nobody can see, which is why leaving used to hang up.
/// With it, walking into a chat to read something mid-call costs nothing.
class OngoingCallBar extends ConsumerStatefulWidget {
  const OngoingCallBar({super.key});

  @override
  ConsumerState<OngoingCallBar> createState() => _OngoingCallBarState();
}

class _OngoingCallBarState extends ConsumerState<OngoingCallBar> {
  Timer? _clock;
  StreamSubscription<CallSnapshot>? _watch;
  CallController? _watched;

  @override
  void dispose() {
    _clock?.cancel();
    unawaited(_watch?.cancel());
    super.dispose();
  }

  /// Follows the call so the bar disappears when the other side hangs up.
  ///
  /// Nothing else is listening once the call screen is gone, so without this
  /// the bar would advertise a call that ended minutes ago.
  void _watchCall(CallController controller) {
    if (identical(_watched, controller)) return;
    unawaited(_watch?.cancel());
    _watched = controller;
    _watch = controller.changes.listen((snapshot) {
      if (snapshot.state == CallConnectionState.ended) _clear(controller);
    });
    if (controller.current.state == CallConnectionState.ended) {
      _clear(controller);
    }
  }

  void _clear(CallController controller) {
    // Scheduled: this can arrive from a stream event mid-build, and writing
    // to a provider then fires listeners while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (identical(ref.read(activeCallProvider), controller)) {
        ref.read(activeCallProvider.notifier).state = null;
      }
    });
  }

  Future<void> _hangUp(CallController controller) async {
    ref.read(activeCallProvider.notifier).state = null;
    await controller.hangUp();
  }

  String _elapsed(CallSnapshot snapshot) {
    final started = snapshot.startedAt;
    if (started == null || snapshot.state != CallConnectionState.connected) {
      return '';
    }
    final elapsed = DateTime.now().difference(started);
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return elapsed.inHours > 0
        ? '${elapsed.inHours}:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(activeCallProvider);
    if (controller == null) {
      _clock?.cancel();
      _clock = null;
      _watched = null;
      unawaited(_watch?.cancel());
      _watch = null;
      return const SizedBox.shrink();
    }
    _watchCall(controller);
    // Only runs while a call is up, and only redraws the duration readout.
    _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<CallSnapshot>(
      stream: controller.changes,
      initialData: controller.current,
      builder: (context, snapshot) {
        final call = snapshot.data ?? controller.current;
        final duration = _elapsed(call);
        return Material(
          color: scheme.primary,
          child: InkWell(
            onTap: () => openCall(
              context,
              call.roomId,
              withVideo: call.cameraEnabled,
              // Returning to a call must never re-ring the room.
              ring: false,
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Icon(Icons.call_rounded, size: 16, color: scheme.onPrimary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        call.state == CallConnectionState.connected
                            ? context.l10n.returnToCall
                            : context.l10n.connecting,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (duration.isNotEmpty) ...[
                      Text(
                        duration,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    IconButton(
                      tooltip: context.l10n.callHangUp,
                      onPressed: () => unawaited(_hangUp(controller)),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.call_end_rounded,
                        size: 18,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
