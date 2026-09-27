import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android picture-in-picture for a running call.
///
/// Going home mid-call used to leave nothing on screen but a notification.
/// With this, the call shrinks to a floating window the way a meeting app's
/// does: the activity is told when the call screen is up, so that leaving
/// the app enters picture-in-picture, and it tells the screen when that
/// happens so the screen can draw only the video.
///
/// Android only. iOS has no equivalent for custom video without a great
/// deal more native work; there the system's own in-call indicator is the
/// way back.
class NativePip {
  static const _channel = MethodChannel('in.digitalgrub.chat/launch');

  static bool get _applies =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether leaving the app right now should shrink it to a window.
  ///
  /// True only while the call screen is the thing on screen. Anything else
  /// in a floating window -- a chat, the settings -- is not what anyone
  /// wanted to keep in the corner.
  static Future<void> setEligible(bool eligible) async {
    if (!_applies) return;
    try {
      await _channel.invokeMethod<bool>('setPipEligible', eligible);
    } catch (_) {
      // Older Android, or a build without the activity hook: no window,
      // and the notification still leads back.
    }
  }

  /// Hears the activity enter and leave picture-in-picture.
  static void listen(void Function(bool inPip) onChanged) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') onChanged(call.arguments == true);
      return null;
    });
  }

  static void stopListening() => _channel.setMethodCallHandler(null);
}
