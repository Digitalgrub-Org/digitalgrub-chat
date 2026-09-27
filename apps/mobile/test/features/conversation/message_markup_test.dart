import 'package:dg_chat/features/conversation/presentation/message_markup.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = TextStyle(fontSize: 14, color: Color(0xFF000000));
const _colors = ColorScheme.light();

/// Walks the span tree so assertions can talk about rendered runs rather than
/// the shape of the tree, which is an implementation detail.
List<({String text, TextStyle style})> _runs(InlineSpan span) {
  final runs = <({String text, TextStyle style})>[];
  void visit(InlineSpan node, TextStyle inherited) {
    if (node is! TextSpan) return;
    final style = node.style == null ? inherited : inherited.merge(node.style);
    final text = node.text;
    if (text != null && text.isNotEmpty) {
      runs.add((text: text, style: style));
    }
    for (final child in node.children ?? const <InlineSpan>[]) {
      visit(child, style);
    }
  }

  visit(span, _base);
  return runs;
}

InlineSpan _span(String html, {void Function(String)? onOpenLink}) =>
    MessageMarkup.toSpan(
      html,
      baseStyle: _base,
      colors: _colors,
      onOpenLink: onOpenLink,
    );

String _plainText(String html) => _runs(_span(html)).map((r) => r.text).join();

void main() {
  group('inline styles', () {
    test('renders bold, italic, strikethrough and code', () {
      final runs = _runs(
        _span('<strong>b</strong><em>i</em><del>s</del><code>c</code>'),
      );

      expect(runs.map((r) => r.text).join(), 'bisc');
      expect(runs[0].style.fontWeight, FontWeight.bold);
      expect(runs[1].style.fontStyle, FontStyle.italic);
      expect(runs[2].style.decoration, TextDecoration.lineThrough);
      expect(runs[3].style.fontFamily, 'monospace');
    });

    test('accepts the legacy tag spellings other clients send', () {
      final runs = _runs(_span('<b>b</b><i>i</i><s>s</s>'));
      expect(runs[0].style.fontWeight, FontWeight.bold);
      expect(runs[1].style.fontStyle, FontStyle.italic);
      expect(runs[2].style.decoration, TextDecoration.lineThrough);
    });

    test('nests styles', () {
      final runs = _runs(_span('<strong>bold <em>and italic</em></strong>'));
      expect(runs.last.style.fontWeight, FontWeight.bold);
      expect(runs.last.style.fontStyle, FontStyle.italic);
    });
  });

  group('untrusted markup', () {
    test('drops a script tag but keeps surrounding text', () {
      // The parser hands over whatever the sender wrote. Anything not on the
      // allow-list has to lose its markup, not its words.
      expect(_plainText('a<script>alert(1)</script>b'), contains('a'));
      expect(_plainText('a<script>alert(1)</script>b'), contains('b'));
    });

    test('renders an unknown tag as its text', () {
      expect(_plainText('<marquee>hello</marquee>'), 'hello');
      expect(_plainText('<h1>Title</h1>'), 'Title');
    });

    test('refuses to make a javascript: link tappable', () {
      var opened = 0;
      final runs = _runs(
        _span(
          '<a href="javascript:alert(1)">tap</a>',
          onOpenLink: (_) => opened++,
        ),
      );

      // The words survive, the link does not.
      expect(runs.map((r) => r.text).join(), 'tap');
      expect(runs.every((r) => r.style.color != _colors.primary), isTrue);
      expect(opened, 0);
    });

    test('refuses a data: url', () {
      final runs = _runs(
        _span('<a href="data:text/html,<h1>x">tap</a>', onOpenLink: (_) {}),
      );
      expect(runs.every((r) => r.style.color != _colors.primary), isTrue);
    });

    test('makes an https link tappable', () {
      final recognizers = <TapGestureRecognizer>[];
      addTearDown(() {
        for (final r in recognizers) {
          r.dispose();
        }
      });
      var opened = '';
      MessageMarkup.toSpan(
        '<a href="https://example.com">tap</a>',
        baseStyle: _base,
        colors: _colors,
        onOpenLink: (url) => opened = url,
        recognizers: recognizers,
      );

      expect(recognizers, hasLength(1));
      recognizers.single.onTap!();
      expect(opened, 'https://example.com');
    });
  });

  group('layout', () {
    test('separates paragraphs without a trailing blank line', () {
      final text = _plainText('<p>one</p><p>two</p>');
      expect(text, 'one\ntwo');
      expect(text.endsWith('\n'), isFalse);
    });

    test('keeps a meaningful space between inline runs', () {
      // A single space between two elements is content; the newline-and-indent
      // a markdown converter emits between blocks is not.
      expect(_plainText('<em>a</em> <em>b</em>'), 'a b');
      expect(_plainText('<p>a</p>\n<p>b</p>'), 'a\nb');
    });

    test('turns br into a line break', () {
      expect(_plainText('a<br />b'), 'a\nb');
    });

    test('bullets list items', () {
      expect(
        _plainText('<ul><li>one</li><li>two</li></ul>'),
        contains('• one'),
      );
    });

    test('drops the reply fallback the app already shows separately', () {
      final text = _plainText(
        '<mx-reply><blockquote>quoted</blockquote></mx-reply>the reply',
      );
      expect(text, 'the reply');
      expect(text, isNot(contains('quoted')));
    });
  });

  group('hasVisibleFormatting', () {
    test('is false for markup that renders as plain text', () {
      expect(MessageMarkup.hasVisibleFormatting('just words'), isFalse);
      expect(MessageMarkup.hasVisibleFormatting('<p>just words</p>'), isFalse);
    });

    test('is true when something would actually be styled', () {
      expect(MessageMarkup.hasVisibleFormatting('<strong>a</strong>'), isTrue);
      expect(MessageMarkup.hasVisibleFormatting('<p><em>a</em></p>'), isTrue);
    });
  });

  group('FormattedMessageText', () {
    testWidgets('falls back to the plaintext body when there is no markup', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FormattedMessageText(body: 'plain', style: _base),
          ),
        ),
      );
      expect(find.text('plain'), findsOneWidget);
    });

    testWidgets('prefers the plaintext body when markup adds nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FormattedMessageText(
              body: 'plain',
              formattedBody: '<p>plain</p>',
              style: _base,
            ),
          ),
        ),
      );
      // Rendered as a plain Text, so it is findable by its string.
      expect(find.text('plain'), findsOneWidget);
    });

    testWidgets('renders the markup when there is some', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FormattedMessageText(
              body: '**bold**',
              formattedBody: '<strong>bold</strong>',
              style: _base,
            ),
          ),
        ),
      );

      // The markdown markers must not reach the screen.
      expect(find.text('**bold**'), findsNothing);
      final richText = tester.widget<RichText>(find.byType(RichText).first);
      expect(_runs(richText.text).single.style.fontWeight, FontWeight.bold);
    });
  });
}
