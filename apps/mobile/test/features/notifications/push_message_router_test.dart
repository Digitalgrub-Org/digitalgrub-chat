import 'package:dg_chat/features/notifications/application/push_message_router.dart';
import 'package:dg_chat/features/notifications/domain/push_notification.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingPresenter implements NotificationPresenter {
  final List<({PushNotification notification, String title})> shown = [];
  final List<String> dismissed = [];
  int initializeCount = 0;

  @override
  Future<void> initialize() async => initializeCount++;

  @override
  Future<void> show(
    PushNotification notification, {
    required String title,
  }) async => shown.add((notification: notification, title: title));

  @override
  Future<void> dismissForRoom(String roomId) async => dismissed.add(roomId);
}

void main() {
  group('PushNotification.fromPayload', () {
    test('reads a message push', () {
      final n = PushNotification.fromPayload({
        'room_id': '!room:test',
        'event_id': r'$event',
        'unread': 3,
      });

      expect(n, isNotNull);
      expect(n!.roomId, '!room:test');
      expect(n.eventId, r'$event');
      expect(n.unreadCount, 3);
      expect(n.isMessage, isTrue);
    });

    test('accepts an unread count sent as a string', () {
      // Gateways vary on whether counts arrive as numbers or strings.
      final n = PushNotification.fromPayload({
        'room_id': '!room:test',
        'event_id': r'$event',
        'unread': '7',
      });
      expect(n!.unreadCount, 7);
    });

    test('treats a push with no event as a badge update', () {
      final n = PushNotification.fromPayload({
        'room_id': '!room:test',
        'unread': 0,
      });
      expect(n, isNotNull);
      expect(n!.isMessage, isFalse);
    });

    test('rejects a payload that is not a push', () {
      expect(PushNotification.fromPayload(const {}), isNull);
      expect(PushNotification.fromPayload(const {'room_id': ''}), isNull);
      expect(PushNotification.fromPayload(const {'room_id': 42}), isNull);
    });
  });

  group('PushMessageRouter', () {
    test('shows a notification for a message in another room', () async {
      final presenter = _RecordingPresenter();
      final router = PushMessageRouter(
        presenter: presenter,
        activeRoomId: '!open:test',
      );

      final shown = await router.handle({
        'room_id': '!other:test',
        'event_id': r'$event',
        'unread': 2,
      }, messageTitle: 'New message');

      expect(shown, isTrue);
      expect(presenter.shown.single.notification.roomId, '!other:test');
      expect(presenter.shown.single.title, 'New message');
    });

    test('stays silent for the room already on screen', () async {
      final presenter = _RecordingPresenter();
      final router = PushMessageRouter(
        presenter: presenter,
        activeRoomId: '!open:test',
      );

      final shown = await router.handle({
        'room_id': '!open:test',
        'event_id': r'$event',
      }, messageTitle: 'New message');

      // Required by the product spec: no alert for the conversation the user
      // is currently reading.
      expect(shown, isFalse);
      expect(presenter.shown, isEmpty);
      // Anything already showing for that room is cleared instead.
      expect(presenter.dismissed, ['!open:test']);
    });

    test('notifies for every room when the app is backgrounded', () async {
      final presenter = _RecordingPresenter();
      // The background isolate cannot know what is on screen, and nothing is.
      final router = PushMessageRouter(
        presenter: presenter,
        activeRoomId: null,
      );

      final shown = await router.handle({
        'room_id': '!any:test',
        'event_id': r'$event',
      }, messageTitle: 'New message');

      expect(shown, isTrue);
    });

    test('does not alert for a counts-only push', () async {
      final presenter = _RecordingPresenter();
      final router = PushMessageRouter(
        presenter: presenter,
        activeRoomId: null,
      );

      final shown = await router.handle({
        'room_id': '!room:test',
        'unread': 0,
      }, messageTitle: 'New message');

      expect(shown, isFalse);
      expect(presenter.shown, isEmpty);
    });

    test('ignores a payload that is not a push', () async {
      final presenter = _RecordingPresenter();
      final router = PushMessageRouter(
        presenter: presenter,
        activeRoomId: null,
      );

      expect(
        await router.handle(const {}, messageTitle: 'New message'),
        isFalse,
      );
      expect(presenter.shown, isEmpty);
      expect(presenter.dismissed, isEmpty);
    });
  });

  group('a ringing call', () {
    test('suppresses the message notification for that same push', () async {
      final presenter = _RecordingPresenter();
      final router = PushMessageRouter(
        presenter: presenter,
        activeRoomId: null,
        ringingRoomId: '!call:test',
      );

      // The ring already raised a full-screen call surface. The gateway
      // cannot label this push as a call -- Sygnal forwards a fixed field
      // list and the event type is stripped by event_id_only -- so without
      // this the user gets "New message" sitting under a ringing phone.
      final shown = await router.handle({
        'room_id': '!call:test',
        'event_id': r'$ring',
      }, messageTitle: 'New message');

      expect(shown, isFalse);
      expect(presenter.shown, isEmpty);
    });

    test('still notifies for a different room', () async {
      final presenter = _RecordingPresenter();
      final router = PushMessageRouter(
        presenter: presenter,
        activeRoomId: null,
        ringingRoomId: '!call:test',
      );

      final shown = await router.handle({
        'room_id': '!other:test',
        'event_id': r'$msg',
      }, messageTitle: 'New message');

      expect(shown, isTrue);
      expect(presenter.shown.single.notification.roomId, '!other:test');
    });

    test('notifies normally once nothing is ringing', () async {
      final presenter = _RecordingPresenter();
      final router = PushMessageRouter(
        presenter: presenter,
        activeRoomId: null,
      );

      final shown = await router.handle({
        'room_id': '!call:test',
        'event_id': r'$msg',
      }, messageTitle: 'New message');

      expect(shown, isTrue);
    });
  });

  group('a preview', () {
    const push = {'room_id': '!other:test', 'event_id': r'$event'};

    test('titles and fills the notification with what it found', () async {
      final presenter = _RecordingPresenter();
      final router = PushMessageRouter(
        presenter: presenter,
        activeRoomId: null,
        describe: (_) async => const NotificationText(
          title: 'Asha Menon',
          body: 'are you coming?',
        ),
      );

      await router.handle(push, messageTitle: 'New message');

      final shown = presenter.shown.single;
      expect(shown.title, 'Asha Menon');
      expect(shown.notification.body, 'are you coming?');
      expect(shown.notification.roomId, '!other:test');
    });

    test(
      'falls back to the generic notification when it finds nothing',
      () async {
        final presenter = _RecordingPresenter();
        final router = PushMessageRouter(
          presenter: presenter,
          activeRoomId: null,
          describe: (_) async => null,
        );

        expect(await router.handle(push, messageTitle: 'New message'), isTrue);
        expect(presenter.shown.single.title, 'New message');
        expect(presenter.shown.single.notification.body, isNull);
      },
    );

    test('costs the preview, not the notification, when it throws', () async {
      final presenter = _RecordingPresenter();
      final router = PushMessageRouter(
        presenter: presenter,
        activeRoomId: null,
        describe: (_) async => throw StateError('network gone'),
      );

      expect(await router.handle(push, messageTitle: 'New message'), isTrue);
      expect(presenter.shown.single.title, 'New message');
    });

    test('is never looked up when nothing will be shown', () async {
      var lookups = 0;
      Future<NotificationText?> count(PushNotification _) async {
        lookups++;
        return null;
      }

      // The room on screen, a ringing call, and a counts-only push.
      await PushMessageRouter(
        presenter: _RecordingPresenter(),
        activeRoomId: '!other:test',
        describe: count,
      ).handle(push, messageTitle: 'New message');
      await PushMessageRouter(
        presenter: _RecordingPresenter(),
        activeRoomId: null,
        ringingRoomId: '!other:test',
        describe: count,
      ).handle(push, messageTitle: 'New message');
      await PushMessageRouter(
        presenter: _RecordingPresenter(),
        activeRoomId: null,
        describe: count,
      ).handle({'room_id': '!other:test', 'unread': 0}, messageTitle: 'x');

      expect(lookups, 0);
    });
  });
}
