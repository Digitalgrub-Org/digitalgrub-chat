import 'dart:math';

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// The system incoming-call surface, raised from a push.
///
/// This runs in the background isolate, where none of the app exists — no
/// providers, no navigator, no signed-in client. Everything it can say has to
/// come from the push payload, which carries a room id and nothing readable,
/// so the caller line is generic. The room id rides along in [CallKitParams]
/// extras; whoever handles the accept — a cold-started app included — reads
/// it back from there.
///
/// The banner's own in-app rings deliberately do NOT carry extras: that is
/// how the two origins stay distinguishable to the accept handlers, so the
/// banner keeps routing its rings and this path keeps routing its own.
Future<void> showNativeIncomingCall({
  required String roomId,
  required String callerLabel,
}) async {
  final random = Random.secure();
  String hex(int n) =>
      List.generate(n, (_) => random.nextInt(16).toRadixString(16)).join();
  final id =
      '${hex(8)}-${hex(4)}-4${hex(3)}-'
      '${(8 + random.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';

  await FlutterCallkitIncoming.showCallkitIncoming(
    CallKitParams(
      id: id,
      nameCaller: callerLabel,
      appName: 'Digitalgrub Chat',
      type: 0,
      // Rings are short-lived by spec; the surface takes itself down when
      // the caller would have given up.
      duration: 30000,
      extra: {'roomId': roomId},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        actionColor: '#FFBE00',
      ),
      ios: const IOSParams(
        supportsVideo: true,
        // voiceChat, not default: the mode decides the route iOS picks when
        // the session activates, and `default` lands on the loudspeaker.
        // voiceChat routes to the earpiece and turns on the echo cancellation
        // a call needs.
        audioSessionMode: 'voiceChat',
        ringtonePath: 'system_ringtone_default',
      ),
    ),
  );
}
