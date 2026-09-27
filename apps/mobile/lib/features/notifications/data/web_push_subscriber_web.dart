import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:dg_chat/features/notifications/domain/push_repository.dart';
import 'package:web/web.dart' as web;

/// Web Push through the browser's PushManager.
///
/// The service worker is registered at a scope of its own (`/push/`) rather
/// than the site root: Flutter's bootstrap registers its own worker at the
/// root on every load, and two workers contending for one scope replace each
/// other in turns. A push subscription belongs to a registration, not a
/// scope, so a narrow scope costs nothing -- the worker never needs to see a
/// page request, only push events.
///
/// Every step is guarded. A browser without push, a refused subscription, a
/// key that will not decode: each yields null and the tab carries on with
/// its in-tab notifications, which need none of this.
class _BrowserWebPush implements WebPushSubscriber {
  const _BrowserWebPush();

  bool get _supported =>
      globalContext.has('Notification') &&
      globalContext.has('PushManager') &&
      web.window.navigator.has('serviceWorker');

  @override
  Future<WebPushSubscription?> subscribe(String vapidPublicKey) async {
    if (!_supported || vapidPublicKey.isEmpty) return null;
    // Subscribing without permission throws; permission is the prompt's job.
    if (web.Notification.permission != 'granted') return null;
    try {
      final container = web.window.navigator.serviceWorker;
      final registration = await container
          .register('sw.js'.toJS, web.RegistrationOptions(scope: '/push/'))
          .toDart;
      // NOT `serviceWorker.ready`: that resolves to whichever worker controls
      // the page -- Flutter's, at the root -- and a subscription made on
      // that registration belongs to a worker with no push handler. The
      // registration handed back above is ours; wait for its worker to
      // reach active, which a fresh install takes a moment to do.
      for (
        var attempt = 0;
        attempt < 40 && registration.active == null;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (registration.active == null) return null;
      final manager = registration.pushManager;
      var subscription = await manager.getSubscription().toDart;
      subscription ??= await manager
          .subscribe(
            web.PushSubscriptionOptionsInit(
              userVisibleOnly: true,
              applicationServerKey: _decodeKey(vapidPublicKey).toJS,
            ),
          )
          .toDart;
      final p256dh = subscription.getKey('p256dh');
      final auth = subscription.getKey('auth');
      if (p256dh == null || auth == null) return null;
      return WebPushSubscription(
        endpoint: subscription.endpoint,
        p256dh: _encode(p256dh),
        auth: _encode(auth),
      );
    } catch (_) {
      return null;
    }
  }

  static Uint8List _decodeKey(String base64url) {
    final padded = base64url.padRight(
      base64url.length + (4 - base64url.length % 4) % 4,
      '=',
    );
    return base64Url.decode(padded);
  }

  /// Base64url without padding, the form the gateway and the spec expect.
  static String _encode(JSArrayBuffer buffer) =>
      base64Url.encode(buffer.toDart.asUint8List()).replaceAll('=', '');
}

WebPushSubscriber createWebPushSubscriber() => const _BrowserWebPush();
