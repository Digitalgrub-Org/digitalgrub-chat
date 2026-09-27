import 'package:dg_chat/features/notifications/data/web_notification_presenter.dart';
import 'package:dg_chat/features/notifications/data/web_notifications.dart';
import 'package:dg_chat/features/notifications/domain/push_notification.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWebNotifications implements WebNotifications {
  _FakeWebNotifications(this._permission);

  WebNotificationPermission _permission;
  WebNotificationPermission? grantOnRequest;

  final List<({String tag, String title, String? body})> shown = [];
  final List<String> closed = [];
  void Function()? lastOnClick;
  int requestCount = 0;

  @override
  WebNotificationPermission get permission => _permission;

  @override
  Future<WebNotificationPermission> requestPermission() async {
    requestCount++;
    if (grantOnRequest != null) _permission = grantOnRequest!;
    return _permission;
  }

  @override
  void show({
    required String tag,
    required String title,
    String? body,
    void Function()? onClick,
  }) {
    shown.add((tag: tag, title: title, body: body));
    lastOnClick = onClick;
  }

  @override
  void close(String tag) => closed.add(tag);
}

void main() {
  test('shows the room name and the message text', () async {
    final browser = _FakeWebNotifications(WebNotificationPermission.granted);
    final presenter = WebNotificationPresenter(notifications: browser);

    await presenter.show(
      const PushNotification(
        roomId: '!room:test',
        eventId: r'$event',
        body: 'Bob: are you around?',
      ),
      title: 'Design',
    );

    expect(browser.shown.single.title, 'Design');
    // Nothing passed through a gateway to get here, so the text can be shown.
    expect(browser.shown.single.body, 'Bob: are you around?');
    // Tagging by room is what makes a second message replace the first.
    expect(browser.shown.single.tag, '!room:test');
  });

  test('clicking one opens its room', () async {
    final browser = _FakeWebNotifications(WebNotificationPermission.granted);
    final opened = <String>[];
    final presenter = WebNotificationPresenter(
      notifications: browser,
      onRoomSelected: opened.add,
    );

    await presenter.show(
      const PushNotification(roomId: '!room:test', eventId: r'$event'),
      title: 'Design',
    );
    browser.lastOnClick!();

    expect(opened, ['!room:test']);
  });

  test('opening a room takes down its notification', () async {
    final browser = _FakeWebNotifications(WebNotificationPermission.granted);
    final presenter = WebNotificationPresenter(notifications: browser);

    await presenter.dismissForRoom('!room:test');

    expect(browser.closed, ['!room:test']);
  });

  test('only an unasked browser is worth prompting', () {
    for (final (permission, expected) in [
      (WebNotificationPermission.prompt, true),
      (WebNotificationPermission.granted, false),
      // Asking again does nothing: only the browser's own settings can undo
      // a refusal, so a banner offering to try would be a lie.
      (WebNotificationPermission.denied, false),
      (WebNotificationPermission.unsupported, false),
    ]) {
      final presenter = WebNotificationPresenter(
        notifications: _FakeWebNotifications(permission),
      );
      expect(presenter.canRequestPermission, expected, reason: permission.name);
    }
  });

  test('reports whether the request was granted', () async {
    final browser = _FakeWebNotifications(WebNotificationPermission.prompt)
      ..grantOnRequest = WebNotificationPermission.granted;
    final presenter = WebNotificationPresenter(notifications: browser);

    expect(await presenter.requestPermission(), isTrue);
    expect(presenter.isPermitted, isTrue);

    final refusing = _FakeWebNotifications(WebNotificationPermission.prompt)
      ..grantOnRequest = WebNotificationPermission.denied;
    expect(
      await WebNotificationPresenter(
        notifications: refusing,
      ).requestPermission(),
      isFalse,
    );
  });

  test('mobile gets a presenter that quietly does nothing', () async {
    // The conditional import resolves to the stub off the web, and every call
    // has to be safe there: this test only runs on the Dart VM.
    final notifications = createWebNotifications();

    expect(notifications.permission, WebNotificationPermission.unsupported);
    expect(
      await notifications.requestPermission(),
      WebNotificationPermission.unsupported,
    );
    notifications
      ..show(tag: '!room:test', title: 'Design')
      ..close('!room:test');
  });
}
