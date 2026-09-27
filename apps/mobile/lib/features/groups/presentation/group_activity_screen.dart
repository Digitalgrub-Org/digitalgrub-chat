import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/chats/presentation/chat_list_screen.dart'
    show formatChatTimestamp;
import 'package:dg_chat/features/groups/application/group_providers.dart';
import 'package:dg_chat/features/groups/presentation/group_activity_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The log a group otherwise keeps silently: who joined, who left, who
/// changed what, newest first.
///
/// Exists because of one real moment — a developer left a group and nobody
/// could say when, or what else had changed while nobody was looking.
class GroupActivityScreen extends ConsumerWidget {
  const GroupActivityScreen({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(groupActivityProvider(roomId));
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.groupActivity)),
      body: activity.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 44),
                const SizedBox(height: AppSpacing.md),
                Text(context.l10n.messageLoadFailed),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(groupActivityProvider(roomId)),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(child: Text(context.l10n.groupActivityEmpty));
          }
          // Already newest-first from the repository, which is the order this
          // screen wants: the question it answers is "what just happened",
          // not "how did it begin".
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(groupActivityProvider(roomId)),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return ListTile(
                  dense: true,
                  leading: Icon(groupActivityIcon(entry.kind), size: 20),
                  title: Text(groupActivityLine(context, entry)),
                  trailing: Text(
                    formatChatTimestamp(context, entry.at),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
