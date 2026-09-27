import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports where the app believes a click landed.
///
/// Written for one bug: the chat list on the web going unresponsive, where
/// three plausible explanations — the click never arriving, arriving at the
/// wrong coordinates, or arriving and being swallowed — all look identical
/// from the outside. Each leaves a different trace here.
///
/// Off unless the page is opened with `?diag=1`, so it costs a normal user
/// nothing. Open the console, click the thing that will not respond, and read.
class PointerDiagnostics extends StatelessWidget {
  const PointerDiagnostics({required this.child, super.key});

  final Widget child;

  /// Enabled by a query parameter rather than a build flag, so a person
  /// hitting this in the wild can turn it on where it is happening instead of
  /// waiting for a special build.
  static bool get enabled => kIsWeb && Uri.base.queryParameters['diag'] == '1';

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Listener(
      // Translucent: this watches, it does not intercept. If it swallowed the
      // event it would be causing the bug it is meant to find.
      behavior: HitTestBehavior.translucent,
      onPointerDown: _report,
      child: child,
    );
  }

  void _report(PointerDownEvent event) {
    // Reaching here at all means the browser delivered the event and the
    // engine routed it. Silence on click is the finding, not the absence of
    // one.
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;

    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, event.position, event.viewId);
    // Nearest target first. If the list was clicked and this names the detail
    // pane, the app's idea of the layout has drifted from what is on screen.
    // If it names the tile and nothing opens, the tap is being lost after the
    // hit test, not before.
    // Type names are minified in a release build, and a release build is
    // where this bug lives, so the trace is built from things minification
    // cannot rename: what kind of thing it is, how big it is, and where the
    // app believes it sits. A box whose position disagrees with what is on
    // screen is the whole answer.
    // Everything, in order, including the entries that are not boxes. The
    // first trace stopped at the scroll view and said nothing about what lay
    // inside it -- but slivers are not RenderBoxes, so "nothing inside" and
    // "filtered out" looked identical. They no longer do.
    final path = result.path.map(_describe).join(' < ');

    debugPrint(
      'dg-diag pointer at ${event.position.dx.toStringAsFixed(1)},'
      '${event.position.dy.toStringAsFixed(1)}'
      ' | kind ${event.kind.name}'
      ' | view ${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}'
      ' | dpr ${view.devicePixelRatio}'
      ' | lifecycle ${WidgetsBinding.instance.lifecycleState?.name}'
      ' | depth ${result.path.length}'
      ' | hit $path',
    );
  }

  /// A label that survives minification.
  ///
  /// The `is` checks compile to real type tests, so the readable part is the
  /// string chosen here rather than a name the compiler is free to mangle.
  static String _describe(HitTestEntry entry) {
    final target = entry.target;
    final kind = switch (target) {
      RenderPointerListener() => 'listener',
      RenderSemanticsGestureHandler() => 'gesture',
      RenderParagraph() => 'text',
      RenderImage() => 'image',
      RenderView() => 'view',
      RenderSliver() => 'sliver',
      RenderBox() => 'box',
      _ => 'other',
    };
    if (target is! RenderBox || !target.hasSize) return kind;
    final size = target.size;
    final origin = target.localToGlobal(Offset.zero);
    return '$kind ${size.width.toStringAsFixed(0)}x'
        '${size.height.toStringAsFixed(0)}'
        '@${origin.dx.toStringAsFixed(0)},${origin.dy.toStringAsFixed(0)}';
  }
}
