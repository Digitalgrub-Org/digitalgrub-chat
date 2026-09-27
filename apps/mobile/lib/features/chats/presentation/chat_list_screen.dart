import 'dart:async';

import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/format/chat_timestamp.dart';
export 'package:dg_chat/core/format/chat_timestamp.dart';
import 'package:dg_chat/core/layout/breakpoints.dart';
import 'package:dg_chat/core/widgets/profile_avatar.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/meetings/presentation/meeting_invite_dialog.dart';
import 'package:dg_chat/features/meetings/presentation/join_meeting_dialog.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:dg_chat/features/conversation/application/selected_room_scope.dart';
import 'package:dg_chat/features/search/application/search_providers.dart';
import 'package:dg_chat/features/search/domain/search_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  final _searchController = TextEditingController();
  bool _searching = false;

  /// The query message search actually runs, settled by a debounce. Filtering
  /// conversation names is local and reacts to every keystroke; hitting the
  /// homeserver on every keystroke is how a search box DoSes its own server.
  String _messageQuery = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _messageQuery = '';
        _debounce?.cancel();
      }
    });
  }

  Future<void> _refresh() async {
    final repository = await ref.read(chatRepositoryProvider.future);
    await repository.refresh();
  }

  Future<void> _showMeetMenu(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_call_rounded),
              title: Text(context.l10n.newMeeting),
              subtitle: Text(context.l10n.meetingShareHint),
              onTap: () => Navigator.pop(context, 'new'),
            ),
            ListTile(
              leading: const Icon(Icons.keyboard_rounded),
              title: Text(context.l10n.joinWithCode),
              onTap: () => Navigator.pop(context, 'join'),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'new') {
      await startNewMeeting(context, ref);
    } else {
      final code = await showJoinMeetingDialog(context);
      if (code != null && context.mounted)
        context.push(AppRoutes.meetPath(code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatListProvider);
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.l10n.searchConversations,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                textInputAction: TextInputAction.search,
                onChanged: (_) {
                  setState(() {});
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), () {
                    if (!mounted) return;
                    final settled = _searchController.text.trim();
                    // Under three characters the server matches half the
                    // room, which is noise presented as results.
                    setState(
                      () => _messageQuery = settled.length >= 3 ? settled : '',
                    );
                  });
                },
              )
            : Text(context.l10n.appName),
        actions: [
          IconButton(
            tooltip: _searching
                ? context.l10n.close
                : context.l10n.searchConversations,
            onPressed: _toggleSearch,
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
          ),
          if (!_searching) ...[
            // Where a meeting app puts it: one tap from the list, not three
            // rows into a menu. New meeting or join with a code.
            IconButton(
              tooltip: context.l10n.meet,
              onPressed: () => _showMeetMenu(context),
              icon: const Icon(Icons.video_call_rounded),
            ),
            IconButton(
              tooltip: context.l10n.searchPeople,
              onPressed: () => context.push(AppRoutes.userSearch),
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          ],
        ],
      ),
      body: chats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            _ChatListError(onRetry: () => ref.invalidate(chatListProvider)),
        data: (items) {
          final query = _searchController.text.trim().toLowerCase();
          final filtered = query.isEmpty
              ? items
              : items
                    .where(
                      (chat) =>
                          chat.name.toLowerCase().contains(query) ||
                          chat.lastMessage.toLowerCase().contains(query),
                    )
                    .toList();
          if (items.isEmpty && _messageQuery.isEmpty) {
            return const _EmptyChatList();
          }
          final searchingMessages = _messageQuery.isNotEmpty;
          if (filtered.isEmpty && !searchingMessages) {
            return Center(child: Text(context.l10n.noMatchingConversations));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                bottom: context.windowSize.hasSidePanes ? 12 : 96,
              ),
              children: [
                for (final (index, chat) in filtered.indexed) ...[
                  chat.isInvite
                      ? _InviteTile(chat: chat)
                      : _ChatTile(chat: chat),
                  // In the sidebar the rows are their own column, so a rule
                  // between them only adds noise; on a phone it separates
                  // rows that span the whole screen.
                  if (index < filtered.length - 1 &&
                      !context.windowSize.hasSidePanes)
                    const Divider(indent: 80),
                ],
                if (searchingMessages) ...[
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        context.l10n.noMatchingConversations,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  _MessageResultsSection(query: _messageQuery),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Server-side message hits for the current query, shown under the
/// conversation matches.
class _MessageResultsSection extends ConsumerWidget {
  const _MessageResultsSection({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(messageSearchProvider(query));
    final scheme = Theme.of(context).colorScheme;

    Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        context.l10n.messagesSection,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return results.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ],
      ),
      // A search that fails is worth a quiet line, not an error screen: the
      // conversation list above it still works.
      error: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              context.l10n.messageSearchFailed,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
      data: (hits) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          if (hits.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                context.l10n.noMessagesFound,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final hit in hits) _MessageResultTile(hit: hit),
        ],
      ),
    );
  }
}

class _MessageResultTile extends ConsumerWidget {
  const _MessageResultTile({required this.hit});

  final MessageSearchResult hit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: CircleAvatar(
        child: Text(hit.roomName.isEmpty ? '?' : hit.roomName[0].toUpperCase()),
      ),
      title: Text(hit.roomName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${hit.senderName}: ${hit.body}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        formatChatTimestamp(context, hit.sentAt),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: () => openConversation(context, hit.roomId, eventId: hit.eventId),
    );
  }
}

/// An invited room cannot be opened: Matrix serves no timeline until the
/// account joins. So the tile offers the decision instead of a dead tap.
class _InviteTile extends ConsumerStatefulWidget {
  const _InviteTile({required this.chat});

  final ChatSummary chat;

  @override
  ConsumerState<_InviteTile> createState() => _InviteTileState();
}

