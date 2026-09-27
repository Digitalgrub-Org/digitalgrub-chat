import 'package:dg_chat/features/groups/data/matrix_group_repository.dart';
import 'package:dg_chat/features/groups/domain/group_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:mocktail/mocktail.dart';

class _MockClient extends Mock implements Client {}

class _MockRoom extends Mock implements Room {}

void main() {
  late _MockClient client;
  late _MockRoom room;
  late MatrixGroupRepository repository;

  setUpAll(() {
    registerFallbackValue(CreateRoomPreset.privateChat);
    registerFallbackValue(Visibility.private);
  });

  setUp(() {
    client = _MockClient();
    room = _MockRoom();
    repository = MatrixGroupRepository(client);
    when(() => client.userID).thenReturn('@current:test');
    when(() => client.accessToken).thenReturn('token');
    when(() => client.getRoomById('!group:test')).thenReturn(room);
    when(() => room.id).thenReturn('!group:test');
  });

  group('createGroup', () {
    test('rejects a blank name before contacting the server', () async {
      await expectLater(
        repository.createGroup(name: '   ', memberIds: const ['@maya:test']),
        throwsA(
          isA<GroupFailure>().having(
            (failure) => failure.code,
            'code',
            GroupFailureCode.invalidName,
          ),
        ),
      );
      verifyNever(
        () => client.createGroupChat(
          groupName: any(named: 'groupName'),
          invite: any(named: 'invite'),
        ),
      );
    });

    test('rejects a group with no valid invitee', () async {
      await expectLater(
        repository.createGroup(
          name: 'Product crew',
          // Own id and a malformed id both drop out.
          memberIds: const ['@current:test', 'not-a-matrix-id'],
        ),
        throwsA(
          isA<GroupFailure>().having(
            (failure) => failure.code,
            'code',
            GroupFailureCode.noMembersSelected,
          ),
        ),
      );
    });

    test('rejects more invitees than the member limit allows', () async {
      final invitees = [
        for (var index = 0; index < maxGroupMembers; index++)
          '@member$index:test',
      ];

      await expectLater(
        repository.createGroup(name: 'Product crew', memberIds: invitees),
        throwsA(
          isA<GroupFailure>().having(
            (failure) => failure.code,
            'code',
            GroupFailureCode.memberLimitExceeded,
          ),
        ),
      );
    });

    test(
      'creates a private unencrypted room carrying the description',
      () async {
        Map<Symbol, dynamic>? arguments;
        when(
          () => client.createGroupChat(
            groupName: any(named: 'groupName'),
            invite: any(named: 'invite'),
            preset: any(named: 'preset'),
            visibility: any(named: 'visibility'),
            enableEncryption: any(named: 'enableEncryption'),
            initialState: any(named: 'initialState'),
          ),
        ).thenAnswer((invocation) async {
          arguments = invocation.namedArguments;
          return '!created:test';
        });

        final roomId = await repository.createGroup(
          name: '  Product crew  ',
          description: '  Ship the app  ',
          memberIds: const ['@maya:test', '@maya:test', '@current:test'],
        );

        expect(roomId, '!created:test');
        expect(arguments?[#groupName], 'Product crew');
        // The creator and the duplicate are removed.
        expect(arguments?[#invite], ['@maya:test']);
        expect(arguments?[#preset], CreateRoomPreset.privateChat);
        expect(arguments?[#visibility], Visibility.private);
        expect(arguments?[#enableEncryption], isFalse);
        final initialState = arguments?[#initialState] as List<StateEvent>;
        expect(initialState.single.type, EventTypes.RoomTopic);
        expect(initialState.single.content, {'topic': 'Ship the app'});
      },
    );
  });

  group('membership administration', () {
    test('refuses to remove a member without the power to do so', () async {
      when(() => room.canKick).thenReturn(false);

      await expectLater(
        repository.removeMember('!group:test', '@maya:test'),
        throwsA(
          isA<GroupFailure>().having(
            (failure) => failure.code,
            'code',
            GroupFailureCode.notPermitted,
          ),
        ),
      );
      verifyNever(() => room.kick(any()));
    });

    test('refuses to remove a member of equal power', () async {
      when(() => room.canKick).thenReturn(true);
      when(() => room.ownPowerLevel).thenReturn(PowerLevel(50));
      when(
        () => room.getPowerLevelByUserId('@peer:test'),
      ).thenReturn(PowerLevel(50));

      await expectLater(
        repository.removeMember('!group:test', '@peer:test'),
        throwsA(
          isA<GroupFailure>().having(
            (failure) => failure.code,
            'code',
            GroupFailureCode.notPermitted,
          ),
        ),
      );
      verifyNever(() => room.kick(any()));
    });

    test('removes a member of lower power', () async {
      when(() => room.canKick).thenReturn(true);
      when(() => room.ownPowerLevel).thenReturn(PowerLevel(100));
      when(
        () => room.getPowerLevelByUserId('@maya:test'),
      ).thenReturn(PowerLevel(0));
      when(() => room.kick('@maya:test')).thenAnswer((_) async {});

      await repository.removeMember('!group:test', '@maya:test');

      verify(() => room.kick('@maya:test')).called(1);
    });

    test('refuses to grant a role above the caller', () async {
      when(() => room.canChangePowerLevel).thenReturn(true);
      when(() => room.ownPowerLevel).thenReturn(PowerLevel(50));

      await expectLater(
        repository.setMemberRole('!group:test', '@maya:test', GroupRole.admin),
        throwsA(
          isA<GroupFailure>().having(
            (failure) => failure.code,
            'code',
            GroupFailureCode.notPermitted,
          ),
        ),
      );
      verifyNever(() => room.setPower(any(), any()));
    });

    test('promotes a member to moderator', () async {
      when(() => room.canChangePowerLevel).thenReturn(true);
      when(() => room.ownPowerLevel).thenReturn(PowerLevel(100));
      when(() => room.setPower('@maya:test', 50)).thenAnswer((_) async => 'ok');

      await repository.setMemberRole(
        '!group:test',
        '@maya:test',
        GroupRole.moderator,
      );

      verify(() => room.setPower('@maya:test', 50)).called(1);
    });

    test('reports a missing room', () async {
      when(() => client.getRoomById('!gone:test')).thenReturn(null);

      await expectLater(
        repository.leaveGroup('!gone:test'),
        throwsA(
          isA<GroupFailure>().having(
            (failure) => failure.code,
            'code',
            GroupFailureCode.roomNotFound,
          ),
        ),
      );
    });
  });

  group('metadata', () {
    test('refuses a rename without permission', () async {
      when(
        () => room.canChangeStateEvent(EventTypes.RoomName),
      ).thenReturn(false);

      await expectLater(
        repository.updateName('!group:test', 'Renamed'),
        throwsA(
          isA<GroupFailure>().having(
            (failure) => failure.code,
            'code',
            GroupFailureCode.notPermitted,
          ),
        ),
      );
      verifyNever(() => room.setName(any()));
    });

    test('rejects an over-long description before any request', () async {
      when(
        () => room.canChangeStateEvent(EventTypes.RoomTopic),
      ).thenReturn(true);

      await expectLater(
        repository.updateDescription(
          '!group:test',
          'x' * (maxGroupDescriptionLength + 1),
        ),
        throwsA(
          isA<GroupFailure>().having(
            (failure) => failure.code,
            'code',
            GroupFailureCode.invalidDescription,
          ),
        ),
      );
      verifyNever(() => room.setDescription(any()));
    });

    test('maps a forbidden response to a permission failure', () async {
      when(
        () => room.canChangeStateEvent(EventTypes.RoomName),
      ).thenReturn(true);
      when(() => room.setName('Renamed')).thenThrow(
        MatrixException.fromJson({
          'errcode': 'M_FORBIDDEN',
          'error': 'You do not have permission',
        }),
      );

      await expectLater(
        repository.updateName('!group:test', 'Renamed'),
        throwsA(
          isA<GroupFailure>().having(
            (failure) => failure.code,
            'code',
            GroupFailureCode.notPermitted,
          ),
        ),
      );
    });
  });
}
