import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Turns a Matrix `org.matrix.custom.html` body into spans.
///
/// The markup comes from other users, so this is an allow-list: anything not
/// named here is dropped and only its text survives. That is the whole
/// security model. A deny-list would have to anticipate every tag worth
/// blocking, and the one it misses is the one that matters.
///
/// The supported set is deliberately the inline formatting people actually
/// send from Element and this app's own composer. Tables, images, headings and
/// colours degrade to plain text rather than being half-rendered.
abstract final class MessageMarkup {
  /// Tags that change how their contents look.
  static const _inlineTags = {
    'b', 'strong', // bold
    'i', 'em', // italic
    'del', 's', 'strike', // strikethrough
    'u', // underline
    'code',
    'a',
    'span',
    'font',
    'p', 'br', 'div', // structural, but text has to flow through them
    'blockquote', 'pre',
    'ul', 'ol', 'li',
    'mx-reply',
  };

  /// Whether [html] contains anything this renderer would draw differently
  /// from its plaintext. Saves building spans for markup that adds nothing.
  static bool hasVisibleFormatting(String html) {
    final body = html_parser.parse(html).body;
    if (body == null) return false;
    return _hasFormatting(body);
  }

  static bool _hasFormatting(dom.Node node) {
    for (final child in node.nodes) {
      if (child is dom.Element) {
        const plain = {'p', 'div', 'span', 'body', 'html'};
        if (!plain.contains(child.localName)) return true;
        if (_hasFormatting(child)) return true;
      }
    }
    return false;
  }

  /// Builds the span tree for [html].
  ///
  /// [onOpenLink] receives the href of a tapped link. Links are not opened
  /// here: a message can carry any URL, so the decision to follow one belongs
  /// to the caller rather than to a text renderer.
  static InlineSpan toSpan(
    String html, {
    required TextStyle baseStyle,
    required ColorScheme colors,
    void Function(String url)? onOpenLink,
    List<TapGestureRecognizer>? recognizers,
  }) {
    final document = html_parser.parse(html);
    final body = document.body;
    if (body == null) return TextSpan(text: '', style: baseStyle);
    final children = _childSpans(
      body,
      baseStyle,
      colors,
      onOpenLink,
      recognizers,
    );
    return TextSpan(style: baseStyle, children: children);
  }

  static const _blockTags = {'p', 'div', 'blockquote', 'pre', 'ul', 'ol', 'li'};

  static List<InlineSpan> _childSpans(
    dom.Node parent,
    TextStyle style,
    ColorScheme colors,
    void Function(String url)? onOpenLink,
    List<TapGestureRecognizer>? recognizers,
  ) {
    final spans = <InlineSpan>[];
    var previousWasBlock = false;
    var wroteSomething = false;
    for (final node in parent.nodes) {
      // Markdown converters pretty-print, so the gaps between block tags
      // arrive as whitespace text nodes. A single space between two inline
      // runs is meaningful and has to survive; a newline's worth of indent is
      // not.
      if (node is dom.Text &&
          node.text.trim().isEmpty &&
          node.text.contains('\n')) {
        continue;
      }
      final children = _spansFor(node, style, colors, onOpenLink, recognizers);
      if (children.isEmpty) continue;

      final isBlock =
          node is dom.Element && _blockTags.contains(node.localName);
      // Separators go between blocks rather than after them, so a message
      // does not end on a blank line.
      if (wroteSomething && (isBlock || previousWasBlock)) {
        spans.add(TextSpan(text: '\n', style: style));
      }
      spans.addAll(children);
      previousWasBlock = isBlock;
      wroteSomething = true;
    }
    return spans;
  }

