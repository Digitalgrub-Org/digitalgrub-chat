import 'dart:async';

import 'package:dg_chat/features/groups/domain/group_repository.dart';

class FakeGroupRepository implements GroupRepository {
  @override
  Future<List<GroupActivityEntry>> activity(String roomId) async => const [];

  FakeGroupRepository({GroupDetails? group, this.createdRoomId = '!group:test'})
    : _group = group;

  GroupDetails? _group;
  final String createdRoomId;
  final _updates = StreamController<GroupDetails>.broadcast();

  final List<({String name, String? description, List<String> memberIds})>
  createRequests = [];
  final List<(String, List<String>)> addedMembers = [];
  final List<(String, String)> removedMembers = [];
  final List<(String, String, GroupRole)> roleChanges = [];
  final List<(String, String)> renames = [];
  final List<(String, String)> descriptionChanges = [];
  final List<(String, AvatarUpload?)> avatarChanges = [];
  final List<String> leftRooms = [];

  GroupFailure? createFailure;
  GroupFailure? mutationFailure;

  @override
  Future<String> createGroup({
    required String name,
    String? description,
    required List<String> memberIds,
  }) async {
    createRequests.add((
      name: name,
      description: description,
      memberIds: memberIds,
    ));
    final failure = createFailure;
    if (failure != null) throw failure;
    return createdRoomId;
  }

  @override
  Stream<GroupDetails> watchGroup(String roomId) async* {
    final group = _group;
    if (group == null) throw const GroupFailure(GroupFailureCode.roomNotFound);
    yield group;
    yield* _updates.stream;
  }

  void emit(GroupDetails group) {
    _group = group;
    _updates.add(group);
  }

  @override
  Future<void> addMembers(String roomId, List<String> userIds) async {
    addedMembers.add((roomId, userIds));
    _throwIfConfigured();
  }

  @override
  Future<void> removeMember(String roomId, String userId) async {
    removedMembers.add((roomId, userId));
    _throwIfConfigured();
  }

  @override
  Future<void> setMemberRole(
    String roomId,
    String userId,
    GroupRole role,
  ) async {
    roleChanges.add((roomId, userId, role));
    _throwIfConfigured();
  }

  @override
  Future<void> updateName(String roomId, String name) async {
    renames.add((roomId, name));
    _throwIfConfigured();
  }

  @override
  Future<void> updateDescription(String roomId, String description) async {
    descriptionChanges.add((roomId, description));
    _throwIfConfigured();
  }

  @override
  Future<void> updateAvatar(String roomId, AvatarUpload? avatar) async {
    avatarChanges.add((roomId, avatar));
    _throwIfConfigured();
  }

  @override
  Future<void> leaveGroup(String roomId) async {
    leftRooms.add(roomId);
    _throwIfConfigured();
  }

  void _throwIfConfigured() {
    final failure = mutationFailure;
    if (failure != null) throw failure;
  }

  Future<void> dispose() => _updates.close();
}
