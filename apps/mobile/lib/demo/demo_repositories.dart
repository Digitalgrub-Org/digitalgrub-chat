import 'dart:async';

import 'package:dg_chat/core/storage/outgoing_message_store.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:dg_chat/features/chats/domain/chat_repository.dart';
import 'package:dg_chat/features/contacts/domain/user_repository.dart';
import 'package:dg_chat/features/conversation/domain/message_repository.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:dg_chat/features/moderation/domain/report_repository.dart';
import 'package:dg_chat/features/profile/domain/profile_repository.dart';
import 'package:dg_chat/matrix/synchronization/messaging_runtime.dart';

/// In-memory data used only by `main_preview.dart` for visual review.
class DemoAuthRepository implements AuthRepository {
  final _changes = StreamController<AuthSession?>.broadcast();
  AuthSession? _session = const AuthSession(userId: '@preview:digitalgrub.com');

  @override
  Stream<AuthSession?> get sessionChanges => _changes.stream;

  @override
  Future<AuthSession?> restoreSession() async => _session;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final session = AuthSession(userId: '@$username:digitalgrub.com');
    _session = session;
    _changes.add(session);
    return session;
  }

  @override
  Future<AuthSession> register(RegistrationRequest request) =>
      login(username: request.username, password: request.password);

  @override
  Future<void> logout() async {
    _session = null;
    _changes.add(null);
  }

  @override
  Future<void> deleteAccount({
    required String password,
    AccountDeletionScope scope = AccountDeletionScope.erase,
  }) async => logout();

  // The preview build talks to nothing, so the email flows pretend to
  // succeed: the point is to look at the screens, and a preview that reports
  // failure would show only the error state.
  static const _previewEmail = 'preview@digitalgrub.com';
  var _emails = <String>[_previewEmail];

  EmailVerification _pending(String email) => EmailVerification(
    sid: 'demo-sid',
    clientSecret: 'demo-secret',
    email: email,
  );

  @override
  Future<EmailVerification> requestPasswordReset(String email) async =>
      _pending(email);

  @override
  Future<EmailVerification> resendPasswordReset(
    EmailVerification pending,
  ) async => pending.withNextAttempt(pending.sid);

  @override
  Future<void> completePasswordReset({
    required EmailVerification pending,
    required String newPassword,
  }) async {}

  @override
  Future<List<String>> emailAddresses() async => List.of(_emails);

  @override
  Future<EmailVerification> addEmailAddress(String email) async =>
      _pending(email);

  @override
  Future<void> confirmEmailAddress({
    required EmailVerification pending,
    required String password,
  }) async => _emails = [..._emails, pending.email];

  @override
  Future<void> removeEmailAddress(String email) async => _emails = [
    for (final e in _emails)
      if (e != email) e,
  ];
}

class DemoChatRepository implements ChatRepository {
  @override
  Stream<List<ChatSummary>> watchChats() => Stream.value(demoChats);

  @override
  Future<void> refresh() async {}

  @override
  Future<void> acceptInvite(String roomId) async {}

  @override
  Future<void> declineInvite(String roomId) async {}
}

class DemoUserRepository implements UserRepository {
  @override
  Future<List<UserSearchResult>> listServerUsers() async => search('');

  @override
  Future<List<UserSearchResult>> search(String query) async {
    final normalized = query.toLowerCase();
    return demoPeople
        .where(
          (person) =>
              person.displayName.toLowerCase().contains(normalized) ||
              person.userId.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }

  @override
  Future<String> startDirectConversation(String userId) async =>
      '!maya:digitalgrub.com';
}

class DemoMessageRepository implements MessageRepository {
  @override
  Future<ConversationSession> openConversation(String roomId) async {
    if (roomId == '!asha:digitalgrub.com') {
      return DemoConversationSession(demoAshaConversation);
    }
    if (roomId == '!product:digitalgrub.com') {
      return DemoConversationSession(demoProductConversation);
    }
    final chat = demoChats.where((chat) => chat.roomId == roomId).firstOrNull;
    return DemoConversationSession(
      ConversationSnapshot(
        roomId: roomId,
        title: chat?.name ?? 'Conversation',
        messages: const [],
        canLoadOlder: false,
        isLoadingOlder: false,
        isDirect: chat?.isDirect ?? true,
      ),
    );
  }
}

class DemoGroupRepository implements GroupRepository {
  @override
  Future<List<GroupActivityEntry>> activity(String roomId) async => const [];

