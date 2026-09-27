import 'package:dg_chat/features/calls/presentation/call_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('callControlIconColor', () {
    test('an available control is legible, not ghosted', () {
      // The bug this fixes: screen sharing sat at white38 on a near-black
      // screen for the whole call, because "not sharing" is its resting state
      // and the old rule painted everything-not-active the same as off. It
      // read as disabled every moment it was usable.
      final idle = callControlIconColor(
        active: false,
        enabled: true,
        hasBackground: false,
      );
      expect(idle, Colors.white70);
      expect(idle.a, greaterThan(Colors.white38.a));
    });

    test('an active control is brightest', () {
      expect(
        callControlIconColor(active: true, enabled: true, hasBackground: false),
        Colors.white,
      );
    });

    test('a disabled control is dimmer than an available one', () {
      // Someone else is already sharing: the button must look unavailable,
      // and must be distinguishable from merely-not-active.
      final disabled = callControlIconColor(
        active: false,
        enabled: false,
        hasBackground: false,
      );
      final available = callControlIconColor(
        active: false,
        enabled: true,
        hasBackground: false,
      );
      expect(disabled, Colors.white24);
      expect(disabled.a, lessThan(available.a));
    });

    test('hang up stays white on its own red', () {
      // It carries its own background, so brightness is not how it signals
      // state and it must never dim.
      expect(
        callControlIconColor(active: true, enabled: true, hasBackground: true),
        Colors.white,
      );
      expect(
        callControlIconColor(active: false, enabled: true, hasBackground: true),
        Colors.white,
      );
    });
  });
}
