import 'package:dg_chat/features/calls/data/livekit_call_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('never left: nothing to recover', () {
    expect(needsAudioRecovery(null), isFalse);
  });

  test('a glance at another app is not an interruption', () {
    // Recovery costs a beat of silence; a two-second switch is not worth it.
    expect(needsAudioRecovery(const Duration(seconds: 2)), isFalse);
  });

  test('a phone call is', () {
    expect(needsAudioRecovery(const Duration(seconds: 3)), isTrue);
    expect(needsAudioRecovery(const Duration(minutes: 4)), isTrue);
  });
}
