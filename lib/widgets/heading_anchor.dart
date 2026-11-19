import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../utils/document_outline.dart';
import 'preview_style.dart';
import 'preview_text.dart';

/// Anchors headings without splitting the read-only document, preserving
/// document-wide Markdown features such as reference links and footnotes.
class HeadingAnchorBuilder extends MarkdownElementBuilder {
  HeadingAnchorBuilder(
    this.headings,
    this.keyFor,
    String source,
    this.imageBuilder,
  ) {
    _document.parseLines(source.split('\n'));
  }
  final _document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
  final Widget Function(Uri, String?, String?) imageBuilder;
  final List<DocumentHeading> headings;
  final GlobalKey Function(int offset) keyFor;
  final _used = <int>{};

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return const SizedBox.shrink();
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final level = int.parse(element.tag.substring(1));
    DocumentHeading? match;
    for (final heading in headings) {
      final plain = _document
          .parseInline(heading.title)
          .map((n) => n.textContent)
          .join();
      if (!_used.contains(heading.offset) &&
          heading.level == level &&
          plain == element.textContent) {
        match = heading;
        _used.add(heading.offset);
        break;
      }
    }
    final sheet = previewStyle(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = (preferredStyle ?? sheet.h3!).copyWith(
      backgroundColor: Colors.transparent,
      decoration: TextDecoration.none,
    );
    return Padding(
      key: match == null ? null : keyFor(match.offset),
      padding: level == 1
          ? sheet.h1Padding!
          : level == 2
          ? sheet.h2Padding!
          : sheet.h3Padding!,
      child: previewSelectableRichText(
        TextSpan(
          style: style,
          children: [
            for (final node in element.children ?? <md.Node>[])
              _inline(node, style, isDark: isDark),
          ],
        ),
        style: style,
      ),
    );
  }

  InlineSpan _inline(md.Node node, TextStyle style, {required bool isDark}) {
    if (node is md.Text) return TextSpan(text: node.text, style: style);
    if (node is! md.Element) return const TextSpan();
    if (node.tag == 'br') return const TextSpan(text: '\n');
    var next = style;
    if (node.tag == 'strong') next = next.copyWith(fontWeight: FontWeight.w700);
    if (node.tag == 'em') next = next.copyWith(fontStyle: FontStyle.italic);
    if (node.tag == 'del') {
      next = next.copyWith(decoration: TextDecoration.lineThrough);
    }
    if (node.tag == 'code') {
      return previewInlineCodeSpan(node.textContent, next, isDark: isDark);
    }
    if (node.tag == 'a') {
      final uri = Uri.tryParse(node.attributes['href'] ?? '');
      return WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: InkWell(
          onTap: uri == null ? null : () => launchUrl(uri),
          child: Text(
            node.textContent,
            style: next.copyWith(
              color: isDark ? const Color(0xFF79A7FF) : const Color(0xFF0A84FF),
            ),
          ),
        ),
      );
    }
    if (node.tag == 'img') {
      final uri = Uri.tryParse(node.attributes['src'] ?? '');
      return uri == null
          ? const TextSpan()
          : WidgetSpan(
              child: imageBuilder(
                uri,
                node.attributes['title'],
                node.attributes['alt'],
              ),
            );
    }
    return TextSpan(
      style: next,
      children: [
        for (final child in node.children ?? <md.Node>[])
          _inline(child, next, isDark: isDark),
      ],
    );
  }
}