  static List<InlineSpan> _spansFor(
    dom.Node node,
    TextStyle style,
    ColorScheme colors,
    void Function(String url)? onOpenLink,
    List<TapGestureRecognizer>? recognizers,
  ) {
    if (node is dom.Text) {
      final text = node.text;
      if (text.isEmpty) return const [];
      return [TextSpan(text: text, style: style)];
    }
    if (node is! dom.Element) return const [];

    final tag = node.localName?.toLowerCase();
    // The reply fallback duplicates the quoted message, which this app already
    // shows as a structured preview above the text.
    if (tag == 'mx-reply') return const [];
    if (tag == 'br') return [TextSpan(text: '\n', style: style)];

    if (tag == null || !_inlineTags.contains(tag)) {
      // Unknown tag: keep the words, drop the markup.
      return _childSpans(node, style, colors, onOpenLink, recognizers);
    }

    final childStyle = _styleFor(tag, style, colors);

    if (tag == 'a') {
      final href = node.attributes['href'];
      if (href != null && _isSafeUrl(href)) {
        final recognizer = onOpenLink == null
            ? null
            : (TapGestureRecognizer()..onTap = () => onOpenLink(href));
        if (recognizer != null) recognizers?.add(recognizer);
        return [
          TextSpan(
            children: _childSpans(
              node,
              childStyle,
              colors,
              onOpenLink,
              recognizers,
            ),
            style: childStyle,
            recognizer: recognizer,
          ),
        ];
      }
      // A link this client will not follow is still worth reading.
      return _childSpans(node, style, colors, onOpenLink, recognizers);
    }

    final children = _childSpans(
      node,
      childStyle,
      colors,
      onOpenLink,
      recognizers,
    );
    if (children.isEmpty) return const [];
    return [
      if (tag == 'li') TextSpan(text: '\u2022 ', style: childStyle),
      TextSpan(children: children, style: childStyle),
    ];
  }

  static TextStyle _styleFor(String tag, TextStyle style, ColorScheme colors) {
    return switch (tag) {
      'b' || 'strong' => style.copyWith(fontWeight: FontWeight.bold),
      'i' || 'em' => style.copyWith(fontStyle: FontStyle.italic),
      'del' ||
      's' ||
      'strike' => style.copyWith(decoration: TextDecoration.lineThrough),
      'u' => style.copyWith(decoration: TextDecoration.underline),
      'code' || 'pre' => style.copyWith(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Menlo', 'Courier New'],
        // Slightly smaller so a monospace run does not tower over the text
        // around it.
        fontSize: (style.fontSize ?? 14) * 0.92,
      ),
      'a' => style.copyWith(
        color: colors.primary,
        decoration: TextDecoration.underline,
        decorationColor: colors.primary,
      ),
      'blockquote' => style.copyWith(color: style.color?.withValues(alpha: .8)),
      _ => style,
    };
  }

  /// Only schemes that cannot execute anything on tap.
  ///
  /// `javascript:` and `data:` are the reason this check exists at all.
  static bool _isSafeUrl(String href) {
    final uri = Uri.tryParse(href.trim());
    if (uri == null || !uri.hasScheme) return false;
    return const {
      'http',
      'https',
      'mailto',
      'tel',
      'matrix',
    }.contains(uri.scheme.toLowerCase());
  }
}

/// Renders a message body, using the sender's markup when there is any.
class FormattedMessageText extends StatefulWidget {
  const FormattedMessageText({
    required this.body,
    required this.style,
    this.formattedBody,
    this.onOpenLink,
    super.key,
  });

  final String body;
  final String? formattedBody;
  final TextStyle style;
  final void Function(String url)? onOpenLink;

  @override
  State<FormattedMessageText> createState() => _FormattedMessageTextState();
}

class _FormattedMessageTextState extends State<FormattedMessageText> {
  /// Held so every recognizer built for a span tree can be disposed with it.
  /// A TapGestureRecognizer that outlives its span leaks.
  final _recognizers = <TapGestureRecognizer>[];

  void _clearRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final html = widget.formattedBody;
    if (html == null || !MessageMarkup.hasVisibleFormatting(html)) {
      return Text(widget.body, style: widget.style);
    }

    _clearRecognizers();
    final span = MessageMarkup.toSpan(
      html,
      baseStyle: widget.style,
      colors: Theme.of(context).colorScheme,
      onOpenLink: widget.onOpenLink,
      recognizers: _recognizers,
    );
    return Text.rich(span);
  }
}
