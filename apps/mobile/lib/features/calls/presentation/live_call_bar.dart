import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The bar that says a call is happening somewhere you are not.
///
/// A ring lasts thirty seconds and then it is gone — phone in a pocket, app
/// closed, and the call may as well not have happened. This is the recovery:
/// as long as somebody is still in the call, there is a line at the top of the
/// app saying so, and joining is one tap. It does not wake a sleeping phone;
/// the push notification does that, and this is what greets you when you act
/// on it.
class LiveCallBar extends ConsumerWidget {
  const LiveCallBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Already talking: the ongoing-call bar has this screen's attention, and
    // two call bars stacked is noise.
    if (ref.watch(activeCallProvider) != null) return const SizedBox.shrink();

    final calls =
        ref.watch(liveCallsProvider).valueOrNull ?? const <LiveCall>[];
    if (calls.isEmpty) return const SizedBox.shrink();
    // Two at once is rare enough that the newest wins rather than earning a
    // list of its own.
    final call = calls.last;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(
                Icons.groups_rounded,
                size: 18,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      call.roomName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      call.participantCount > 1
                          ? context.l10n.liveCallParticipants(
                              call.participantCount,
                            )
                          : context.l10n.onACallNow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                onPressed: () => openCall(
                  context,
                  call.roomId,
                  // Audio first: joining a call that is already running should
                  // not put your camera on without being asked.
                  withVideo: false,
                  // Joining must never re-ring the room.
                  ring: false,
                ),
                icon: const Icon(Icons.call_rounded, size: 16),
                label: Text(context.l10n.joinCall),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
