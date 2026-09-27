import 'dart:async';

import 'package:dg_chat/features/groups/data/group_activity_mapper.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:matrix/matrix.dart';

class MatrixGroupRepository implements GroupRepository {
  MatrixGroupRepository(this._client);

  final Client _client;

  @override
  Future<String> createGroup({
    required String name,
    String? description,
    required List<String> memberIds,
  }) async {
    final groupName = _validateName(name);
    final topic = _validateDescription(description);
    final invites = _normalizeInvites(memberIds);
    if (invites.isEmpty) {
      throw const GroupFailure(GroupFailureCode.noMembersSelected);
    }
    // The creator occupies one seat.
    if (invites.length + 1 > maxGroupMembers) {
      throw const GroupFailure(GroupFailureCode.memberLimitExceeded);
    }

    try {
      return await _client.createGroupChat(
        groupName: groupName,
        invite: invites,
        preset: CreateRoomPreset.privateChat,
        visibility: Visibility.private,
        // MVP 1 is explicitly not end-to-end encrypted.
        enableEncryption: false,
        // Federation is disabled by server configuration and must stay
        // configurable later; `m.federate` is permanent per room, so it is
        // deliberately left at the default here.
        initialState: [
          if (topic.isNotEmpty)
            StateEvent(type: EventTypes.RoomTopic, content: {'topic': topic}),
        ],
      );
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    } on GroupFailure {
      rethrow;
    } catch (_) {
      throw const GroupFailure(GroupFailureCode.serverUnavailable);
    }
  }

  @override
  Stream<GroupDetails> watchGroup(String roomId) async* {
    await _client.roomsLoading;
    final room = _requireRoom(roomId);
    // Fills the local member cache once; later reads are served from the
    // state that sync keeps current.
    await _loadParticipants(room);
    yield await _readGroup(room);

    final updates = StreamController<void>();
    final subscription = _client.onSync.stream.listen((_) {
      if (!updates.isClosed) updates.add(null);
    });
    try {
      await for (final _ in updates.stream) {
        final current = _client.getRoomById(roomId);
        // A leave or a remote removal ends the stream rather than emitting a
        // half-populated group.
        if (current == null || current.membership != Membership.join) return;
        yield await _readGroup(current);
      }
    } finally {
      await subscription.cancel();
      await updates.close();
    }
  }

  @override
  Future<void> addMembers(String roomId, List<String> userIds) async {
    final room = _requireRoom(roomId);
    if (!room.canInvite) {
      throw const GroupFailure(GroupFailureCode.notPermitted);
    }

    final existing = _participants(room).map((user) => user.id).toSet();
    final invites = _normalizeInvites(
      userIds,
    ).where((userId) => !existing.contains(userId)).toList(growable: false);
    if (invites.isEmpty) {
      throw const GroupFailure(GroupFailureCode.noMembersSelected);
    }
    if (existing.length + invites.length > maxGroupMembers) {
      throw const GroupFailure(GroupFailureCode.memberLimitExceeded);
    }

    await _guard(() async {
      for (final userId in invites) {
        await room.invite(userId);
      }
    });
  }

  @override
  Future<void> removeMember(String roomId, String userId) async {
    final room = _requireRoom(roomId);
    if (!room.canKick) {
      throw const GroupFailure(GroupFailureCode.notPermitted);
    }
    // Matrix refuses to remove a member whose power level is not below the
    // remover's; failing early keeps the UI honest.
    if (userId != _client.userID &&
        room.getPowerLevelByUserId(userId) >= room.ownPowerLevel) {
      throw const GroupFailure(GroupFailureCode.notPermitted);
    }
    await _guard(() => room.kick(userId));
  }

  @override
  Future<void> setMemberRole(
    String roomId,
    String userId,
    GroupRole role,
  ) async {
    final room = _requireRoom(roomId);
    if (!room.canChangePowerLevel) {
      throw const GroupFailure(GroupFailureCode.notPermitted);
    }
    final level = _levelForRole(role);
    // A member cannot grant a level above their own.
    if (PowerLevel(level) > room.ownPowerLevel) {
      throw const GroupFailure(GroupFailureCode.notPermitted);
    }
    await _guard(() => room.setPower(userId, level));
  }

