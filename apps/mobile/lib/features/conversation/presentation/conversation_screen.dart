import 'dart:async';

import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/router/app_router.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/core/format/chat_timestamp.dart';
import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/core/widgets/profile_avatar.dart';
import 'package:dg_chat/features/calls/application/call_providers.dart';
import 'package:dg_chat/features/chats/application/chat_providers.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:dg_chat/features/conversation/application/conversation_providers.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/features/conversation/presentation/attachment_picker.dart';
import 'package:dg_chat/features/conversation/presentation/composer_formatting.dart';
import 'package:dg_chat/features/conversation/presentation/message_attachment_view.dart';
import 'package:dg_chat/features/conversation/presentation/mention_suggestions.dart';
import 'package:dg_chat/features/conversation/presentation/message_actions.dart';
import 'package:dg_chat/features/conversation/presentation/message_markup.dart';
import 'package:dg_chat/features/conversation/presentation/system_timeline_entry.dart';
import 'package:dg_chat/features/conversation/presentation/voice_recorder.dart';
import 'package:dg_chat/features/moderation/presentation/content_agreement_sheet.dart';
import 'package:dg_chat/features/notifications/application/push_message_router.dart';
import 'package:dg_chat/features/moderation/presentation/report_sheet.dart';
import 'package:dg_chat/features/profile/application/profile_providers.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

enum _MessageAction {
  reply,
  forward,
  pin,
  unpin,
  copy,
  react,
  edit,
  delete,
  report,
  block,
  details,
}