class _InviteTileState extends ConsumerState<_InviteTile> {
  bool _busy = false;

  Future<void> _respond({required bool accept}) async {
    if (_busy) return;
    final l10n = context.l10n;

    if (!accept) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.declineInviteConfirmation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.declineInvite),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _busy = true);
    try {
      final repository = await ref.read(chatRepositoryProvider.future);
      if (accept) {
        await repository.acceptInvite(widget.chat.roomId);
      } else {
        await repository.declineInvite(widget.chat.roomId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? l10n.inviteAccepted : l10n.inviteDeclined),
        ),
      );
      if (accept) openConversation(context, widget.chat.roomId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.inviteActionFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final inviter = chat.invitedBy;

    return ListTile(
      minTileHeight: 88,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: ProfileAvatar(
        label: chat.name,
        imageUrl: chat.avatarUrl,
        httpHeaders: chat.avatarHeaders,
      ),
      title: Text(
        chat.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            inviter == null
                ? context.l10n.invitedYouGeneric
                : context.l10n.invitedYou(inviter),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Row(
              children: [
                FilledButton(
                  onPressed: () => _respond(accept: true),
                  child: Text(context.l10n.acceptInvite),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  onPressed: () => _respond(accept: false),
                  child: Text(context.l10n.declineInvite),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ChatTile extends ConsumerWidget {
  const _ChatTile({required this.chat});

  final ChatSummary chat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // In the sidebar the open conversation is marked, the way a desktop
    // client shows which channel you are reading. On a phone only one pane is
    // ever visible, so there is nothing to mark.
    final inSidebar = context.windowSize.hasSidePanes;
    final selected = inSidebar && SelectedRoomScope.of(context) == chat.roomId;
    final unread = chat.unreadCount > 0;

    return ListTile(
      selected: selected,
      selectedTileColor: scheme.primary.withValues(alpha: 0.18),
      selectedColor: scheme.onSurface,
      minTileHeight: inSidebar ? 62 : 76,
      contentPadding: EdgeInsets.symmetric(
        horizontal: inSidebar ? AppSpacing.sm : AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: ProfileAvatar(
        label: chat.name,
        imageUrl: chat.avatarUrl,
        httpHeaders: chat.avatarHeaders,
        radius: inSidebar ? 18 : 24,
        online: chat.presence?.online,
      ),
      title: Text(
        chat.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: unread && inSidebar ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        _previewText(context, chat),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: unread && inSidebar
            ? TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600)
            : null,
      ),
      trailing: SizedBox(
        width: 58,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (chat.lastActivity != null)
              Text(
                _formatActivity(context, chat.lastActivity!),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            if (chat.unreadCount > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              UnreadIndicator(
                unreadCount: chat.unreadCount,
                highlightCount: chat.highlightCount,
              ),
            ] else if (chat.pendingCount > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Tooltip(
                message: chat.hasFailedMessages
                    ? context.l10n.messagesFailedToSend
                    : context.l10n.messagesWaitingToSend,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      chat.hasFailedMessages
                          ? Icons.error_outline_rounded
                          : Icons.schedule_rounded,
                      size: 15,
                      color: chat.hasFailedMessages
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 2),
                    Text('${chat.pendingCount}'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      onTap: () => openConversation(context, chat.roomId),
    );
  }

  String _formatActivity(BuildContext context, DateTime value) =>
      formatChatTimestamp(context, value);
}

class _EmptyChatList extends StatelessWidget {
  const _EmptyChatList();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                context.l10n.noConversationsTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.l10n.noConversationsBody,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.userSearch),
                icon: const Icon(Icons.person_search_rounded),
                label: Text(context.l10n.findPeople),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatListError extends StatelessWidget {
  const _ChatListError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 44),
            const SizedBox(height: AppSpacing.md),
            Text(context.l10n.chatListFailed, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onRetry, child: Text(context.l10n.retry)),
          ],
        ),
      ),
    );
  }
}

/// What the list shows under a room name.
///
/// A file event's plaintext fallback is just its filename, so an unadorned
/// preview reads as a stray "IMG_0421.HEIC" with no hint that a photo was
/// shared. Naming the kind is what every other chat app does here.
String _previewText(BuildContext context, ChatSummary chat) {
  final label = switch (chat.previewKind) {
    ChatPreviewKind.image => context.l10n.attachmentPhoto,
    ChatPreviewKind.video => context.l10n.attachmentVideo,
    ChatPreviewKind.audio => context.l10n.attachmentAudio,
    ChatPreviewKind.file => context.l10n.attachmentFile,
    ChatPreviewKind.text => null,
  };
  if (label != null) return label;
  return chat.lastMessage.isEmpty
      ? context.l10n.noMessagesYet
      : chat.lastMessage;
}

/// What a chat row shows when it has something unread.
///
/// A count only when you were mentioned, a plain dot otherwise. Every unread
/// chat used to show a number, which meant a group where forty routine
/// messages arrived overnight looked more urgent than the one that named you
/// once -- the two are not the same request for attention, and a number is
/// the loudest thing a row can say.
///
/// Nothing is drawn for a chat with neither; the caller decides whether to
/// build this at all.
class UnreadIndicator extends StatelessWidget {
  const UnreadIndicator({
    super.key,
    required this.unreadCount,
    required this.highlightCount,
  });

  final int unreadCount;
  final int highlightCount;

  @override
  Widget build(BuildContext context) {
    if (highlightCount > 0) {
      return Badge(
        label: Text(highlightCount > 99 ? '99+' : '$highlightCount'),
      );
    }
    if (unreadCount <= 0) return const SizedBox.shrink();
    // Sized to sit on the same baseline as the badge it replaces, so a row
    // does not shift when a mention lands in a chat that was merely unread.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