  @override
  Future<void> updateName(String roomId, String name) async {
    final room = _requireRoom(roomId);
    final value = _validateName(name);
    if (!room.canChangeStateEvent(EventTypes.RoomName)) {
      throw const GroupFailure(GroupFailureCode.notPermitted);
    }
    await _guard(() => room.setName(value));
  }

  @override
  Future<void> updateDescription(String roomId, String description) async {
    final room = _requireRoom(roomId);
    final value = _validateDescription(description);
    if (!room.canChangeStateEvent(EventTypes.RoomTopic)) {
      throw const GroupFailure(GroupFailureCode.notPermitted);
    }
    await _guard(() => room.setDescription(value));
  }

  @override
  Future<void> updateAvatar(String roomId, AvatarUpload? avatar) async {
    final room = _requireRoom(roomId);
    if (!room.canChangeStateEvent(EventTypes.RoomAvatar)) {
      throw const GroupFailure(GroupFailureCode.notPermitted);
    }
    await _guard(
      () => room.setAvatar(
        avatar == null
            ? null
            : MatrixFile(bytes: avatar.bytes, name: avatar.fileName),
      ),
    );
  }

  @override
  Future<List<GroupActivityEntry>> activity(String roomId) async {
    final room = _requireRoom(roomId);
    final Timeline timeline;
    try {
      timeline = await room.getTimeline();
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    } catch (_) {
      throw const GroupFailure(GroupFailureCode.serverUnavailable);
    }
    try {
      if (timeline.events.length < 60 && timeline.canRequestHistory) {
        try {
          await timeline.requestHistory(historyCount: 120);
        } catch (_) {
          // The log shows what is loaded; deeper history failing to page in
          // is not worth failing the whole screen for.
        }
      }
      final entries = <GroupActivityEntry>[];
      for (final event in timeline.events) {
        final entry = activityEntryOf(event, room);
        if (entry != null) entries.add(entry);
      }
      return entries;
    } finally {
      timeline.cancelSubscriptions();
    }
  }

  @override
  Future<void> leaveGroup(String roomId) async {
    final room = _requireRoom(roomId);
    await _guard(room.leave);
    try {
      // Forgetting is what makes leaving mean something: it clears the room
      // and its cached history from this device and from the account's
      // archive, so no stale route can resurrect what was left behind.
      await room.forget();
    } catch (_) {
      // The leave already succeeded. A failed forget leaves an archived
      // room the UI never shows; not worth failing the action over.
    }
  }

  Future<GroupDetails> _readGroup(Room room) async {
    final participants = _participants(room);
    final ownUserId = _client.userID;

    final members = await Future.wait(
      participants.map((user) async {
        final avatarUrl = await _thumbnail(user.avatarUrl);
        return GroupMember(
          userId: user.id,
          displayName: user.calcDisplayname(),
          role: _roleForLevel(room.getPowerLevelByUserId(user.id)),
          membership: user.membership == Membership.invite
              ? GroupMembership.invited
              : GroupMembership.joined,
          isSelf: user.id == ownUserId,
          avatarUrl: avatarUrl,
          avatarHeaders: avatarUrl == null ? const {} : _mediaHeaders,
        );
      }),
    );
    members.sort(_compareMembers);

    final avatarUrl = await _thumbnail(room.avatar);
    final name = room.name.trim();

    return GroupDetails(
      roomId: room.id,
      name: name.isEmpty ? room.getLocalizedDisplayname() : name,
      description: room.topic.trim(),
      members: members,
      ownRole: _roleForLevel(room.ownPowerLevel),
      permissions: GroupPermissions(
        canInvite: room.canInvite,
        canRemove: room.canKick,
        canEditMetadata:
            room.canChangeStateEvent(EventTypes.RoomName) &&
            room.canChangeStateEvent(EventTypes.RoomTopic) &&
            room.canChangeStateEvent(EventTypes.RoomAvatar),
        canChangeRoles: room.canChangePowerLevel,
      ),
      avatarUrl: avatarUrl,
      avatarHeaders: avatarUrl == null ? const {} : _mediaHeaders,
    );
  }

