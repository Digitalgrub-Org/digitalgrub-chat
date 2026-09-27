import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps Android's microphone alive while the app is not on screen.
///
/// Android does not refuse a backgrounded app's microphone -- it hands it
/// silence. So a call survived switching to another app in one direction only:
/// you could hear everyone and nobody could hear you, with no error on either
/// side and no way for either party to tell whose phone was at fault.
///
/// The fix is a foreground service of type `microphone`, which is what this
/// starts. It is Android-only: iOS keeps a call's audio session alive through
/// its own background mode, and the web has no such rule.
class CallForegroundService {
  const CallForegroundService();

  static const _channel = MethodChannel('in.digitalgrub.chat/launch');

  bool get _applies =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Starts the service. Safe to call more than once for one call.
  ///
  /// Never throws: a call that connects but cannot raise a notification is
  /// still a call, and it is better to run it with the old background
  /// behaviour than to fail the join outright.
  Future<void> start() async {
    if (!_applies) return;
    try {
      await _channel.invokeMethod<bool>('startCallService');
    } catch (error) {
      debugPrint('call foreground service did not start: $error');
    }
  }

  /// Stops the service, taking the notification down with it.
  ///
  /// Must run on every path out of a call, including failed ones -- an
  /// "in a call" notification outliving its call is worse than never showing
  /// one, because the only way out of it is to force-stop the app.
  Future<void> stop() async {
    if (!_applies) return;
    try {
      await _channel.invokeMethod<bool>('stopCallService');
    } catch (error) {
      debugPrint('call foreground service did not stop: $error');
    }
  }
}
