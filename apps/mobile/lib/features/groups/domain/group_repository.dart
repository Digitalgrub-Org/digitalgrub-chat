import 'package:dg_chat/features/profile/domain/profile_repository.dart'
    show AvatarUpload;

export 'package:dg_chat/features/profile/domain/profile_repository.dart'
    show AvatarUpload;

/// Product limit for MVP 1, including the creator. It is enforced in the
/// domain layer only; nothing in the storage or transport design depends on it.
const int maxGroupMembers = 100;

/// Maximum characters accepted for a group name and description.
const int maxGroupNameLength = 64;
const int maxGroupDescriptionLength = 240;

enum GroupRole { member, moderator, admin }

enum GroupMembership { joined, invited }

class GroupMember {
  const GroupMember({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.membership,
    required this.isSelf,
    this.avatarUrl,
    this.avatarHeaders = const {},
  });

  final String userId;
  final String displayName;
  final GroupRole role;
  final GroupMembership membership;
  final bool isSelf;
  final Uri? avatarUrl;
  final Map<String, String> avatarHeaders;
}

/// What the signed-in account may do in a group, derived from the room's
/// effective power levels. Presentation must offer a control only when the
/// matching flag is set rather than assuming the viewer is an administrator.
class GroupPermissions {
  const GroupPermissions({
    this.canInvite = false,
    this.canRemove = false,
    this.canEditMetadata = false,
    this.canChangeRoles = false,
  });

  final bool canInvite;
  final bool canRemove;
  final bool canEditMetadata;
  final bool canChangeRoles;
}

class GroupDetails {
  const GroupDetails({
    required this.roomId,
    required this.name,
    required this.description,
    required this.members,
    required this.permissions,
    required this.ownRole,
    this.avatarUrl,
    this.avatarHeaders = const {},
  });

  final String roomId;
  final String name;
  final String description;
  final List<GroupMember> members;
  final GroupPermissions permissions;
  final GroupRole ownRole;
  final Uri? avatarUrl;
  final Map<String, String> avatarHeaders;

  int get memberCount => members.length;

  bool get isFull => members.length >= maxGroupMembers;

  int get remainingSeats {
    final remaining = maxGroupMembers - members.length;
    return remaining < 0 ? 0 : remaining;
  }
}

enum GroupFailureCode {
  invalidName,
  invalidDescription,
  noMembersSelected,
  memberLimitExceeded,
  notPermitted,
  roomNotFound,
  rateLimited,
  serverUnavailable,
  sessionExpired,
  unknown,
}

class GroupFailure implements Exception {
  const GroupFailure(this.code);

  final GroupFailureCode code;
}

/// One line of a group's activity log.
enum GroupActivityKind {
  created,
  joined,
  left,
  invited,
  removed,
  renamed,
  photoChanged,
  callStarted,
  pinsChanged,
  rolesChanged,
}

class GroupActivityEntry {
  const GroupActivityEntry({
    required this.kind,
    required this.actorName,
    required this.at,
    this.targetName,
    this.detail,
  });

  /// Who did it, already resolved to a display name.
  final String actorName;

  /// Who it was done to, for invites and removals.
  final String? targetName;

  /// The new value, where one exists — a new group name, say.
  final String? detail;

  final GroupActivityKind kind;
  final DateTime at;
}

abstract interface class GroupRepository {
  /// The room's recent activity, newest first: who joined, who left, who
  /// changed what. The log a group otherwise keeps silently.
  Future<List<GroupActivityEntry>> activity(String roomId);

  /// Creates a private group and returns its room id. [memberIds] excludes the
  /// creator, who is always joined.
  Future<String> createGroup({
    required String name,
    String? description,
    required List<String> memberIds,
  });

  /// Emits the current group and every later change to its metadata,
  /// membership, or power levels.
  Stream<GroupDetails> watchGroup(String roomId);

  Future<void> addMembers(String roomId, List<String> userIds);

  Future<void> removeMember(String roomId, String userId);

  Future<void> setMemberRole(String roomId, String userId, GroupRole role);

  Future<void> updateName(String roomId, String name);

  Future<void> updateDescription(String roomId, String description);

  /// Passing null removes the current group avatar.
  Future<void> updateAvatar(String roomId, AvatarUpload? avatar);

  Future<void> leaveGroup(String roomId);
}