  /// Administrators first, then invited members, then display name.
  int _compareMembers(GroupMember a, GroupMember b) {
    final byRole = b.role.index.compareTo(a.role.index);
    if (byRole != 0) return byRole;
    final byMembership = a.membership.index.compareTo(b.membership.index);
    if (byMembership != 0) return byMembership;
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  List<User> _participants(Room room) =>
      room.getParticipants(const [Membership.join, Membership.invite]);

  Future<void> _loadParticipants(Room room) async {
    try {
      await room.requestParticipants(const [
        Membership.join,
        Membership.invite,
      ]);
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    } catch (_) {
      // The cached member list stays usable when the server cannot be reached.
    }
  }

  Future<Uri?> _thumbnail(Uri? source) async {
    if (source == null) return null;
    final thumbnail = await source.getThumbnailUri(
      _client,
      width: 96,
      height: 96,
    );
    return thumbnail.hasScheme ? thumbnail : null;
  }

  Room _requireRoom(String roomId) {
    final room = _client.getRoomById(roomId);
    if (room == null) throw const GroupFailure(GroupFailureCode.roomNotFound);
    return room;
  }

  List<String> _normalizeInvites(List<String> userIds) {
    final normalized = <String>{};
    for (final userId in userIds) {
      final value = userId.trim();
      if (value.isEmpty || value == _client.userID) continue;
      if (!value.isValidMatrixIdStrict()) continue;
      normalized.add(value);
    }
    return normalized.toList(growable: false);
  }

  String _validateName(String name) {
    final value = name.trim();
    if (value.isEmpty || value.length > maxGroupNameLength) {
      throw const GroupFailure(GroupFailureCode.invalidName);
    }
    return value;
  }

  String _validateDescription(String? description) {
    final value = description?.trim() ?? '';
    if (value.length > maxGroupDescriptionLength) {
      throw const GroupFailure(GroupFailureCode.invalidDescription);
    }
    return value;
  }

  int _levelForRole(GroupRole role) => switch (role) {
    GroupRole.admin => PowerLevel.defaultAdminLevel,
    GroupRole.moderator => PowerLevel.defaultModeratorLevel,
    GroupRole.member => PowerLevel.defaultUserLevel,
  };

  GroupRole _roleForLevel(PowerLevel level) => switch (level.role) {
    PowerLevelRole.owner || PowerLevelRole.admin => GroupRole.admin,
    PowerLevelRole.moderator => GroupRole.moderator,
    PowerLevelRole.user => GroupRole.member,
  };

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on MatrixException catch (error) {
      throw _mapFailure(error);
    } on GroupFailure {
      rethrow;
    } catch (_) {
      throw const GroupFailure(GroupFailureCode.serverUnavailable);
    }
  }

  Map<String, String> get _mediaHeaders {
    final token = _client.accessToken;
    return token == null ? const {} : {'authorization': 'Bearer $token'};
  }

  GroupFailure _mapFailure(MatrixException error) {
    return switch (error.error) {
      MatrixError.M_FORBIDDEN => const GroupFailure(
        GroupFailureCode.notPermitted,
      ),
      MatrixError.M_LIMIT_EXCEEDED => const GroupFailure(
        GroupFailureCode.rateLimited,
      ),
      MatrixError.M_UNKNOWN_TOKEN => const GroupFailure(
        GroupFailureCode.sessionExpired,
      ),
      MatrixError.M_NOT_FOUND => const GroupFailure(
        GroupFailureCode.roomNotFound,
      ),
      _ => const GroupFailure(GroupFailureCode.serverUnavailable),
    };
  }
}
