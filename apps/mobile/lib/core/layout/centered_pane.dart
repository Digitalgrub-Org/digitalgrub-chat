import 'package:flutter/widgets.dart';

/// Keeps a single-column screen at a readable width instead of letting it
/// stretch the full width of a desktop window.
///
/// Screens written for a phone assume the viewport is the column: a form field
/// or a paragraph simply fills it. At 1400px that same field becomes a line
/// the eye cannot track, and a full-width primary button reads as a banner. So
/// the column stays roughly phone-width and centres in whatever space it gets.
class CenteredPane extends StatelessWidget {
  const CenteredPane({required this.child, this.maxWidth = 480, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
