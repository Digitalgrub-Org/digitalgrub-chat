import 'package:dg_chat/features/search/data/matrix_search_repository.dart';
import 'package:dg_chat/features/search/domain/search_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:mocktail/mocktail.dart';

class _MockClient extends Mock implements Client {}

class _MockRoom extends Mock implements Room {}

class _MockUser extends Mock implements User {}

class _FakeCategories extends Fake implements Categories {}

MatrixEvent _event({
  String type = EventTypes.Message,
  String body = 'hello world',
  String roomId = '!team:test',
  String eventId = r'$hit1',
  String senderId = '@maya:test',
}) {
  return MatrixEvent.fromJson({
    'type': type,
    'event_id': eventId,
    'sender': senderId,
    'room_id': roomId,
    'origin_server_ts': DateTime.utc(2026, 8, 10, 9).millisecondsSinceEpoch,
    'content': {'msgtype': 'm.text', 'body': body},
  });
}

SearchResults _serverReturns(List<MatrixEvent> events) {
  return SearchResults(
    searchCategories: ResultCategories(
      roomEvents: ResultRoomEvents(
        results: [for (final event in events) Result(result: event)],
      ),
    ),
  );
}

void main() {
  late _MockClient client;
  late _MockRoom room;
  late MatrixSearchRepository repository;

  setUpAll(() => registerFallbackValue(_FakeCategories()));

  setUp(() {
    client = _MockClient();
    room = _MockRoom();
    repository = MatrixSearchRepository(client);

    final sender = _MockUser();
    when(() => sender.calcDisplayname()).thenReturn('Maya');
    when(() => client.getRoomById(any())).thenReturn(room);
    when(() => room.membership).thenReturn(Membership.join);
    when(() => room.getLocalizedDisplayname()).thenReturn('Team room');
    when(
      () => room.unsafeGetUserFromMemoryOrFallback(any()),
    ).thenReturn(sender);
  });

  test('maps a hit into a result row', () async {
    when(
      () => client.search(any(), nextBatch: any(named: 'nextBatch')),
    ).thenAnswer((_) async => _serverReturns([_event()]));

    final results = await repository.searchMessages('hello');

    final hit = results.single;
    expect(hit.roomId, '!team:test');
    expect(hit.roomName, 'Team room');
    expect(hit.senderName, 'Maya');
    expect(hit.body, 'hello world');
    expect(hit.eventId, r'$hit1');
  });

  test('asks the server for recent messages matching the term', () async {
    when(
      () => client.search(any(), nextBatch: any(named: 'nextBatch')),
    ).thenAnswer((_) async => _serverReturns([]));

    await repository.searchMessages('  budget  ');

    final categories =
        verify(
              () => client.search(
                captureAny(),
                nextBatch: any(named: 'nextBatch'),
              ),
            ).captured.single
            as Categories;
    expect(categories.roomEvents?.searchTerm, 'budget');
    expect(categories.roomEvents?.orderBy, SearchOrder.recent);
  });

  test('an empty term never contacts the server', () async {
    expect(await repository.searchMessages('   '), isEmpty);
    verifyNever(() => client.search(any(), nextBatch: any(named: 'nextBatch')));
  });

  test('drops hits in rooms the account has left', () async {
    // A row for an unopenable room is a dead tap.
    when(() => room.membership).thenReturn(Membership.leave);
    when(
      () => client.search(any(), nextBatch: any(named: 'nextBatch')),
    ).thenAnswer((_) async => _serverReturns([_event()]));

    expect(await repository.searchMessages('hello'), isEmpty);
  });

  test('drops hits whose room is unknown locally', () async {
    when(() => client.getRoomById(any())).thenReturn(null);
    when(
      () => client.search(any(), nextBatch: any(named: 'nextBatch')),
    ).thenAnswer((_) async => _serverReturns([_event()]));

    expect(await repository.searchMessages('hello'), isEmpty);
  });

  test('drops non-message and empty-bodied hits', () async {
    when(
      () => client.search(any(), nextBatch: any(named: 'nextBatch')),
    ).thenAnswer(
      (_) async => _serverReturns([
        _event(type: 'm.room.topic'),
        _event(body: '   '),
        _event(body: 'kept', eventId: r'$kept'),
      ]),
    );

    final results = await repository.searchMessages('hello');

    expect(results.single.eventId, r'$kept');
  });

  test('maps an expired session', () async {
    when(
      () => client.search(any(), nextBatch: any(named: 'nextBatch')),
    ).thenThrow(
      MatrixException.fromJson({'errcode': 'M_UNKNOWN_TOKEN', 'error': 'x'}),
    );

    await expectLater(
      repository.searchMessages('hello'),
      throwsA(
        isA<SearchFailure>().having(
          (failure) => failure.code,
          'code',
          SearchFailureCode.sessionExpired,
        ),
      ),
    );
  });
}