enum _DeleteScope { local, everyone }

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({
    required this.roomId,
    this.embedded = false,
    this.initialEventId,
    this.onClose,
    super.key,
  });

  /// Set when this conversation is the chat panel of a live call.
  ///
  /// The back button becomes a close that hands control back to the call,
  /// and the call buttons go: you are already in the call, and a second one
  /// to the same room from inside the first is not a thing anyone means.
  final VoidCallback? onClose;

  final String roomId;

  /// A message to land on — the search hit that opened this conversation.
  final String? initialEventId;

  /// True when this is the detail pane of a wide window rather than a pushed
  /// route. An embedded conversation has nothing to go back to, so it drops
  /// the leading back button, and it lays its messages out as full-width rows
  /// because it is no longer competing with a phone's screen width.
  final bool embedded;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _composer = TextEditingController();
  final _focusNode = FocusNode();
  final _itemScroller = ItemScrollController();
  bool _sending = false;
  ChatMessage? _replyingTo;
  ChatMessage? _editingMessage;

  /// The search hit being walked to, until it is on screen or given up on.
  String? _pendingJump;

  /// Briefly marks the landed-on message so the eye finds it.
  String? _highlightedEventId;
  Timer? _highlightTimer;
  int _jumpPagesLoaded = 0;

  /// Which pinned message the bar is showing, newest first. Tapping the bar
  /// walks to the next one, the way a stack of pins is normally read.
  int _pinnedCursor = 0;
  bool _jumping = false;

  /// People offered for the `@` currently being typed, and the token itself.
  List<MentionCandidate> _mentionCandidates = const [];
  MentionQuery? _mentionQuery;
  int _mentionRequest = 0;

  static const _reactionOptions = ['👍', '❤️', '😂', '😮', '😢', '🎉'];

  /// Captured so the room can still be cleared while the widget is being torn
  /// down, when reading from `ref` is no longer safe.
  StateController<String?>? _activeRoom;

  @override
  void initState() {
    super.initState();
    _pendingJump = widget.initialEventId;
    _composer.addListener(_composerChanged);
    // Marks this room as on screen so a push for it is suppressed rather than
    // notifying about a message the user is already looking at. Deferred
    // because Riverpod forbids writing to a provider during a lifecycle
    // method, which would fire listeners mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(activeRoomProvider.notifier);
      notifier.state = widget.roomId;
      _activeRoom = notifier;
    });
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _composer.removeListener(_composerChanged);
    _composer.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String? _presenceLine(BuildContext context, ConversationSnapshot snapshot) {
    final presence = snapshot.partnerPresence;
    if (!snapshot.isDirect || presence == null) return null;
    if (presence.online) return context.l10n.presenceOnline;
    final lastActive = presence.lastActive;
    if (lastActive == null) return null;
    return context.l10n.presenceLastSeen(
      formatChatTimestamp(context, lastActive),
    );
  }

  /// Walks history until the target message is loaded, then scrolls to it.
  ///
  /// Deliberately bounded: a hit deeper than a handful of pages costs more
  /// scroll-back than it is worth, and the honest fallback is landing at the
  /// latest messages rather than spinning forever.
  Future<void> _advanceJump(ConversationSnapshot snapshot) async {
    final target = _pendingJump;
    if (target == null || _jumping) return;
    final index = snapshot.messages.indexWhere(
      (message) => message.eventId == target,
    );
    if (index >= 0) {
      _pendingJump = null;
      setState(() => _highlightedEventId = target);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _highlightedEventId = null);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _itemScroller.isAttached) {
          _itemScroller.scrollTo(
            index: index,
            duration: const Duration(milliseconds: 350),
            alignment: 0.3,
          );
        }
      });
      return;
    }
    if (!snapshot.canLoadOlder || _jumpPagesLoaded >= 10) {
      _pendingJump = null;
      return;
    }
    _jumping = true;
    _jumpPagesLoaded++;
    try {
      await _loadOlder();
    } finally {
      _jumping = false;
    }
  }

  @override
  void deactivate() {
    // Scheduled rather than applied inline: this runs during teardown, and
    // writing to a provider there fires listeners while the tree is building.
    final notifier = _activeRoom;
    final roomId = widget.roomId;
    if (notifier != null) {
      Future.microtask(() {
        // The container can be torn down before this runs, for instance when
        // the whole app is disposed.
        if (!notifier.mounted) return;
        if (notifier.state == roomId) notifier.state = null;
      });
    }
    super.deactivate();
  }

  void _composerChanged() {
    final hasText = _composer.text.trim().isNotEmpty;
    unawaited(_updateTyping(hasText));
    unawaited(_refreshMentions());
  }

  /// Keeps the @ picker in step with the caret.
  Future<void> _refreshMentions() async {
    final query = MentionQuery.of(_composer.value);
    if (query == null) {
      if (_mentionQuery != null || _mentionCandidates.isNotEmpty) {
        setState(() {
          _mentionQuery = null;
          _mentionCandidates = const [];
        });
      }
      return;
    }

    // Every keystroke starts a lookup; only the newest may paint, or a slow
    // earlier one lands on top of a narrower list.
    final request = ++_mentionRequest;
    try {
      final session = await ref.read(
        conversationSessionProvider(widget.roomId).future,
      );
      final candidates = await session.mentionCandidates(query.query);
      if (!mounted || request != _mentionRequest) return;
      setState(() {
        _mentionQuery = query;
        _mentionCandidates = candidates;
      });
    } catch (_) {
      if (!mounted || request != _mentionRequest) return;
      setState(() => _mentionCandidates = const []);
    }
  }

  void _insertMention(MentionCandidate candidate) {
    final query = _mentionQuery;
    if (query == null) return;
    _composer.value = applyMention(_composer.value, query, candidate);
    setState(() {
      _mentionQuery = null;
      _mentionCandidates = const [];
    });
    _focusNode.requestFocus();
  }

  Future<void> _updateTyping(bool isTyping) async {
    try {
      final session = await ref.read(
        conversationSessionProvider(widget.roomId).future,
      );
      await session.updateTyping(isTyping);
    } catch (_) {}
  }

  Future<void> _loadOlder() async {
    try {
      final session = await ref.read(
        conversationSessionProvider(widget.roomId).future,
      );
      await session.loadOlder();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.historyLoadFailed)));
      }
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;

    // Guideline 1.2: the community rules must be accepted before a user can
    // contribute content. Checked here because this is the only path that
    // publishes anything.
    if (!await ensureContentAgreement(context, ref)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.contentAgreementRequired)),
        );
      }
      return;
    }
    if (!mounted) return;

    _composer.clear();
    setState(() => _sending = true);
    try {
      final session = await ref.read(
        conversationSessionProvider(widget.roomId).future,
      );
      final editingMessage = _editingMessage;
      if (editingMessage != null) {
        await session.editMessage(editingMessage.eventId, text);
      } else {
        await session.sendText(text, replyToEventId: _replyingTo?.eventId);
      }
      if (mounted) {
        setState(() {
          _replyingTo = null;
          _editingMessage = null;
        });
      }
      _focusNode.requestFocus();
    } catch (_) {
      if (mounted) {
        _composer.text = text;
        _composer.selection = TextSelection.collapsed(offset: text.length);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.messageSendFailed)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendVoice(AttachmentDraft draft) async {
    if (!await ensureContentAgreement(context, ref)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.contentAgreementRequired)),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _sending = true);
    try {
      final session = await ref.read(
        conversationSessionProvider(widget.roomId).future,
      );
      await session.sendAttachment(draft);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.voiceSendFailed)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendAttachment() async {
    // Same publication gate as text: Guideline 1.2 wants the community rules
    // accepted before any content is contributed, and a photo is content.
    if (!await ensureContentAgreement(context, ref)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.contentAgreementRequired)),
        );
      }
      return;
    }
    if (!mounted) return;

    final draft = await pickAttachment(context);
    if (draft == null || !mounted) return;

    setState(() => _sending = true);
    try {
      final session = await ref.read(
        conversationSessionProvider(widget.roomId).future,
      );
      await session.sendAttachment(draft);
    } on MessageFailure catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure.code == MessageFailureCode.attachmentTooLarge
                  ? context.l10n.attachmentTooLarge
                  : context.l10n.attachmentSendFailed,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.attachmentSendFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _retryMessage(String transactionId) async {
    final session = await ref.read(
      conversationSessionProvider(widget.roomId).future,
    );
    await session.retryMessage(transactionId);
  }

  void _startReply(ChatMessage message) {
    setState(() {
      _editingMessage = null;
      _replyingTo = message;
    });
    _focusNode.requestFocus();
  }

  void _startEdit(ChatMessage message) {
    setState(() {
      _replyingTo = null;
      _editingMessage = message;
      _composer.text = message.body;
      _composer.selection = TextSelection.collapsed(
        offset: _composer.text.length,
      );
    });
    _focusNode.requestFocus();
  }

  void _cancelComposerMode() {
    setState(() {
      _replyingTo = null;
      _editingMessage = null;
      _composer.clear();
    });
  }

  Future<void> _showMessageActions(
    ChatMessage message,
    ConversationSnapshot snapshot,
  ) async {
    final isPinned = snapshot.pinnedEventIds.contains(message.eventId);
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (!message.isDeleted)
              _ActionTile(
                icon: Icons.reply_rounded,
                label: context.l10n.reply,
                action: _MessageAction.reply,
              ),
            if (!message.isDeleted)
              _ActionTile(
                icon: Icons.forward_rounded,
                label: context.l10n.forwardMessage,
                action: _MessageAction.forward,
              ),
            // Pinning is a room state change, so only somebody with the
            // power level for it is offered the choice.
            if (!message.isDeleted && snapshot.canPin)
              _ActionTile(
                icon: isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                label: isPinned
                    ? context.l10n.unpinMessage
                    : context.l10n.pinMessage,
                action: isPinned ? _MessageAction.unpin : _MessageAction.pin,
              ),
            if (!message.isDeleted)
              _ActionTile(
                icon: Icons.copy_rounded,
                label: context.l10n.copyMessage,
                action: _MessageAction.copy,
              ),
            if (!message.isDeleted)
              _ActionTile(
                icon: Icons.add_reaction_outlined,
                label: context.l10n.react,
                action: _MessageAction.react,
              ),
            if (message.isOwn &&
                !message.isDeleted &&
                message.deliveryState == MessageDeliveryState.synced)
              _ActionTile(
                icon: Icons.edit_outlined,
                label: context.l10n.editMessage,
                action: _MessageAction.edit,
              ),
            // Not only your own: whoever runs the group can take a message
            // down, and the room's power levels are what decide that.
            if (canOfferDelete(message))
              _ActionTile(
                icon: Icons.delete_outline_rounded,
                label: context.l10n.deleteMessage,
                action: _MessageAction.delete,
              ),
            if (!message.isOwn)
              _ActionTile(
                icon: Icons.flag_outlined,
                label: context.l10n.reportMessage,
                action: _MessageAction.report,
              ),
            // Next to Report, where somebody being harassed already is.
            // Their profile has the same button, but a profile is two screens
            // away from the message that made them want it.
            if (!message.isOwn)
              _ActionTile(
                icon: Icons.block_rounded,
                label: context.l10n.blockUser,
                action: _MessageAction.block,
              ),
            _ActionTile(
              icon: Icons.info_outline_rounded,
              label: context.l10n.messageDetails,
              action: _MessageAction.details,
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _MessageAction.reply:
        _startReply(message);
      case _MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.body));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.copiedToClipboard)),
          );
        }
      case _MessageAction.forward:
        await _forward(message);
      case _MessageAction.pin:
        await _setPinned(message.eventId, pinned: true);
      case _MessageAction.unpin:
        await _setPinned(message.eventId, pinned: false);
      case _MessageAction.react:
        await _chooseReaction(message);
      case _MessageAction.edit:
        _startEdit(message);
      case _MessageAction.delete:
        await _deleteMessage(message);
      case _MessageAction.report:
        await _reportMessage(message);
      case _MessageAction.block:
        await _blockSender(message);
      case _MessageAction.details:
        await _showMessageDetails(message);
    }
  }

  Future<void> _reportMessage(ChatMessage message) async {
    final submitted = await showReportSheet(
      context,
      reportedUserId: message.senderId,
      roomId: widget.roomId,
      eventId: message.eventId,
    );
    if (submitted && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.reportSubmitted)));
    }
  }

  /// Blocks whoever sent [message], after the same confirmation their
  /// profile asks for. Their messages leave this timeline at once, and the
  /// block is reported to moderators on the way (see
  /// MatrixProfileRepository.blockUser).
  Future<void> _blockSender(ChatMessage message) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.blockUserConfirmation(message.senderName)),
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
            child: Text(l10n.block),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final profiles = await ref.read(profileRepositoryProvider.future);
      await profiles.blockUser(message.senderId);
      messenger.showSnackBar(SnackBar(content: Text(l10n.userBlocked)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.blockFailed)));
    }
  }

  Future<void> _forward(ChatMessage message) async {
    final chats =
        ref.read(chatListProvider).valueOrNull ?? const <ChatSummary>[];
    final targets = chats
        .where((chat) => chat.roomId != widget.roomId && !chat.isInvite)
        .toList();
    if (!mounted) return;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.forwardNoChats)));
      return;
    }

    final targetId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                sheetContext.l10n.forwardTo,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: targets.length,
                itemBuilder: (context, index) {
                  final chat = targets[index];
                  return ListTile(
                    leading: ProfileAvatar(
                      label: chat.name,
                      imageUrl: chat.avatarUrl,
                      httpHeaders: chat.avatarHeaders,
                      radius: 18,
                    ),
                    title: Text(
                      chat.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(sheetContext, chat.roomId),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (targetId == null || !mounted) return;
    try {
      final session = await ref.read(
        conversationSessionProvider(widget.roomId).future,
      );
      await session.forwardTo(targetId, message);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.forwarded)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.messageActionFailed)));
    }
  }

  Future<void> _chooseReaction(ChatMessage message) async {
    final reaction = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.chooseReaction,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final emoji in _reactionOptions)
                    IconButton.filledTonal(
                      tooltip: emoji,
                      onPressed: () => Navigator.pop(context, emoji),
                      icon: Text(emoji, style: const TextStyle(fontSize: 24)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (reaction == null) return;
    await _toggleReaction(message.eventId, reaction);
  }

  Future<void> _toggleReaction(String eventId, String key) async {
    try {
      final session = await ref.read(
        conversationSessionProvider(widget.roomId).future,
      );
      await session.toggleReaction(eventId, key);
    } catch (_) {
      if (mounted) _showActionFailure();
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final scope = await showDialog<_DeleteScope>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteMessage),
        content: Text(context.l10n.deleteMessageConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _DeleteScope.local),
            child: Text(context.l10n.deleteForMe),
          ),
          if (message.canDeleteForEveryone)
            FilledButton(
              onPressed: () => Navigator.pop(context, _DeleteScope.everyone),
              child: Text(context.l10n.deleteForEveryone),
            ),
        ],
      ),
    );
    if (scope == null) return;
    try {
      final session = await ref.read(
        conversationSessionProvider(widget.roomId).future,
      );
      if (scope == _DeleteScope.local) {
        await session.deleteForMe(message.eventId);
      } else {
        await session.deleteForEveryone(message.eventId);
      }
    } catch (_) {
      if (mounted) _showActionFailure();
    }
  }

  Future<void> _showMessageDetails(ChatMessage message) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.messageDetails),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.senderName),
            const SizedBox(height: AppSpacing.sm),
            Text(
              MaterialLocalizations.of(
                context,
              ).formatFullDate(message.sentAt.toLocal()),
            ),
            Text(
              MaterialLocalizations.of(context).formatTimeOfDay(
                TimeOfDay.fromDateTime(message.sentAt.toLocal()),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SelectableText(message.eventId),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  void _showActionFailure() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.messageActionFailed)));
  }

  Future<void> _setPinned(String eventId, {required bool pinned}) async {
    try {
      await ref
          .read(conversationSessionProvider(widget.roomId).future)
          .then((session) => session.setPinned(eventId, pinned: pinned));
    } on MessageFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failure.code == MessageFailureCode.notAllowed
                ? context.l10n.pinNotAllowed
                : context.l10n.pinFailed,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.pinFailed)));
    }
  }

  /// Scrolls to [eventId], loading history behind it if it is not on screen.
  void _jumpTo(String eventId) {
    setState(() {
      _pendingJump = eventId;
      _jumpPagesLoaded = 0;
    });
  }

  Widget _buildPinnedBar(BuildContext context, ConversationSnapshot snapshot) {
    // Newest pin first: the last thing pinned is the thing people are being
    // pointed at.
    final pinned = snapshot.pinnedEventIds.reversed.toList();
    final cursor = _pinnedCursor % pinned.length;
    final eventId = pinned[cursor];
    final message = snapshot.messages
        .where((candidate) => candidate.eventId == eventId)
        .firstOrNull;

    return _PinnedBar(
      heading: pinned.length > 1
          ? context.l10n.pinnedCount(cursor + 1, pinned.length)
          : context.l10n.pinnedMessage,
      // Deeper history is not loaded yet, so there may be nothing to preview
      // until the jump has walked back to it.
      preview: message?.body ?? '',
      onTap: () {
        _jumpTo(eventId);
        // Leave the bar pointing at the next pin, so a second tap moves on
        // rather than bouncing to the same place.
        if (pinned.length > 1) {
          setState(() => _pinnedCursor = cursor + 1);
        }
      },
      onUnpin: snapshot.canPin
          ? () => unawaited(_setPinned(eventId, pinned: false))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final conversation = ref.watch(conversationProvider(widget.roomId));
    return conversation.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
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
                  onPressed: () => ref.invalidate(
                    conversationSessionProvider(widget.roomId),
                  ),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (snapshot) {
        // Only the most recent call in a room can be the one running now. The
        // room's liveness alone lit up every call it had ever had, so a second
        // call left the first one still offering to join it.
        final latestCallEventId = snapshot.messages
            .where((message) => message.isCallStart)
            .map((message) => message.eventId)
            .firstOrNull;
        if (_pendingJump != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_advanceJump(snapshot));
          });
        }
        return Scaffold(
          appBar: AppBar(
            titleSpacing: widget.embedded && widget.onClose == null
                ? AppSpacing.md
                : 0,
            automaticallyImplyLeading: !widget.embedded,
            leading: widget.onClose == null
                ? null
                : IconButton(
                    tooltip: context.l10n.callCloseChat,
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
            title: Row(
              children: [
                ProfileAvatar(
                  label: snapshot.title,
                  imageUrl: snapshot.avatarUrl,
                  httpHeaders: snapshot.avatarHeaders,
                  radius: 18,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        snapshot.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Presence, for the one person a direct chat is with.
                      // "Online" or when they were last around; nothing at
                      // all for somebody the server has never seen, which is
                      // more honest than "last seen never".
                      if (_presenceLine(context, snapshot) case final line?)
                        Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              if (widget.onClose == null &&
                  ref.watch(appConfigProvider).isCallsConfigured) ...[
                IconButton(
                  tooltip: context.l10n.startCall,
                  onPressed: () => openCall(
                    context,
                    widget.roomId,
                    withVideo: false,
                    ring: true,
                  ),
                  icon: const Icon(Icons.call_rounded),
                ),
                IconButton(
                  tooltip: context.l10n.startVideoCall,
                  onPressed: () => openCall(
                    context,
                    widget.roomId,
                    withVideo: true,
                    ring: true,
                  ),
                  icon: const Icon(Icons.videocam_rounded),
                ),
              ],
              if (!snapshot.isDirect)
                IconButton(
                  tooltip: context.l10n.groupDetails,
                  onPressed: () =>
                      context.push(AppRoutes.groupDetailsPath(widget.roomId)),
                  icon: const Icon(Icons.info_outline_rounded),
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                if (snapshot.pinnedEventIds.isNotEmpty)
                  _buildPinnedBar(context, snapshot),
                Expanded(
                  child: snapshot.messages.isEmpty
                      ? Center(child: Text(context.l10n.noMessagesYet))
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification.metrics.pixels >=
                                    notification.metrics.maxScrollExtent -
                                        160 &&
                                snapshot.canLoadOlder &&
                                !snapshot.isLoadingOlder) {
                              unawaited(_loadOlder());
                            }
                            return false;
                          },
                          child: ScrollablePositionedList.builder(
                            itemScrollController: _itemScroller,
                            reverse: true,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                            itemCount:
                                snapshot.messages.length +
                                (snapshot.isLoadingOlder ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == snapshot.messages.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(AppSpacing.md),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }
                              final message = snapshot.messages[index];
                              // Something that happened to the group rather
                              // than something somebody said: a line across
                              // the middle, where it happened.
                              final activity = message.activity;
                              if (activity != null) {
                                return SystemTimelineEntry(entry: activity);
                              }
                              // A call is not a message and does not read as
                              // one: no bubble, no sender column, and an
                              // action rather than text.
                              if (message.isCallStart) {
                                return _CallTimelineEntry(
                                  message: message,
                                  roomId: widget.roomId,
                                  isLatestCall:
                                      message.eventId == latestCallEventId,
                                );
                              }
                              // The list is reversed, so the next index is the
                              // message *above* this one. Consecutive messages
                              // from one person collapse into a single block.
                              final previous =
                                  index + 1 < snapshot.messages.length
                                  ? snapshot.messages[index + 1]
                                  : null;
                              return _MessageBubble(
                                message: message,
                                flat: widget.embedded,
                                highlighted:
                                    message.eventId == _highlightedEventId,
                                startsBlock:
                                    previous == null ||
                                    previous.senderId != message.senderId,
                                showSender: !snapshot.isDirect,
                                onLongPress: () => _showMessageActions(
                                  snapshot.messages[index],
                                  snapshot,
                                ),
                                onReactionTap: (key) => _toggleReaction(
                                  snapshot.messages[index].eventId,
                                  key,
                                ),
                                onReply: () => _startReply(message),
                                onPickReaction: () =>
                                    unawaited(_chooseReaction(message)),
                                onRetry:
                                    snapshot.messages[index].transactionId ==
                                            null ||
                                        snapshot
                                                .messages[index]
                                                .deliveryState !=
                                            MessageDeliveryState.failed
                                    ? null
                                    : () => _retryMessage(
                                        snapshot.messages[index].transactionId!,
                                      ),
                              );
                            },
                          ),
                        ),
                ),
                if (snapshot.typingUsers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${snapshot.typingUsers.join(', ')} ${context.l10n.typing}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ),
                if (_mentionQuery != null)
                  MentionSuggestions(
                    candidates: _mentionCandidates,
                    onSelected: _insertMention,
                  ),
                _MessageComposer(
                  controller: _composer,
                  focusNode: _focusNode,
                  sending: _sending,
                  onSend: _send,
                  onAttach: _sendAttachment,
                  onSendVoice: _sendVoice,
                  replyingTo: _replyingTo,
                  editingMessage: _editingMessage,
                  onCancelMode: _cancelComposerMode,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.message,
    required this.showSender,
    required this.onRetry,
    required this.onLongPress,
    required this.onReactionTap,
    required this.onReply,
    required this.onPickReaction,
    this.flat = false,
    this.startsBlock = true,
    this.highlighted = false,
  });

  final ChatMessage message;
  final bool showSender;
  final VoidCallback? onRetry;

  /// Opens the full action sheet. Long press on touch, right click on a
  /// desktop, and the "more" button on the hover row all land here.
  final VoidCallback onLongPress;
  final ValueChanged<String> onReactionTap;
  final VoidCallback onReply;
  final VoidCallback onPickReaction;

  /// Momentarily marked as the message a search jump landed on.
  final bool highlighted;

  /// Render as a full-width row with the sender alongside, rather than as a
  /// bubble aligned to one side. Bubbles work on a phone, where the screen is
  /// narrow enough that left and right reads as "them" and "me"; across a
  /// desktop pane they leave a gutter of empty space and the eye has to jump
  /// between two columns.
  final bool flat;

  /// False when the message above is from the same person, so a run of
  /// messages reads as one block instead of repeating the name and avatar.
  final bool startsBlock;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _hovered = false;

  ChatMessage get message => widget.message;
  bool get flat => widget.flat;
  bool get startsBlock => widget.startsBlock;
  bool get highlighted => widget.highlighted;
  bool get showSender => widget.showSender;
  VoidCallback get onLongPress => widget.onLongPress;
  VoidCallback? get onRetry => widget.onRetry;
  ValueChanged<String> get onReactionTap => widget.onReactionTap;

  @override
  Widget build(BuildContext context) {
    // A mouse never long-presses, which is why reactions felt absent on the
    // web: the only way in was a touch gesture. MouseRegion fires for pointer
    // devices only, so touch keeps the long press and loses nothing.
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // People try right-click on a desktop, and today they get the
        // browser's own menu.
        onSecondaryTap: onLongPress,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _buildMessage(context),
            if (_hovered && !message.isDeleted)
              Positioned(
                top: -6,
                right: AppSpacing.sm,
                child: _HoverActions(
                  onThumbsUp: () => onReactionTap('\u{1F44D}'),
                  onPickReaction: widget.onPickReaction,
                  onReply: widget.onReply,
                  onMore: onLongPress,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (flat) return _buildRow(context, scheme);

    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(message.isOwn ? 16 : 4),
      bottomRight: Radius.circular(message.isOwn ? 4 : 16),
    );
    return Align(
      alignment: message.isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Material(
        // The landed-on search hit flashes tertiary so the eye finds it in a
        // wall of bubbles, then fades back on a timer. A message that names
        // you keeps a permanent tint, so scrolling back through a busy room
        // shows what was actually aimed at you.
        color: highlighted
            ? scheme.tertiaryContainer
            : message.mentionsMe && !message.isOwn
            ? scheme.secondaryContainer
            : message.isOwn
            ? scheme.primaryContainer
            : scheme.surface,
        borderRadius: bubbleRadius,
        child: InkWell(
          onLongPress: onLongPress,
          borderRadius: bubbleRadius,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _content(context, scheme, showTime: true),
            ),
          ),
        ),
      ),
    );
  }

  /// The desktop row: avatar and name in the left gutter, message body filling
  /// the pane, and consecutive messages from one person tucked underneath.
  Widget _buildRow(BuildContext context, ColorScheme scheme) {
    final theme = Theme.of(context);
    return InkWell(
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.sm,
          startsBlock ? AppSpacing.sm : 1,
          AppSpacing.sm,
          2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: startsBlock
                  ? ProfileAvatar(label: message.senderName, radius: 18)
                  : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (startsBlock) ...[
                    Row(
                      textBaseline: TextBaseline.alphabetic,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      children: [
                        Flexible(
                          child: Text(
                            message.senderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          MaterialLocalizations.of(context).formatTimeOfDay(
                            TimeOfDay.fromDateTime(message.sentAt.toLocal()),
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                  ],
                  // The time already sits beside the name, so the trailing
                  // row carries only the edited marker and delivery state.
                  ..._content(context, scheme, showTime: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    ColorScheme scheme, {
    required bool showTime,
  }) {
    return [
      if (!flat && showSender && !message.isOwn) ...[
        Text(
          message.senderName,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: scheme.secondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
      ],
      if (message.replyTo != null) ...[
        _ReplyPreview(reply: message.replyTo!),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (message.isFromBlockedUser || message.isDeleted)
        Text(
          message.isFromBlockedUser
              ? context.l10n.blockedMessageHidden
              : context.l10n.messageDeleted,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        )
      else if (message.attachment != null)
        // The body of a file event is its filename, which the attachment view
        // already shows, so rendering both would say it twice.
        MessageAttachmentView(
          attachment: message.attachment!,
          onOpenImage: (attachment) =>
              showAttachmentViewer(context, attachment),
        )
      else
        FormattedMessageText(
          body: message.body,
          formattedBody: message.formattedBody,
          style: DefaultTextStyle.of(context).style,
        ),
      if (message.reactions.isNotEmpty && !message.isFromBlockedUser) ...[
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final reaction in message.reactions)
              _ReactionChip(
                reaction: reaction,
                onTap: () => onReactionTap(reaction.key),
              ),
          ],
        ),
      ],
      if (message.isForwarded) ...[
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.forward_rounded,
              size: 12,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
            Text(
              context.l10n.forwardedLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ],
      if (showTime || message.isEdited || message.isOwn) ...[
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTime)
              Text(
                MaterialLocalizations.of(context).formatTimeOfDay(
                  TimeOfDay.fromDateTime(message.sentAt.toLocal()),
                ),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            if (message.isEdited) ...[
              if (showTime) const SizedBox(width: AppSpacing.xs),
              Text(
                context.l10n.edited,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (message.isOwn) ...[
              const SizedBox(width: AppSpacing.xs),
              Tooltip(
                // The tick already said "Read"; in a group the question is
                // always who. Same disclosure as a reaction chip -- hover
                // where there is a pointer, long-press where there is not --
                // so there is one way to ask "who" across the timeline.
                message: message.readBy.isNotEmpty
                    ? context.l10n.readBy(message.readBy.join(', '))
                    : message.isRead
                    ? context.l10n.read
                    : '',
                child: Icon(
                  message.isRead
                      ? Icons.done_all_rounded
                      : _statusIcon(message.deliveryState),
                  size: 14,
                  color: message.deliveryState == MessageDeliveryState.failed
                      ? scheme.error
                      : message.isRead
                      ? scheme.secondary
                      : scheme.onSurfaceVariant,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(width: AppSpacing.xs),
                InkWell(
                  onTap: onRetry,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      context.l10n.retry,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ],
    ];
  }

  IconData _statusIcon(MessageDeliveryState status) => switch (status) {
    MessageDeliveryState.pending => Icons.schedule_rounded,
    MessageDeliveryState.sending => Icons.sync_rounded,
    MessageDeliveryState.sent => Icons.check_rounded,
    MessageDeliveryState.synced => Icons.check_rounded,
    MessageDeliveryState.failed => Icons.error_outline_rounded,
  };
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.reply});

  final MessageReplyPreview reply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.55),
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reply.senderName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            reply.body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.reaction, required this.onTap});

  final MessageReaction reaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chip = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: reaction.reactedByMe
              ? scheme.primary.withValues(alpha: 0.24)
              : scheme.surface.withValues(alpha: 0.65),
          border: Border.all(
            color: reaction.reactedByMe
                ? scheme.primary
                : scheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text('${reaction.key} ${reaction.count}'),
      ),
    );
    if (reaction.senderNames.isEmpty) return chip;
    // Who reacted: hover where there is a pointer, long-press where there is
    // not -- a Tooltip does both without a second gesture fighting the tap.
    return Tooltip(
      message: reaction.senderNames.join(', '),
      waitDuration: const Duration(milliseconds: 300),
      child: chip,
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.action,
  });

  final IconData icon;
  final String label;
  final _MessageAction action;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () => Navigator.pop(context, action),
    );
  }
}

class _MessageComposer extends StatefulWidget {
  const _MessageComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.onAttach,
    required this.onSendVoice,
    required this.replyingTo,
    required this.editingMessage,
    required this.onCancelMode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final Future<void> Function(AttachmentDraft draft) onSendVoice;
  final ChatMessage? replyingTo;
  final ChatMessage? editingMessage;
  final VoidCallback onCancelMode;

  @override
  State<_MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<_MessageComposer> {
  bool _emojiOpen = false;
  final _voice = VoiceRecorder();
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _toggleEmoji() {
    // The keyboard and the picker compete for the same space, so opening one
    // dismisses the other rather than stacking them.
    if (!_emojiOpen) FocusScope.of(context).unfocus();
    setState(() => _emojiOpen = !_emojiOpen);
  }

  @override
  void didUpdateWidget(covariant _MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    unawaited(_voice.dispose());
    super.dispose();
  }

  Future<void> _startRecording() async {
    FocusScope.of(context).unfocus();
    final started = await _voice.start(
      onTick: () {
        if (mounted) setState(() {});
      },
    );
    if (mounted && started) setState(() => _recording = true);
  }

  Future<void> _finishRecording({required bool send}) async {
    final draft = send ? await _voice.stop() : null;
    if (!send) await _voice.discard();
    if (mounted) setState(() => _recording = false);
    if (draft != null) await widget.onSendVoice(draft);
  }

  String _recordingClock() {
    final elapsed = _voice.elapsed;
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final canSend = widget.controller.text.trim().isNotEmpty && !widget.sending;
    final scheme = Theme.of(context).colorScheme;
    if (_recording) {
      return Material(
        color: scheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Icon(Icons.fiber_manual_record_rounded, color: scheme.error),
              const SizedBox(width: AppSpacing.sm),
              Text(
                context.l10n.voiceRecording,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _recordingClock(),
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: context.l10n.voiceDiscard,
                onPressed: () => _finishRecording(send: false),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              IconButton.filled(
                tooltip: context.l10n.sendMessage,
                onPressed: () => _finishRecording(send: true),
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      );
    }
    return Material(
      color: scheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.replyingTo != null || widget.editingMessage != null)
            _ComposerContext(
              message: widget.editingMessage ?? widget.replyingTo!,
              editing: widget.editingMessage != null,
              onCancel: widget.onCancelMode,
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: context.l10n.insertEmoji,
                  onPressed: _toggleEmoji,
                  icon: Icon(
                    _emojiOpen
                        ? Icons.keyboard_rounded
                        : Icons.emoji_emotions_outlined,
                  ),
                ),
                // Attaching mid-edit would silently abandon the edit, so the
                // button only appears when composing something new.
                if (widget.editingMessage == null)
                  IconButton(
                    tooltip: context.l10n.sendFile,
                    onPressed: widget.sending ? null : widget.onAttach,
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                Expanded(
                  // Formatting shortcuts are scoped to the composer rather
                  // than the screen, so Ctrl+B does nothing while the message
                  // list has focus.
                  child: CallbackShortcuts(
                    bindings: {
                      ...composerShortcuts(widget.controller),
                      // A multiline composer swallows plain Enter as a
                      // newline, which is right for prose and useless for
                      // sending. Ctrl+Enter — Cmd+Enter on a Mac — is the
                      // desk-keyboard send.
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        control: true,
                      ): () {
                        if (canSend) widget.onSend();
                      },
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        meta: true,
                      ): () {
                        if (canSend) widget.onSend();
                      },
                    },
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      contextMenuBuilder: (context, editableState) =>
                          buildComposerContextMenu(
                            context,
                            editableState,
                            widget.controller,
                          ),
                      onTap: () {
                        if (_emojiOpen) setState(() => _emojiOpen = false);
                      },
                      buildCounter:
                          (
                            _, {
                            required currentLength,
                            maxLength,
                            required isFocused,
                          }) => null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: context.l10n.messageInputHint,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) {
                        if (canSend) widget.onSend();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (widget.controller.text.trim().isEmpty &&
                    widget.editingMessage == null &&
                    !widget.sending)
                  IconButton.filled(
                    tooltip: context.l10n.voiceRecord,
                    onPressed: _startRecording,
                    icon: const Icon(Icons.mic_rounded),
                  )
                else
                  IconButton.filled(
                    tooltip: context.l10n.sendMessage,
                    onPressed: canSend ? widget.onSend : null,
                    icon: widget.sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            widget.editingMessage != null
                                ? Icons.check_rounded
                                : Icons.send_rounded,
                          ),
                  ),
              ],
            ),
          ),
          if (_emojiOpen)
            SizedBox(
              height: 280,
              child: EmojiPicker(
                onEmojiSelected: (_, emoji) =>
                    insertEmoji(widget.controller, emoji.emoji),
                config: Config(
                  height: 280,
                  emojiViewConfig: const EmojiViewConfig(
                    columns: 8,
                    emojiSizeMax: 28,
                    backgroundColor: Colors.transparent,
                  ),
                  categoryViewConfig: CategoryViewConfig(
                    backgroundColor: Colors.transparent,
                    iconColor: scheme.onSurfaceVariant,
                    iconColorSelected: scheme.primary,
                    indicatorColor: scheme.primary,
                  ),
                  bottomActionBarConfig: const BottomActionBarConfig(
                    enabled: false,
                  ),
                  searchViewConfig: SearchViewConfig(
                    backgroundColor: scheme.surfaceContainerHighest,
                    hintText: context.l10n.emojiSearchHint,
                  ),
                  skinToneConfig: const SkinToneConfig(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ComposerContext extends StatelessWidget {
  const _ComposerContext({
    required this.message,
    required this.editing,
    required this.onCancel,
  });

  final ChatMessage message;
  final bool editing;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 38, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  editing
                      ? context.l10n.editingMessage
                      : '${context.l10n.replyingTo} ${message.senderName}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.secondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  message.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.l10n.cancel,
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// The tap-through bar of pinned messages at the top of a room.
class _PinnedBar extends StatelessWidget {
  const _PinnedBar({
    required this.heading,
    required this.preview,
    required this.onTap,
    this.onUnpin,
  });

  final String heading;
  final String preview;
  final VoidCallback onTap;
  final VoidCallback? onUnpin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.push_pin_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      heading,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (preview.trim().isNotEmpty)
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (onUnpin != null)
                IconButton(
                  tooltip: context.l10n.unpinMessage,
                  onPressed: onUnpin,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A call in the timeline: joinable while it is up, a missed call once it is
/// not.
///
/// Liveness is asked of the room rather than read off the event, because the
/// event says only that somebody rang. Whether there is still a call to join
/// is a question about now.
class _CallTimelineEntry extends ConsumerWidget {
  const _CallTimelineEntry({
    required this.message,
    required this.roomId,
    required this.isLatestCall,
  });

  final ChatMessage message;
  final String roomId;

  /// Whether this is the newest call in the room. An older one is over by
  /// definition — a room runs one call at a time — so it must not offer to
  /// join whatever is happening now.
  final bool isLatestCall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roomHasCall =
        ref
            .watch(liveCallsProvider)
            .valueOrNull
            ?.any((call) => call.roomId == roomId) ??
        false;
    // The room being on a call says nothing about *this* call unless this is
    // the newest one.
    final isLive = isLatestCall && roomHasCall;
    // Call back earns its place only while calling back is a plausible next
    // move: on somebody else's recent missed call. Your own ended calls and
    // anything stale read as history, not as an invitation -- a chat full of
    // buttons is what "always appearing" complaints are made of.
    final isRecent =
        DateTime.now().difference(message.sentAt) < const Duration(minutes: 15);
    final offerAction = isLive || (!message.isOwn && isRecent);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: isLive ? scheme.tertiaryContainer : scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.xs,
            top: AppSpacing.xs,
            bottom: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isLive ? Icons.call_rounded : Icons.phone_missed_rounded,
                size: 15,
                color: isLive
                    ? scheme.onTertiaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  isLive
                      ? (message.isOwn
                            ? context.l10n.youStartedCall
                            : context.l10n.callStartedBy(message.senderName))
                      // Nobody is in it now. For the person who was called
                      // that is a missed call; for the caller it is just a
                      // call that happened.
                      : (message.isOwn
                            ? context.l10n.youStartedCall
                            : context.l10n.missedCall),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isLive
                        ? scheme.onTertiaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (offerAction) ...[
                const SizedBox(width: AppSpacing.xs),
                TextButton(
                  onPressed: () => openCall(
                    context,
                    roomId,
                    withVideo: false,
                    // Joining a running call must not re-ring it; calling
                    // back a finished one has to ring, or nobody hears it.
                    ring: !isLive,
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                  ),
                  child: Text(
                    isLive ? context.l10n.joinCall : context.l10n.callBack,
                  ),
                ),
              ] else
                const SizedBox(width: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

/// The row of actions that appears when a mouse points at a message.
///
/// Hidden until pointed at, so a busy room stays clean — a permanent control
/// on every message is clutter, and a control nobody can find is not a
/// feature. Everything here already exists in the long-press sheet; this is
/// the desktop way in, and "more" opens that same sheet rather than a second
/// copy of it.
class _HoverActions extends StatelessWidget {
  const _HoverActions({
    required this.onThumbsUp,
    required this.onPickReaction,
    required this.onReply,
    required this.onMore,
  });

  final VoidCallback onThumbsUp;
  final VoidCallback onPickReaction;
  final VoidCallback onReply;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(18),
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HoverAction(
              tooltip: context.l10n.react,
              onPressed: onThumbsUp,
              // The reaction people actually use, one click away.
              child: const Text('\u{1F44D}', style: TextStyle(fontSize: 15)),
            ),
            _HoverAction(
              tooltip: context.l10n.chooseReaction,
              onPressed: onPickReaction,
              child: Icon(
                Icons.add_reaction_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
            _HoverAction(
              tooltip: context.l10n.reply,
              onPressed: onReply,
              child: Icon(
                Icons.reply_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
            _HoverAction(
              tooltip: context.l10n.messageActions,
              onPressed: onMore,
              child: Icon(
                Icons.more_horiz_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoverAction extends StatelessWidget {
  const _HoverAction({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: child,
        ),
      ),
    );
  }
}
