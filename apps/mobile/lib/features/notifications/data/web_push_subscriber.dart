import 'package:dg_chat/features/notifications/domain/push_repository.dart';

import 'web_push_subscriber_stub.dart'
    if (dart.library.js_interop) 'web_push_subscriber_web.dart'
    as impl;

/// The browser implementation on web, and one that never subscribes
/// everywhere else.
WebPushSubscriber createWebPushSubscriber() => impl.createWebPushSubscriber();
