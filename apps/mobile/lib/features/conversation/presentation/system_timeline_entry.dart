import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:dg_chat/features/groups/presentation/group_activity_line.dart';
import 'package:flutter/material.dart';

/// Something that happened to the group, in the middle of the timeline.
///
/// Not a bubble: no sender column, no avatar, nothing to long-press, because
/// nobody said it. A quiet centred line is how both WhatsApp and Telegram
/// render this, and it is what keeps a group's history reading as one story
/// instead of a chat plus a logbook kept somewhere else.
class SystemTimelineEntry extends StatelessWidget {
  const SystemTimelineEntry({required this.entry, super.key});

  final GroupActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xs,
      ),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              groupActivityLine(context, entry),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
