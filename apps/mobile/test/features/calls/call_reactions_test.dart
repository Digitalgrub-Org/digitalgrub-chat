import 'dart:async';

import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:dg_chat/features/calls/presentation/call_reactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a picked reaction is handed on', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CallReactionBar(onPick: picked.add)),
      ),
    );

    await tester.tap(find.text('👋'));
    expect(picked, ['👋']);
  });

  testWidgets('the bar offers exactly the allowed set', (tester) async {
    // The allowlist is what keeps the call's data channel from carrying
    // arbitrary content onto everyone's screen; the picker must not offer
    // anything the receiving side would refuse.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CallReactionBar(onPick: (_) {})),
      ),
    );

    for (final emoji in allowedCallReactions) {
      expect(find.text(emoji), findsOneWidget);
    }
  });

  testWidgets('a reaction floats up, names its sender, and fades away', (
    tester,
  ) async {
    final reactions = StreamController<CallReaction>.broadcast();
    addTearDown(reactions.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CallReactionsOverlay(reactions: reactions.stream)),
      ),
    );

    reactions.add(
      const CallReaction(emoji: '👏', senderName: 'Asha', isLocal: false),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('👏'), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);

    // Gone after its lifetime: a wave is a moment, not furniture.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('👏'), findsNothing);
  });
}
