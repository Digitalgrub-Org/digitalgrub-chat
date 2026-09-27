import 'package:dg_chat/features/contacts/domain/user_repository.dart';
import 'package:dg_chat/features/groups/application/group_providers.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_group_repository.dart';
import '../../helpers/fake_stage3_repositories.dart';

void main() {
  late FakeGroupRepository groups;
  late NewGroupController controller;

  setUp(() {
    groups = FakeGroupRepository();
    controller = NewGroupController(
      () async => groups,
      () async => FakeUserRepository(results: const []),
    );
  });

  tearDown(() {
    controller.dispose();
    return groups.dispose();
  });

  test('toggling a person adds then removes the selection', () {
    const person = UserSearchResult(userId: '@maya:test', displayName: 'Maya');

    controller.toggleMember(person);
    expect(controller.state.selected.single.userId, '@maya:test');
    expect(controller.isSelected('@maya:test'), isTrue);

    controller.toggleMember(person);
    expect(controller.state.selected, isEmpty);
  });

  test('refuses a selection beyond the member limit', () {
    // The creator holds one seat, so the limit is reached one short.
    for (var index = 0; index < maxGroupMembers - 1; index++) {
      controller.toggleMember(
        UserSearchResult(userId: '@member$index:test', displayName: 'M$index'),
      );
    }
    expect(controller.state.selected, hasLength(maxGroupMembers - 1));
    expect(controller.state.remainingSeats, 0);

    controller.toggleMember(
      const UserSearchResult(userId: '@extra:test', displayName: 'Extra'),
    );

    expect(controller.state.selected, hasLength(maxGroupMembers - 1));
    expect(
      controller.state.failure?.code,
      GroupFailureCode.memberLimitExceeded,
    );
  });

  test('refuses to create without a selected member', () async {
    final roomId = await controller.create(name: 'Product crew');

    expect(roomId, isNull);
    expect(groups.createRequests, isEmpty);
    expect(controller.state.failure?.code, GroupFailureCode.noMembersSelected);
  });

  test('ignores a concurrent create so one group is made', () async {
    controller.toggleMember(
      const UserSearchResult(userId: '@maya:test', displayName: 'Maya'),
    );

    final first = controller.create(name: 'Product crew');
    final second = await controller.create(name: 'Product crew');

    expect(second, isNull);
    expect(await first, '!group:test');
    expect(groups.createRequests, hasLength(1));
    expect(controller.state.isCreating, isFalse);
  });

  test('keeps the selection when creation fails', () async {
    groups.createFailure = const GroupFailure(
      GroupFailureCode.serverUnavailable,
    );
    controller.toggleMember(
      const UserSearchResult(userId: '@maya:test', displayName: 'Maya'),
    );

    final roomId = await controller.create(name: 'Product crew');

    expect(roomId, isNull);
    expect(controller.state.selected, hasLength(1));
    expect(controller.state.isCreating, isFalse);
    expect(controller.state.failure?.code, GroupFailureCode.serverUnavailable);
  });
}
