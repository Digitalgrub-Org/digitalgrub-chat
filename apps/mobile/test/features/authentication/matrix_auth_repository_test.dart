import 'package:dg_chat/core/config/app_config.dart';
import 'package:dg_chat/core/storage/hidden_event_store.dart';
import 'package:dg_chat/core/storage/outgoing_message_store.dart';
import 'package:dg_chat/features/authentication/data/matrix_auth_repository.dart';
import 'package:dg_chat/features/authentication/domain/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:mocktail/mocktail.dart';

class _MockClient extends Mock implements Client {}

class _MemoryHiddenEventStore implements HiddenEventStore {
  final Map<String, Set<String>> _hidden = {};
  final List<String> clearedUsers = [];

  String _key(String userId, String roomId) => '$userId|$roomId';

  @override
  Future<Set<String>> read(String userId, String roomId) async =>
      _hidden[_key(userId, roomId)] ?? const {};

  @override
  Future<void> hide(String userId, String roomId, String eventId) async {
    _hidden.putIfAbsent(_key(userId, roomId), () => {}).add(eventId);
  }

  @override
  Future<void> deleteForUser(String userId) async {
    clearedUsers.add(userId);
    _hidden.removeWhere((key, _) => key.startsWith('$userId|'));
  }
}

void main() {
  late _MockClient client;
  late MatrixAuthRepository repository;
  late MemoryOutgoingMessageStore outgoingMessageStore;
  late _MemoryHiddenEventStore hiddenEventStore;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://fallback.example.com'));
    registerFallbackValue(AuthenticationUserIdentifier(user: 'fallback-user'));
    registerFallbackValue(AuthenticationData());
  });

  setUp(() {
    client = _MockClient();
    outgoingMessageStore = MemoryOutgoingMessageStore();
    hiddenEventStore = _MemoryHiddenEventStore();
    repository = MatrixAuthRepository(
      client: client,
      config: AppConfig(homeserver: Uri.parse('https://chat.example.com')),
      outgoingMessageStore: outgoingMessageStore,
      hiddenEventStore: hiddenEventStore,
    );
    _stubHomeserverDiscovery(client);
  });

  tearDown(() => outgoingMessageStore.close());

  test('logs in with password and requests a refresh token', () async {
    when(
      () => client.login(
        any(),
        identifier: any(named: 'identifier'),
        password: any(named: 'password'),
        initialDeviceDisplayName: any(named: 'initialDeviceDisplayName'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer(
      (_) async => LoginResponse(
        accessToken: 'access-token',
        deviceId: 'DEVICE',
        userId: '@alice:chat.example.com',
      ),
    );
    when(() => client.isLogged()).thenReturn(true);
    when(() => client.userID).thenReturn('@alice:chat.example.com');

    final session = await repository.login(
      username: ' alice ',
      password: 'ValidPassword1',
    );

    expect(session.userId, '@alice:chat.example.com');
    final captured =
        verify(
              () => client.login(
                LoginType.mLoginPassword,
                identifier: captureAny(named: 'identifier'),
                password: 'ValidPassword1',
                initialDeviceDisplayName: 'Digitalgrub Chat Mobile',
                refreshToken: true,
              ),
            ).captured.single
            as AuthenticationUserIdentifier;
    expect(captured.user, 'alice');
  });

  test('completes Synapse dummy UI-auth and saves profile fields', () async {
    var registrationCalls = 0;
    when(
      () => client.checkUsernameAvailability(any()),
    ).thenAnswer((_) async => true);
    when(
      () => client.register(
        username: any(named: 'username'),
        password: any(named: 'password'),
        initialDeviceDisplayName: any(named: 'initialDeviceDisplayName'),
        refreshToken: any(named: 'refreshToken'),
        auth: any(named: 'auth'),
      ),
    ).thenAnswer((invocation) async {
      registrationCalls++;
      final auth = invocation.namedArguments[#auth] as AuthenticationData?;
      if (auth == null) {
        throw MatrixException.fromJson({
          'session': 'uia-session',
          'flows': [
            {
              'stages': [AuthenticationTypes.dummy],
            },
          ],
        });
      }
      expect(auth.type, AuthenticationTypes.dummy);
      expect(auth.session, 'uia-session');
      return RegisterResponse(userId: '@alice:chat.example.com');
    });
    when(() => client.userID).thenReturn('@alice:chat.example.com');
    when(
      () => client.setProfileField(any(), any(), any()),
    ).thenAnswer((_) async => {});
    when(
      () => client.setAccountData(any(), any(), any()),
    ).thenAnswer((_) async {});

    final session = await repository.register(
      const RegistrationRequest(
        username: 'alice',
        password: 'ValidPassword1',
        displayName: 'Alice Example',
        mobileNumber: '+919876543210',
      ),
    );

    expect(registrationCalls, 2);
    expect(session.userId, '@alice:chat.example.com');
    verify(
      () => client.setProfileField('@alice:chat.example.com', 'displayname', {
        'displayname': 'Alice Example',
      }),
    ).called(1);
    verify(
      () => client.setAccountData(
        '@alice:chat.example.com',
        'com.digitalgrub.profile',
        {'mobile_number': '+919876543210', 'mobile_number_verified': false},
      ),
    ).called(1);
  });

  test('maps invalid password and rate-limit Matrix errors', () async {
    when(
      () => client.login(
        any(),
        identifier: any(named: 'identifier'),
        password: any(named: 'password'),
        initialDeviceDisplayName: any(named: 'initialDeviceDisplayName'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenThrow(
      MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'Invalid username or password',
      }),
    );

    await expectLater(
      repository.login(username: 'alice', password: 'wrong'),
      throwsA(
        isA<AuthFailure>().having(
          (failure) => failure.code,
          'code',
          AuthFailureCode.invalidCredentials,
        ),
      ),
    );

    reset(client);
    _stubHomeserverDiscovery(client);
    when(
      () => client.login(
        any(),
        identifier: any(named: 'identifier'),
        password: any(named: 'password'),
        initialDeviceDisplayName: any(named: 'initialDeviceDisplayName'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenThrow(
      MatrixException.fromJson({
        'errcode': 'M_LIMIT_EXCEEDED',
        'error': 'Slow down',
        'retry_after_ms': 1500,
      }),
    );

    await expectLater(
      repository.login(username: 'alice', password: 'wrong'),
      throwsA(
        isA<AuthFailure>()
            .having(
              (failure) => failure.code,
              'code',
              AuthFailureCode.rateLimited,
            )
            .having(
              (failure) => failure.retryAfter,
              'retryAfter',
              const Duration(milliseconds: 1500),
            ),
      ),
    );
  });

  test('clears the local session when remote logout fails', () async {
    when(() => client.userID).thenReturn('@alice:chat.example.com');
    when(() => client.logout()).thenThrow(Exception('offline'));
    when(() => client.isLogged()).thenReturn(true);
    when(() => client.clear()).thenAnswer((_) async {});
    final now = DateTime.utc(2026, 8, 1);
    await outgoingMessageStore.put(
      OutgoingMessage(
        transactionId: 'logout-txn',
        ownerUserId: '@alice:chat.example.com',
        roomId: '!room:chat.example.com',
        body: 'Remove me',
        createdAt: now,
        status: OutgoingMessageStatus.pending,
        attemptCount: 0,
        nextAttemptAt: now,
      ),
    );

    await repository.logout();

    verify(() => client.clear()).called(1);
    expect(
      await outgoingMessageStore.readForUser('@alice:chat.example.com'),
      isEmpty,
    );
  });

  test('clears local delete-for-me records on logout', () async {
    when(() => client.userID).thenReturn('@alice:chat.example.com');
    when(() => client.logout()).thenAnswer((_) async {});
    await hiddenEventStore.hide(
      '@alice:chat.example.com',
      '!room:test',
      'event-1',
    );

    await repository.logout();

    expect(hiddenEventStore.clearedUsers, ['@alice:chat.example.com']);
    expect(
      await hiddenEventStore.read('@alice:chat.example.com', '!room:test'),
      isEmpty,
    );
  });
}

void _stubHomeserverDiscovery(_MockClient client) {
  when(() => client.checkHomeserver(any())).thenAnswer(
    (_) async => (
      null,
      GetVersionsResponse(versions: ['v1.19']),
      [LoginFlow(type: AuthenticationTypes.password)],
      null,
    ),
  );
}
