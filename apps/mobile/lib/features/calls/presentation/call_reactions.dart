import 'dart:async';
import 'dart:math';

import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:dg_chat/features/calls/domain/call_repository.dart';
import 'package:flutter/material.dart';

/// Reactions floating up over the call, the way every meeting app does it.
///
/// Purely decorative and deliberately brief: each one drifts upward and is
/// gone in a couple of seconds, so a wave stays a wave instead of becoming
/// clutter over somebody's face.
class CallReactionsOverlay extends StatefulWidget {
  const CallReactionsOverlay({required this.reactions, super.key});

  final Stream<CallReaction> reactions;

  @override
  State<CallReactionsOverlay> createState() => _CallReactionsOverlayState();
}

class _FloatingReaction {
  _FloatingReaction(this.reaction, this.horizontal);

  final CallReaction reaction;

  /// Where across the width it rises, 0..1. Random so a burst of applause
  /// spreads out instead of stacking into one column.
  final double horizontal;
}

class _CallReactionsOverlayState extends State<CallReactionsOverlay> {
  static const _lifetime = Duration(milliseconds: 2400);

  final _random = Random();
  final _active = <_FloatingReaction>[];
  StreamSubscription<CallReaction>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.reactions.listen((reaction) {
      final floating = _FloatingReaction(
        reaction,
        0.1 + _random.nextDouble() * 0.8,
      );
      setState(() => _active.add(floating));
      Timer(_lifetime, () {
        if (mounted) setState(() => _active.remove(floating));
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watches, never intercepts: a tap through a drifting emoji still lands
    // on the call underneath.
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            for (final floating in _active)
              _RisingEmoji(
                key: ObjectKey(floating),
                reaction: floating.reaction,
                left: floating.horizontal * (constraints.maxWidth - 56),
                height: constraints.maxHeight,
                lifetime: _lifetime,
              ),
          ],
        ),
      ),
    );
  }
}

class _RisingEmoji extends StatelessWidget {
  const _RisingEmoji({
    required this.reaction,
    required this.left,
    required this.height,
    required this.lifetime,
    super.key,
  });

  final CallReaction reaction;
  final double left;
  final double height;
  final Duration lifetime;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: lifetime,
      curve: Curves.easeOut,
      builder: (context, t, child) => Positioned(
        left: left,
        bottom: 24 + t * (height * 0.55),
        child: Opacity(
          // Fully there for most of the ride, gone by the top.
          opacity: t < 0.7 ? 1 : (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0),
          child: child,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(reaction.emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(height: 2),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(
                reaction.senderName,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The row of reactions to pick from, shown while the react control is open.
class CallReactionBar extends StatelessWidget {
  const CallReactionBar({required this.onPick, super.key});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in allowedCallReactions)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onPick(emoji),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(emoji, style: const TextStyle(fontSize: 26)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
