import 'package:dg_chat/features/notifications/domain/push_repository.dart';

/// Phones push through FCM and APNs; there is no browser here to subscribe.
class _NoWebPush implements WebPushSubscriber {
  const _NoWebPush();

  @override
  Future<WebPushSubscription?> subscribe(String vapidPublicKey) async => null;
}

WebPushSubscriber createWebPushSubscriber() => const _NoWebPush();
