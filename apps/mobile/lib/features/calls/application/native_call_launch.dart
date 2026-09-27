import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

/// Routes answers to rings the app itself never showed.
///
/// A ring raised by the background push isolate outlives that isolate: the
/// person answers, the system launches the app, and by then nothing is
/// subscribed to hear the answer. This asks the plugin what is already
/// accepted at startup, and stays subscribed for answers that land while the
/// app is up but the in-app banner never rang (it only subscribes once it
/// has shown a ring of its own).
///
/// Only calls carrying a `roomId` extra are handled here — that extra is the
/// signature of the push path. The banner's rings carry none and stay the
/// banner's business.
class NativeCallLaunch {
  NativeCallLaunch(this._onAccepted);

  final void Function(String roomId) _onAccepted;
  StreamSubscription<CallEvent?>? _events;

  static const _launchChannel = MethodChannel('in.digitalgrub.chat/launch');

  Future<void> start() async {
    if (kIsWeb) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _startIos();
        return;
      }
      // Answered before the app was running: the launch intent carries the
      // accept, read by our MainActivity. The plugin's own cold-start API
      // (activeCalls) hangs once the push isolate's engine has run, and its
      // accept event is not replayed to late listeners — the intent is the
      // one signal that cannot race anything. Decline never launches the
      // app, and a manual open arrives with a plain MAIN intent, so a
      // non-null answer here always means the green button.
      //
      // This call doubles as the platform probe: where no native side
      // exists — a test, or a platform without the channel — it throws
      // before the event stream below would try to activate and leak an
      // asynchronous MissingPluginException into the zone.
      final accepted = await _launchChannel.invokeMethod<String>(
        'takeAcceptedCallRoom',
      );
      if (accepted != null && accepted.isNotEmpty) {
        unawaited(FlutterCallkitIncoming.endAllCalls().catchError((_) {}));
        _onAccepted(accepted);
      }

      // Answers that land while the app is up but the in-app banner never
      // rang (it only subscribes once it has shown a ring of its own).
      _events = FlutterCallkitIncoming.onEvent.listen((event) {
        if (event == null) return;
        if (event.event != Event.actionCallAccept) return;
        final body = event.body;
        if (body is! Map) return;
        final roomId = _pushRoomId(body['extra']);
        if (roomId == null) return;
        final id = body['id'];
        if (id is String) {
          unawaited(FlutterCallkitIncoming.endCall(id).catchError((_) {}));
        }
        _onAccepted(roomId);
      }, onError: (Object _) {});
    } catch (_) {
      // No plugin here — a test, or a platform without it. Ringing is an
      // enhancement; its absence must not take the shell down.
    }
  }

  /// The iOS half. CallKit answers reach Flutter through the plugin's event
  /// stream, and the cold-start case is covered by activeCalls — which works
  /// on iOS; it is the Android implementation that hangs after the push
  /// isolate has run, which is why the platforms part ways here.
  Future<void> _startIos() async {
    _events = FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;
      if (event.event != Event.actionCallAccept) return;
      final body = event.body;
      if (body is! Map) return;
      final roomId = _pushRoomId(body['extra']);
      if (roomId == null) return;
      final id = body['id'];
      if (id is String) {
        unawaited(FlutterCallkitIncoming.endCall(id).catchError((_) {}));
      }
      _onAccepted(roomId);
    }, onError: (Object _) {});

    try {
      final active = await FlutterCallkitIncoming.activeCalls().timeout(
        const Duration(seconds: 3),
      );
      if (active is! List) return;
      for (final call in active) {
        if (call is! Map) continue;
        if (call['isAccepted'] != true) continue;
        final roomId = _pushRoomId(call['extra']);
        if (roomId == null) continue;
        final id = call['id'];
        if (id is String) {
          unawaited(FlutterCallkitIncoming.endCall(id).catchError((_) {}));
        }
        _onAccepted(roomId);
      }
    } on TimeoutException {
      // Answers still arrive through the stream above.
    }
  }

  static String? _pushRoomId(Object? extra) {
    if (extra is! Map) return null;
    final roomId = extra['roomId'];
    return roomId is String && roomId.isNotEmpty ? roomId : null;
  }

  void dispose() {
    unawaited(_events?.cancel());
    _events = null;
  }
}
