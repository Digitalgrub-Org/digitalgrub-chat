import 'package:dg_chat/features/meetings/data/matrix_meeting_repository.dart';
import 'package:dg_chat/features/meetings/domain/meeting_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:mocktail/mocktail.dart';

class _MockClient extends Mock implements Client {}

class _MockRoom extends Mock implements Room {}

void main() {
  late _MockClient client;
  late MatrixMeetingRepository repository;

  setUpAll(() {
    registerFallbackValue(CreateRoomPreset.publicChat);
    registerFallbackValue(Visibility.private);
  });

  setUp(() {
    client = _MockClient();
    repository = MatrixMeetingRepository(client);
    when(() => client.roomsLoading).thenAnswer((_) async {});
    when(() => client.userID).thenReturn('@dgtest1:chat.example.com');
  });

  group('createMeeting', () {
    test('creates a public-join room behind a short code', () async {
      when(
        () => client.createRoom(
          name: any(named: 'name'),
          preset: any(named: 'preset'),
          visibility: any(named: 'visibility'),
          roomAliasName: any(named: 'roomAliasName'),
          initialState: any(named: 'initialState'),
        ),
      ).thenAnswer((_) async => '!meet:test');

      final meeting = await repository.createMeeting('  Standup  ');

      expect(meeting.roomId, '!meet:test');
      expect(meeting.title, 'Standup');
      // Meet-shaped and free of lookalike letters, because codes get read
      // aloud and typed from a phone screen.
      expect(
        meeting.code,
        matches(
          RegExp(r'^[a-hj-km-np-z]{3}-[a-hj-km-np-z]{4}-[a-hj-km-np-z]{3}$'),
        ),
      );
      final captured = verify(
        () => client.createRoom(
          name: captureAny(named: 'name'),
          preset: captureAny(named: 'preset'),
          visibility: captureAny(named: 'visibility'),
          roomAliasName: captureAny(named: 'roomAliasName'),
          initialState: captureAny(named: 'initialState'),
        ),
      ).captured;
      expect(captured[0], 'Standup');
      // The link IS the invitation: public join rules, or the link is dead.
      expect(captured[1], CreateRoomPreset.publicChat);
      // Joinable by code is not the same as advertised in a directory.
      expect(captured[2], Visibility.private);
      // The code is the alias, so the server is the code directory.
      expect(captured[3], meeting.code);
      final state = captured[4] as List<StateEvent>;
      expect(
        state.any(
          (event) => event.type == MatrixMeetingRepository.meetingMarkerType,
        ),
        isTrue,
      );
    });

    test('retries with a fresh code when the alias is taken', () async {
      var calls = 0;
      when(
        () => client.createRoom(
          name: any(named: 'name'),
          preset: any(named: 'preset'),
          visibility: any(named: 'visibility'),
          roomAliasName: any(named: 'roomAliasName'),
          initialState: any(named: 'initialState'),
        ),
      ).thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          throw MatrixException.fromJson({
            'errcode': 'M_ROOM_IN_USE',
            'error': 'taken',
          });
        }
        return '!meet:test';
      });

      final meeting = await repository.createMeeting('Standup');

      expect(meeting.roomId, '!meet:test');
      expect(calls, 2);
    });
  });

  group('ensureJoined', () {
    test('does nothing when already a member', () async {
      final room = _MockRoom();
      when(() => room.membership).thenReturn(Membership.join);
      when(() => client.getRoomById('!meet:test')).thenReturn(room);

      expect(await repository.ensureJoined('!meet:test'), '!meet:test');

      verifyNever(() => client.joinRoom(any()));
    });

    test('resolves a short code through its alias', () async {
      when(
        () => client.getRoomIdByAlias('#abc-defg-hij:chat.example.com'),
      ).thenAnswer((_) async => GetRoomIdByAliasResponse(roomId: '!meet:test'));
      final room = _MockRoom();
      when(() => room.membership).thenReturn(Membership.join);
      when(() => client.getRoomById('!meet:test')).thenReturn(room);

      expect(await repository.ensureJoined('abc-defg-hij'), '!meet:test');
    });

    test('maps an unknown code to notJoinable', () async {
      when(() => client.getRoomIdByAlias(any())).thenThrow(
        MatrixException.fromJson({'errcode': 'M_NOT_FOUND', 'error': 'x'}),
      );

      await expectLater(
        repository.ensureJoined('zzz-zzzz-zzz'),
        throwsA(
          isA<MeetingFailure>().having(
            (failure) => failure.code,
            'code',
            MeetingFailureCode.notJoinable,
          ),
        ),
      );
    });

    test('joins on first contact and waits for the room to sync', () async {
      when(() => client.getRoomById('!meet:test')).thenReturn(null);
      when(() => client.joinRoom(any())).thenAnswer((_) async => '!meet:test');
      when(
        () => client.waitForRoomInSync('!meet:test', join: true),
      ).thenAnswer((_) async => SyncUpdate(nextBatch: ''));

      expect(await repository.ensureJoined('!meet:test'), '!meet:test');

      verify(() => client.joinRoom('!meet:test')).called(1);
      // Without the sync wait the call screen opens on a room the local
      // client does not have yet, which reads as room-not-found.
      verify(
        () => client.waitForRoomInSync('!meet:test', join: true),
      ).called(1);
    });

    test('maps a dead link to notJoinable', () async {
      when(() => client.getRoomById(any())).thenReturn(null);
      when(() => client.joinRoom(any())).thenThrow(
        MatrixException.fromJson({'errcode': 'M_NOT_FOUND', 'error': 'gone'}),
      );

      await expectLater(
        repository.ensureJoined('!gone:test'),
        throwsA(
          isA<MeetingFailure>().having(
            (failure) => failure.code,
            'code',
            MeetingFailureCode.notJoinable,
          ),
        ),
      );
    });
  });

  test('meeting links carry the encoded room id', () {
    // Room ids contain ! and :, both of which must survive a mail client.
    const roomId = '!abc:chat.example.com';
    final link = Uri.parse(
      'https://chat.example.com/meet/${Uri.encodeComponent(roomId)}',
    );
    expect(link.pathSegments.last, roomId);
  });
}