  final _changes = StreamController<GroupDetails>.broadcast();
  GroupDetails _group = demoProductGroup;

  @override
  Future<String> createGroup({
    required String name,
    String? description,
    required List<String> memberIds,
  }) async => demoProductGroup.roomId;

  @override
  Stream<GroupDetails> watchGroup(String roomId) async* {
    yield _group;
    yield* _changes.stream;
  }

  @override
  Future<void> addMembers(String roomId, List<String> userIds) async {}

  @override
  Future<void> removeMember(String roomId, String userId) async {
    _emit(
      members: _group.members
          .where((member) => member.userId != userId)
          .toList(growable: false),
    );
  }

  @override
  Future<void> setMemberRole(
    String roomId,
    String userId,
    GroupRole role,
  ) async {
    _emit(
      members: _group.members
          .map(
            (member) => member.userId == userId
                ? GroupMember(
                    userId: member.userId,
                    displayName: member.displayName,
                    role: role,
                    membership: member.membership,
                    isSelf: member.isSelf,
                  )
                : member,
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> updateName(String roomId, String name) async =>
      _emit(name: name);

  @override
  Future<void> updateDescription(String roomId, String description) async =>
      _emit(description: description);

  @override
  Future<void> updateAvatar(String roomId, AvatarUpload? avatar) async {}

  @override
  Future<void> leaveGroup(String roomId) async {}

  void _emit({String? name, String? description, List<GroupMember>? members}) {
    _group = GroupDetails(
      roomId: _group.roomId,
      name: name ?? _group.name,
      description: description ?? _group.description,
      members: members ?? _group.members,
      permissions: _group.permissions,
      ownRole: _group.ownRole,
    );
    _changes.add(_group);
  }
}

class DemoConversationSession implements ConversationSession {
  DemoConversationSession(this._snapshot);

  ConversationSnapshot _snapshot;
  final _changes = StreamController<ConversationSnapshot>.broadcast();

  @override
  Stream<ConversationSnapshot> get changes async* {
    yield _snapshot;
    yield* _changes.stream;
  }

  @override
  Future<void> loadOlder() async {}

  @override
  @override
  Future<void> setPinned(String eventId, {required bool pinned}) async {}

  @override
  Future<void> forwardTo(String roomId, ChatMessage message) async {}

  @override
  Future<List<MentionCandidate>> mentionCandidates(String query) async =>
      const [];

  @override
  Future<void> retryMessage(String transactionId) async {
    _snapshot = ConversationSnapshot(
      roomId: _snapshot.roomId,
      title: _snapshot.title,
      messages: _snapshot.messages
          .map(
            (message) => message.transactionId == transactionId
                ? ChatMessage(
                    eventId: message.eventId,
                    transactionId: message.transactionId,
                    senderId: message.senderId,
                    senderName: message.senderName,
                    body: message.body,
                    sentAt: message.sentAt,
                    isOwn: message.isOwn,
                    deliveryState: MessageDeliveryState.pending,
                  )
                : message,
          )
          .toList(growable: false),
      canLoadOlder: _snapshot.canLoadOlder,
      isLoadingOlder: false,
      isDirect: _snapshot.isDirect,
    );
    _changes.add(_snapshot);
  }

  @override
  Future<void> sendText(String text, {String? replyToEventId}) async {}

  @override
  Future<void> sendAttachment(AttachmentDraft draft) async {}

  @override
  Future<void> editMessage(String eventId, String text) async {}

  @override
  Future<void> toggleReaction(String eventId, String key) async {}

  @override
  Future<void> deleteForMe(String eventId) async {}

  @override
  Future<void> deleteForEveryone(String eventId) async {}

  @override
  Future<void> updateTyping(bool isTyping) async {}

  @override
  void dispose() => unawaited(_changes.close());
}

class DemoProfileRepository implements ProfileRepository {
  final _profiles = StreamController<UserProfile>.broadcast();
  final _blocked = StreamController<List<UserProfile>>.broadcast();
  final _blockedIds = <String>{'@spam:digitalgrub.com'};
  UserProfile _own = demoOwnProfile;

  @override
  Stream<UserProfile> watchProfile(String userId) async* {
    yield userId == demoOwnProfile.userId
        ? _own
        : UserProfile(
            userId: userId,
            displayName: demoPeople
                .where((person) => person.userId == userId)
                .map((person) => person.displayName)
                .firstOrNull!,
            isSelf: false,
            about: 'Building the Digitalgrub mobile apps.',
            isBlocked: _blockedIds.contains(userId),
          );
    yield* _profiles.stream.where((profile) => profile.userId == userId);
  }

  @override
  Future<void> updateDisplayName(String displayName) async =>
      _emitOwn(displayName: displayName);

  @override
  Future<void> updateAbout(String about) async => _emitOwn(about: about);

  @override
  Future<void> updateMobileNumber(String? mobileNumber) async =>
      _emitOwn(mobileNumber: mobileNumber);

  @override
  Future<void> updateAvatar(AvatarUpload? avatar) async {}

  @override
  Stream<List<UserProfile>> watchBlockedUsers() async* {
    yield _readBlocked();
    yield* _blocked.stream;
  }

  @override
  Future<void> blockUser(String userId) async {
    _blockedIds.add(userId);
    _blocked.add(_readBlocked());
  }

  @override
  Future<void> unblockUser(String userId) async {
    _blockedIds.remove(userId);
    _blocked.add(_readBlocked());
  }

  List<UserProfile> _readBlocked() => _blockedIds
      .map(
        (userId) => UserProfile(
          userId: userId,
          displayName: userId,
          isSelf: false,
          isBlocked: true,
        ),
      )
      .toList(growable: false);

  void _emitOwn({String? displayName, String? about, String? mobileNumber}) {
    _own = UserProfile(
      userId: _own.userId,
      displayName: displayName ?? _own.displayName,
      isSelf: true,
      about: about ?? _own.about,
      mobileNumber: mobileNumber ?? _own.mobileNumber,
    );
    _profiles.add(_own);
  }
}

class DemoReportRepository implements ReportRepository {
  final List<ContentReport> submitted = [];

  @override
  Future<void> submit(ContentReport report) async => submitted.add(report);
}

class DemoMessagingRuntime implements MessagingRuntime {
  @override
  MessagingConnectionState get currentStatus =>
      MessagingConnectionState.offline;

  @override
  Stream<MessagingConnectionState> get statuses => Stream.value(currentStatus);

  @override
  Future<void> dispose() async {}

  @override
  Future<String> enqueueText(
    String roomId,
    String body, {
    String? replyToEventId,
    String? editEventId,
  }) async => 'demo-txn';

  @override
  Future<List<OutgoingMessage>> loadRoomOutbox(String roomId) async => const [];

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> retry(String transactionId) async {}

  @override
  Stream<List<OutgoingMessage>> watchRoomOutbox(String roomId) =>
      Stream.value(const []);
}

final demoChats = [
  ChatSummary(
    roomId: '!asha:digitalgrub.com',
    name: 'Asha Menon',
    lastMessage: 'The revised brief is uploading now.',
    lastActivity: DateTime(2026, 8, 1, 11, 22),
    unreadCount: 0,
    isDirect: true,
    pendingCount: 1,
    hasFailedMessages: true,
  ),
  ChatSummary(
    roomId: '!product:digitalgrub.com',
    name: 'Product crew',
    lastMessage: 'Maya: Joining from the office wifi.',
    lastActivity: DateTime(2026, 8, 1, 11, 8),
    unreadCount: 4,
    isDirect: false,
  ),
  ChatSummary(
    roomId: '!arjun:digitalgrub.com',
    name: 'Arjun Rao',
    lastMessage: 'Let us ship the smaller scope first.',
    lastActivity: DateTime(2026, 8, 1, 9, 15),
    unreadCount: 1,
    isDirect: true,
  ),
  ChatSummary(
    roomId: '!ops:digitalgrub.com',
    name: 'Operations',
    lastMessage: 'Sync is healthy across both homeservers.',
    lastActivity: DateTime(2026, 7, 31, 18, 40),
    unreadCount: 0,
    isDirect: false,
  ),
  ChatSummary(
    roomId: '!nisha:digitalgrub.com',
    name: 'Nisha Iyer',
    lastMessage: 'Thanks, talk tomorrow!',
    lastActivity: DateTime(2026, 7, 30, 20, 4),
    unreadCount: 0,
    isDirect: true,
  ),
];

const demoProductGroup = GroupDetails(
  roomId: '!product:digitalgrub.com',
  name: 'Product crew',
  description: 'Design, build, and ship the Digitalgrub apps.',
  ownRole: GroupRole.admin,
  permissions: GroupPermissions(
    canInvite: true,
    canRemove: true,
    canEditMetadata: true,
    canChangeRoles: true,
  ),
  members: [
    GroupMember(
      userId: '@preview:digitalgrub.com',
      displayName: 'Preview User',
      role: GroupRole.admin,
      membership: GroupMembership.joined,
      isSelf: true,
    ),
    GroupMember(
      userId: '@maya:digitalgrub.com',
      displayName: 'Maya Krishnan',
      role: GroupRole.moderator,
      membership: GroupMembership.joined,
      isSelf: false,
    ),
    GroupMember(
      userId: '@arjun:digitalgrub.com',
      displayName: 'Arjun Rao',
      role: GroupRole.member,
      membership: GroupMembership.joined,
      isSelf: false,
    ),
    GroupMember(
      userId: '@nisha:digitalgrub.com',
      displayName: 'Nisha Iyer',
      role: GroupRole.member,
      membership: GroupMembership.invited,
      isSelf: false,
    ),
  ],
);

const demoOwnProfile = UserProfile(
  userId: '@preview:digitalgrub.com',
  displayName: 'Preview User',
  isSelf: true,
  about: 'Product and design at Digitalgrub.',
  mobileNumber: '+91 90000 00000',
);

const demoPeople = [
  UserSearchResult(
    userId: '@maya:digitalgrub.com',
    displayName: 'Maya Krishnan',
  ),
  UserSearchResult(
    userId: '@mayank:digitalgrub.com',
    displayName: 'Mayank Shah',
  ),
  UserSearchResult(
    userId: '@maya.design:digitalgrub.com',
    displayName: 'Maya · Design',
  ),
];

/// A group, where the room's own story sits between the messages.
///
/// Direct chats never carry these lines, so previewing them needs a group.
final demoProductConversation = ConversationSnapshot(
  roomId: '!product:digitalgrub.com',
  title: 'Product crew',
  isDirect: false,
  canLoadOlder: false,
  isLoadingOlder: false,
  messages: [
    ChatMessage(
      eventId: 'product-14',
      senderId: '@maya:digitalgrub.com',
      senderName: 'Maya',
      body: 'Joining from the office wifi.',
      sentAt: DateTime(2026, 8, 1, 11, 8),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
    ),
    ChatMessage(
      eventId: 'product-13',
      senderId: '@arjun:digitalgrub.com',
      senderName: 'Arjun Rao',
      body: 'Works for me.',
      sentAt: DateTime(2026, 8, 1, 11, 6),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
      reactions: const [
        MessageReaction(
          key: '👍',
          count: 2,
          reactedByMe: true,
          senderNames: ['You', 'Maya'],
        ),
      ],
    ),
    ChatMessage(
      eventId: 'product-12',
      senderId: '@preview:digitalgrub.com',
      senderName: 'You',
      body: 'Shall we get on a call before lunch?',
      sentAt: DateTime(2026, 8, 1, 11, 4),
      isOwn: true,
      deliveryState: MessageDeliveryState.synced,
      isRead: true,
      canDeleteForEveryone: true,
    ),
    ChatMessage(
      eventId: 'product-11',
      senderId: '@maya:digitalgrub.com',
      senderName: 'Maya',
      body: 'Store screenshots are done as well — sending them across.',
      sentAt: DateTime(2026, 8, 1, 11, 2),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
    ),
    ChatMessage(
      eventId: 'product-10',
      senderId: '@arjun:digitalgrub.com',
      senderName: 'Arjun Rao',
      body: 'Perfect. I will start on the release notes.',
      sentAt: DateTime(2026, 8, 1, 10, 58),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
    ),
    ChatMessage(
      eventId: 'product-9',
      senderId: '@preview:digitalgrub.com',
      senderName: 'You',
      body: 'Nice. I will cut the build once QA signs off.',
      sentAt: DateTime(2026, 8, 1, 10, 56),
      isOwn: true,
      deliveryState: MessageDeliveryState.synced,
      isRead: true,
      canDeleteForEveryone: true,
    ),
    ChatMessage(
      eventId: 'product-8',
      senderId: '@maya:digitalgrub.com',
      senderName: 'Maya',
      body: 'Calls ring on a locked phone now — tested on both platforms.',
      sentAt: DateTime(2026, 8, 1, 10, 53),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
      reactions: const [
        MessageReaction(
          key: '🎉',
          count: 3,
          reactedByMe: true,
          senderNames: ['You', 'Arjun Rao', 'Maya'],
        ),
      ],
    ),
    ChatMessage(
      eventId: 'product-7',
      senderId: '@arjun:digitalgrub.com',
      senderName: 'Arjun Rao',
      body: 'Great. Anything left on the call side?',
      sentAt: DateTime(2026, 8, 1, 10, 50),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
    ),
    ChatMessage(
      eventId: 'product-6',
      senderId: '@maya:digitalgrub.com',
      senderName: 'Maya',
      body: 'The mobile flow is ready for QA',
      sentAt: DateTime(2026, 8, 1, 10, 48),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
    ),
    ChatMessage(
      eventId: 'product-5',
      senderId: '@preview:digitalgrub.com',
      senderName: 'You',
      body: '',
      sentAt: DateTime(2026, 8, 1, 10, 44),
      isOwn: true,
      deliveryState: MessageDeliveryState.synced,
      activity: GroupActivityEntry(
        kind: GroupActivityKind.renamed,
        actorName: 'You',
        detail: 'Product crew',
        at: DateTime(2026, 8, 1, 10, 44),
      ),
    ),
    ChatMessage(
      eventId: 'product-4',
      senderId: '@preview:digitalgrub.com',
      senderName: 'You',
      body: '',
      sentAt: DateTime(2026, 8, 1, 10, 41),
      isOwn: true,
      deliveryState: MessageDeliveryState.synced,
      activity: GroupActivityEntry(
        kind: GroupActivityKind.joined,
        actorName: 'Maya',
        at: DateTime(2026, 8, 1, 10, 41),
      ),
    ),
    ChatMessage(
      eventId: 'product-3',
      senderId: '@arjun:digitalgrub.com',
      senderName: 'Arjun Rao',
      body: 'Adding Maya so she can pick up the QA pass.',
      sentAt: DateTime(2026, 8, 1, 10, 39),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
    ),
    ChatMessage(
      eventId: 'product-2',
      senderId: '@preview:digitalgrub.com',
      senderName: 'You',
      body: '',
      sentAt: DateTime(2026, 8, 1, 10, 30),
      isOwn: true,
      deliveryState: MessageDeliveryState.synced,
      activity: GroupActivityEntry(
        kind: GroupActivityKind.invited,
        actorName: 'Arjun Rao',
        targetName: 'Maya',
        at: DateTime(2026, 8, 1, 10, 30),
      ),
    ),
    ChatMessage(
      eventId: 'product-1',
      senderId: '@preview:digitalgrub.com',
      senderName: 'You',
      body: '',
      sentAt: DateTime(2026, 8, 1, 10, 28),
      isOwn: true,
      deliveryState: MessageDeliveryState.synced,
      activity: GroupActivityEntry(
        kind: GroupActivityKind.created,
        actorName: 'You',
        at: DateTime(2026, 8, 1, 10, 28),
      ),
    ),
  ],
);

final demoAshaConversation = ConversationSnapshot(
  roomId: '!asha:digitalgrub.com',
  title: 'Asha Menon',
  isDirect: true,
  canLoadOlder: true,
  isLoadingOlder: false,
  typingUsers: const ['Asha Menon'],
  messages: [
    ChatMessage(
      eventId: 'local-failed',
      transactionId: 'dg-42',
      senderId: '@preview:digitalgrub.com',
      senderName: 'You',
      body: 'The revised brief is uploading now.',
      sentAt: DateTime(2026, 8, 1, 11, 22),
      isOwn: true,
      deliveryState: MessageDeliveryState.failed,
      canDeleteForEveryone: true,
    ),
    ChatMessage(
      eventId: 'event-4',
      senderId: '@asha:digitalgrub.com',
      senderName: 'Asha Menon',
      body: 'Perfect — I will review it before lunch.',
      sentAt: DateTime(2026, 8, 1, 11, 20),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
      replyTo: const MessageReplyPreview(
        eventId: 'event-3',
        senderName: 'You',
        body: 'The onboarding flow is ready for QA.',
      ),
      reactions: const [
        MessageReaction(
          key: '👍',
          count: 2,
          reactedByMe: false,
          senderNames: ['Asha Menon', 'Arjun Rao'],
        ),
        MessageReaction(
          key: '🎉',
          count: 1,
          reactedByMe: true,
          senderNames: ['You'],
        ),
      ],
    ),
    ChatMessage(
      eventId: 'event-3',
      senderId: '@preview:digitalgrub.com',
      senderName: 'You',
      body: 'The onboarding flow is ready for QA.',
      sentAt: DateTime(2026, 8, 1, 11, 18),
      isOwn: true,
      deliveryState: MessageDeliveryState.synced,
      isEdited: true,
      isRead: true,
      canDeleteForEveryone: true,
    ),
    ChatMessage(
      eventId: 'event-2',
      senderId: '@asha:digitalgrub.com',
      senderName: 'Asha Menon',
      body: 'Looks clean. Can we keep the gold accent?',
      sentAt: DateTime(2026, 8, 1, 11, 17),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
    ),
    ChatMessage(
      eventId: 'event-1',
      senderId: '@preview:digitalgrub.com',
      senderName: 'You',
      body: 'Yes — deep teal for structure, gold for emphasis.',
      sentAt: DateTime(2026, 8, 1, 11, 15),
      isOwn: true,
      deliveryState: MessageDeliveryState.synced,
      isRead: true,
      canDeleteForEveryone: true,
    ),
    ChatMessage(
      eventId: 'event-0c',
      senderId: '@asha:digitalgrub.com',
      senderName: 'Asha Menon',
      body: 'Sending the palette over now.',
      sentAt: DateTime(2026, 8, 1, 11, 12),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
    ),
    ChatMessage(
      eventId: 'event-0b',
      senderId: '@preview:digitalgrub.com',
      senderName: 'You',
      body: 'Morning — did the brand colours land?',
      sentAt: DateTime(2026, 8, 1, 11, 10),
      isOwn: true,
      deliveryState: MessageDeliveryState.synced,
      isRead: true,
      canDeleteForEveryone: true,
    ),
    ChatMessage(
      eventId: 'event-0a',
      senderId: '@asha:digitalgrub.com',
      senderName: 'Asha Menon',
      body: 'Good morning!',
      sentAt: DateTime(2026, 8, 1, 11, 8),
      isOwn: false,
      deliveryState: MessageDeliveryState.synced,
    ),
  ],
);
