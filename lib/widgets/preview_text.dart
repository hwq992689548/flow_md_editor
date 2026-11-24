import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../utils/text_finder.dart';
import 'preview_selection.dart';
export 'preview_selection.dart';

/// Chrome-style find fill: the matched glyphs themselves, not the block.
const Color kPreviewFindFillLight = Color(0x99FFEB3B);
const Color kPreviewFindFillDark = Color(0x99E6C229);
const Color kPreviewFindFillActiveLight = Color(0x99FFC107);
const Color kPreviewFindFillActiveDark = Color(0x99FFB300);

/// Find-in-preview: paint the matched glyphs, not the whole block.
class PreviewFindHighlight {
  const PreviewFindHighlight({
    required this.query,
    required this.caseSensitive,
    required this.mode,
  });

  final String query;
  final bool caseSensitive;
  final FindMatchMode mode;

  @override
  bool operator ==(Object other) {
    return other is PreviewFindHighlight &&
        other.query == query &&
        other.caseSensitive == caseSensitive &&
        other.mode == mode;
  }

  @override
  int get hashCode => Object.hash(query, caseSensitive, mode);
}

class PreviewFindScope extends InheritedWidget {
  const PreviewFindScope({
    super.key,
    this.highlight,
    required super.child,
  });

  final PreviewFindHighlight? highlight;

  static PreviewFindHighlight? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PreviewFindScope>()
        ?.highlight;
  }

  @override
  bool updateShouldNotify(PreviewFindScope oldWidget) {
    return highlight != oldWidget.highlight;
  }
}

class PreviewFindActive extends InheritedWidget {
  const PreviewFindActive({
    super.key,
    required this.active,
    required super.child,
  });

  final bool active;

  static bool of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<PreviewFindActive>()
            ?.active ??
        false;
  }

  @override
  bool updateShouldNotify(PreviewFindActive oldWidget) {
    return active != oldWidget.active;
  }
}

/// Chip fill for unselected inline code. Painted *behind* the selection
/// highlight so a selected range stays one continuous color.
const Color kInlineCodeBackgroundLight = Color(0xFFEEEEF0);
const Color kInlineCodeBackgroundDark = Color(0xFF2C2C2E);
const Color kInlineCodeForegroundLight = Color(0xFF1F2328);
const Color kInlineCodeForegroundDark = Color(0xFFD2DCF0);

/// Shared typography for preview text so line boxes stay uniform and the
/// selection highlight can fill the whole line (including leading).
StrutStyle previewStrut(TextStyle style) {
  return StrutStyle(
    fontSize: style.fontSize,
    height: style.height,
    forceStrutHeight: true,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: style.fontWeight,
  );
}

/// Marks an inline-code run so [PreviewSelectableRichText] can paint its
/// chip behind the glyphs and the selection highlight.
class InlineCodeSpan extends TextSpan {
  const InlineCodeSpan({
    super.text,
    super.children,
    super.style,
    required this.chipColor,
  });

  final Color chipColor;
}

/// Inline code typography without [TextStyle.backgroundColor].
///
/// Flutter paints span backgrounds *after* the selection highlight, which
/// made opaque chips cover the selection and break it into segments.
InlineCodeSpan previewInlineCodeSpan(
  String text,
  TextStyle parent, {
  required bool isDark,
}) {
  // Build a fresh style so a parent backgroundColor/background paint
  // cannot leak onto the span (copyWith cannot clear a Paint).
  return InlineCodeSpan(
    text: text,
    chipColor: isDark ? kInlineCodeBackgroundDark : kInlineCodeBackgroundLight,
    style: TextStyle(
      inherit: false,
      fontFamily: 'Menlo',
      fontSize: parent.fontSize ?? 15,
      height: parent.height,
      fontWeight: parent.fontWeight,
      fontStyle: parent.fontStyle,
      leadingDistribution: TextLeadingDistribution.even,
      color: isDark ? kInlineCodeForegroundDark : kInlineCodeForegroundLight,
      textBaseline: parent.textBaseline ?? TextBaseline.alphabetic,
      decoration: TextDecoration.none,
    ),
  );
}

/// Collects [start, end) ranges of [InlineCodeSpan]s in a span tree.
List<(int start, int end, Color color)> collectInlineCodeRanges(
  InlineSpan root,
) {
  final ranges = <(int, int, Color)>[];
  var offset = 0;

  void walk(InlineSpan span) {
    if (span is InlineCodeSpan) {
      final length = span.toPlainText().length;
      if (length > 0) {
        ranges.add((offset, offset + length, span.chipColor));
      }
      offset += length;
      return;
    }
    if (span is TextSpan) {
      if (span.text != null) offset += span.text!.length;
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
      return;
    }
    if (span is WidgetSpan) {
      offset += 1;
    }
  }

  walk(root);
  return ranges;
}

/// Wraps each find hit with a yellow [TextStyle.backgroundColor] so the
/// matched glyphs stay boxed even when layout measurement misses.
TextSpan applyPreviewFindHighlight(
  TextSpan span,
  PreviewFindHighlight? spec, {
  required Color fill,
}) {
  if (spec == null || spec.query.isEmpty) return span;
  final plain = span.toPlainText(includeSemanticsLabels: false);
  final hits = findTextHits(
    plain,
    spec.query,
    caseSensitive: spec.caseSensitive,
    mode: spec.mode,
  );
  if (hits.isEmpty) return span;
  return _highlightInlineSpan(span, hits, fill, 0).$1 as TextSpan;
}

(InlineSpan, int) _highlightInlineSpan(
  InlineSpan span,
  List<TextHit> hits,
  Color fill,
  int offset,
) {
  if (span is! TextSpan) {
    final length = span is WidgetSpan
        ? 1
        : span.toPlainText(includeSemanticsLabels: false).length;
    return (span, offset + length);
  }

  final length = span.toPlainText(includeSemanticsLabels: false).length;
  if (length == 0) return (span, offset);
  final overlaps = hits.any(
    (hit) => hit.start < offset + length && hit.end > offset,
  );
  if (!overlaps) return (span, offset + length);

  // A recognizer can only be owned by one span — highlight the whole run.
  if (span.recognizer != null) {
    return (
      TextSpan(
        text: span.text,
        children: span.children,
        style: (span.style ?? const TextStyle()).copyWith(
          backgroundColor: fill,
        ),
        recognizer: span.recognizer,
        mouseCursor: span.mouseCursor,
      ),
      offset + length,
    );
  }

  final pieces = <InlineSpan>[];
  var cursor = offset;
  final text = span.text;
  if (text != null && text.isNotEmpty) {
    pieces.addAll(_splitTextHits(text, hits, fill, cursor, span.style));
    cursor += text.length;
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    final mapped = _highlightInlineSpan(child, hits, fill, cursor);
    pieces.add(mapped.$1);
    cursor = mapped.$2;
  }
  if (pieces.isEmpty) return (span, cursor);

  if (span is InlineCodeSpan) {
    return (
      InlineCodeSpan(
        style: span.style,
        children: pieces,
        chipColor: span.chipColor,
      ),
      cursor,
    );
  }
  return (
    TextSpan(
      style: span.style,
      mouseCursor: span.mouseCursor,
      children: pieces,
    ),
    cursor,
  );
}

List<InlineSpan> _splitTextHits(
  String text,
  List<TextHit> hits,
  Color fill,
  int offset,
  TextStyle? style,
) {
  final start = offset;
  final end = offset + text.length;
  final pieces = <InlineSpan>[];
  var i = 0;
  for (final hit in hits) {
    if (hit.end <= start || hit.start >= end) continue;
    final hs = math.max(hit.start, start) - start;
    final he = math.min(hit.end, end) - start;
    if (hs > i) {
      pieces.add(TextSpan(text: text.substring(i, hs)));
    }
    pieces.add(
      TextSpan(
        text: text.substring(hs, he),
        style: TextStyle(backgroundColor: fill),
      ),
    );
    i = he;
  }
  if (i < text.length) {
    pieces.add(TextSpan(text: text.substring(i)));
  }
  if (pieces.isEmpty) return [TextSpan(text: text, style: style)];
  return pieces;
}

/// Preview rich text that participates in a parent [SelectionArea].
///
/// The default [RenderParagraph] highlight is hidden (tight line boxes leave
/// gaps). This widget paints an includeLineSpacingMiddle highlight *behind*
/// the glyphs, and paints inline-code chips behind that highlight so a
/// selected range stays one continuous color.
Widget previewSelectableRichText(
  TextSpan span, {
  TextStyle? style,
  TextAlign textAlign = TextAlign.start,
}) {
  return PreviewSelectableRichText(
    span: span,
    style: style,
    textAlign: textAlign,
  );
}

/// Rich text for the preview [SelectionArea], with chips + a continuous
/// macOS-like selection highlight painted behind the glyphs.
class PreviewSelectableRichText extends StatefulWidget {
  const PreviewSelectableRichText({
    super.key,
    required this.span,
    this.style,
    this.textAlign = TextAlign.start,
  });

  final TextSpan span;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  State<PreviewSelectableRichText> createState() =>
      _PreviewSelectableRichTextState();
}

class _PreviewSelectableRichTextState extends State<PreviewSelectableRichText> {
  final _paintKey = GlobalKey();
  final _textKey = GlobalKey();
  final _selection = SelectionListenerNotifier();
  List<_CodeChip> _chips = const [];
  List<Rect> _highlights = const [];
  List<Rect> _findHighlights = const [];
  bool _findActive = false;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelection);
  }

  void _onSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _selection.removeListener(_onSelection);
    _selection.dispose();
    super.dispose();
  }

  List<TextSelection> get _currentSelections {
    if (!_selection.registered) return const [];
    final range = _selection.selection.range;
    if (range == null) return const [];
    final start = range.startOffset < range.endOffset
        ? range.startOffset
        : range.endOffset;
    final end = range.startOffset < range.endOffset
        ? range.endOffset
        : range.startOffset;
    if (start == end) return const [];
    return [TextSelection(baseOffset: start, extentOffset: end)];
  }

  TextStyle get _base {
    var base = widget.style ?? widget.span.style ?? const TextStyle();
    // Text.rich with inherit:false still needs fontSize + textBaseline.
    if (!base.inherit) {
      base = base.copyWith(
        fontSize: base.fontSize ?? 15,
        textBaseline: base.textBaseline ?? TextBaseline.alphabetic,
      );
    }
    return base;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(covariant PreviewSelectableRichText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.span != widget.span || oldWidget.style != widget.style) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
  }

  void _sync() {
    if (!mounted) return;
    final chips = _measureChips();
    final highlights = _measureHighlights();
    final finds = _measureFindHighlights();
    final active = PreviewFindActive.of(context);
    if (_sameChips(_chips, chips) &&
        _sameRects(_highlights, highlights) &&
        _sameRects(_findHighlights, finds) &&
        _findActive == active) {
      return;
    }
    setState(() {
      _chips = chips;
      _highlights = highlights;
      _findHighlights = finds;
      _findActive = active;
    });
  }

  List<Rect> _measureHighlights() {
    final paragraph = _findParagraph(
      _textKey.currentContext?.findRenderObject(),
    );
    final paintBox = _paintKey.currentContext?.findRenderObject() as RenderBox?;
    if (paragraph == null || paintBox == null || !paintBox.hasSize) {
      return const [];
    }
    final origin = paintBox.globalToLocal(paragraph.localToGlobal(Offset.zero));
    final rects = <Rect>[];
    for (final selection in _currentSelections) {
      if (!selection.isValid || selection.isCollapsed) continue;
      for (final box in paragraph.getBoxesForSelection(
        selection,
        boxHeightStyle: BoxHeightStyle.includeLineSpacingMiddle,
        boxWidthStyle: BoxWidthStyle.tight,
      )) {
        rects.add(
          Rect.fromLTWH(
            origin.dx + box.left,
            origin.dy + box.top,
            box.right - box.left,
            box.bottom - box.top,
          ),
        );
      }
    }
    return rects;
  }

  List<Rect> _measureFindHighlights() {
    final spec = PreviewFindScope.maybeOf(context);
    if (spec == null || spec.query.isEmpty) return const [];
    final paragraph = _findParagraph(
      _textKey.currentContext?.findRenderObject(),
    );
    final paintBox = _paintKey.currentContext?.findRenderObject() as RenderBox?;
    if (paragraph == null || paintBox == null || !paintBox.hasSize) {
      return const [];
    }
    final origin = paintBox.globalToLocal(paragraph.localToGlobal(Offset.zero));
    final plain = widget.span.toPlainText(includeSemanticsLabels: false);
    final hits = findTextHits(
      plain,
      spec.query,
      caseSensitive: spec.caseSensitive,
      mode: spec.mode,
    );
    final rects = <Rect>[];
    for (final hit in hits) {
      for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: hit.start, extentOffset: hit.end),
        boxHeightStyle: BoxHeightStyle.includeLineSpacingMiddle,
        boxWidthStyle: BoxWidthStyle.tight,
      )) {
        rects.add(
          Rect.fromLTWH(
            origin.dx + box.left - 1.5,
            origin.dy + box.top,
            (box.right - box.left) + 3,
            box.bottom - box.top,
          ),
        );
      }
    }
    return rects;
  }

  List<_CodeChip> _measureChips() {
    final paragraph = _findParagraph(
      _textKey.currentContext?.findRenderObject(),
    );
    final paintBox = _paintKey.currentContext?.findRenderObject() as RenderBox?;
    if (paragraph == null || paintBox == null || !paintBox.hasSize) {
      return const [];
    }
    final origin = paintBox.globalToLocal(paragraph.localToGlobal(Offset.zero));
    final fontSize = _base.fontSize ?? 15;
    final chips = <_CodeChip>[];
    for (final range in collectInlineCodeRanges(widget.span)) {
      for (final part in _unselectedParts(
        range.$1,
        range.$2,
        _currentSelections,
      )) {
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: part.$1, extentOffset: part.$2),
        );
        for (final box in boxes) {
          final midY = (box.top + box.bottom) / 2;
          final height = fontSize + 2;
          chips.add(
            _CodeChip(
              Rect.fromLTWH(
                origin.dx + box.left - 2,
                origin.dy + midY - height / 2,
                (box.right - box.left) + 4,
                height,
              ),
              range.$3,
            ),
          );
        }
      }
    }
    return chips;
  }

  List<(int, int)> _unselectedParts(
    int start,
    int end,
    List<TextSelection> selections,
  ) {
    var parts = <(int, int)>[(start, end)];
    for (final sel in selections) {
      if (!sel.isValid || sel.isCollapsed) continue;
      final next = <(int, int)>[];
      for (final part in parts) {
        final selStart = sel.start;
        final selEnd = sel.end;
        if (selEnd <= part.$1 || selStart >= part.$2) {
          next.add(part);
          continue;
        }
        if (part.$1 < selStart) next.add((part.$1, selStart));
        if (selEnd < part.$2) next.add((selEnd, part.$2));
      }
      parts = next;
      if (parts.isEmpty) break;
    }
    return parts;
  }

  RenderParagraph? _findParagraph(RenderObject? node) {
    if (node is RenderParagraph) return node;
    if (node == null) return null;
    RenderParagraph? found;
    node.visitChildren((child) {
      found ??= _findParagraph(child);
    });
    return found;
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the parent SelectionArea selection or find query changes.
    PreviewSelectionScope.maybeOf(context);
    PreviewFindScope.maybeOf(context);
    PreviewFindActive.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    final base = _base;
    final highlight =
        DefaultSelectionStyle.of(context).selectionColor ??
        Theme.of(context).textSelectionTheme.selectionColor ??
        const Color(0xFFB3D7FF);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final findFill = _findActive
        ? (isDark ? kPreviewFindFillActiveDark : kPreviewFindFillActiveLight)
        : (isDark ? kPreviewFindFillDark : kPreviewFindFillLight);
    final findBorder = _findActive
        ? (isDark ? const Color(0xFFFFD54F) : const Color(0xFFEF6C00))
        : (isDark ? const Color(0xFFC9A227) : const Color(0xFFF9A825));
    final spec = PreviewFindScope.maybeOf(context);
    final displaySpan = applyPreviewFindHighlight(
      widget.span,
      spec,
      fill: findFill,
    );
    // CustomPaint draws behind the text. The Text's own tight selection
    // is made fully transparent so only this continuous highlight shows.
    return SelectionListener(
      selectionNotifier: _selection,
      child: CustomPaint(
        key: _paintKey,
        painter: _PreviewBackgroundPainter(
          chips: _chips,
          highlights: _highlights,
          highlightColor: highlight,
          findHighlights: _findHighlights,
          findFill: findFill,
          findBorder: findBorder,
        ),
        child: Text.rich(
          displaySpan,
          key: _textKey,
          style: base,
          textAlign: widget.textAlign,
          strutStyle: previewStrut(base),
          textHeightBehavior: const TextHeightBehavior(
            leadingDistribution: TextLeadingDistribution.even,
          ),
          selectionColor: const Color(0x00000000),
        ),
      ),
    );
  }
}

class _CodeChip {
  const _CodeChip(this.rect, this.color);
  final Rect rect;
  final Color color;
}

bool _sameChips(List<_CodeChip> a, List<_CodeChip> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].rect != b[i].rect || a[i].color != b[i].color) return false;
  }
  return true;
}

bool _sameRects(List<Rect> a, List<Rect> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _PreviewBackgroundPainter extends CustomPainter {
  const _PreviewBackgroundPainter({
    required this.chips,
    required this.highlights,
    required this.highlightColor,
    required this.findHighlights,
    required this.findFill,
    required this.findBorder,
  });

  final List<_CodeChip> chips;
  final List<Rect> highlights;
  final Color highlightColor;
  final List<Rect> findHighlights;
  final Color findFill;
  final Color findBorder;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final chip in chips) {
      paint.color = chip.color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(chip.rect, const Radius.circular(3)),
        paint,
      );
    }
    paint.color = findFill;
    for (final rect in findHighlights) {
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rrect, paint);
    }
    if (findHighlights.isNotEmpty) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = findBorder;
      for (final rect in findHighlights) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          stroke,
        );
      }
    }
    paint
      ..style = PaintingStyle.fill
      ..color = highlightColor;
    for (final rect in highlights) {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewBackgroundPainter oldDelegate) {
    return oldDelegate.highlightColor != highlightColor ||
        oldDelegate.findFill != findFill ||
        oldDelegate.findBorder != findBorder ||
        !_sameRects(oldDelegate.highlights, highlights) ||
        !_sameRects(oldDelegate.findHighlights, findHighlights) ||
        !_sameChips(oldDelegate.chips, chips);
  }
}

/// Rebuilds a markdown element's inlines as a [TextSpan] tree.
///
/// Inline code keeps the parent font size and height so it cannot inflate the
/// line box. The chip itself is painted behind the selection, not as a span
/// background. Links use a recognizer rather than a WidgetSpan, which would
/// also break uniform line metrics.
TextSpan markdownInlineSpan(
  md.Element element,
  TextStyle style, {
  required bool isDark,
}) {
  return TextSpan(
    style: style,
    children: [
      for (final node in element.children ?? const <md.Node>[])
        _inline(node, style, isDark: isDark),
    ],
  );
}

InlineSpan _inline(md.Node node, TextStyle style, {required bool isDark}) {
  if (node is md.Text) return TextSpan(text: node.text, style: style);
  if (node is! md.Element) return const TextSpan();
  if (node.tag == 'br') return const TextSpan(text: '\n');
  var next = style;
  if (node.tag == 'strong' || node.tag == 'b') {
    next = next.copyWith(fontWeight: FontWeight.w700);
  }
  if (node.tag == 'em' || node.tag == 'i') {
    next = next.copyWith(fontStyle: FontStyle.italic);
  }
  if (node.tag == 'del') {
    next = next.copyWith(decoration: TextDecoration.lineThrough);
  }
  if (node.tag == 'code') {
    return previewInlineCodeSpan(node.textContent, next, isDark: isDark);
  }
  if (node.tag == 'a') {
    final uri = Uri.tryParse(node.attributes['href'] ?? '');
    final recognizer = TapGestureRecognizer()
      ..onTap = uri == null ? null : () => launchUrl(uri);
    return TextSpan(
      text: node.textContent,
      style: next.copyWith(
        color: isDark ? const Color(0xFF79A7FF) : const Color(0xFF0A84FF),
        decoration: TextDecoration.none,
      ),
      recognizer: recognizer,
    );
  }
  return TextSpan(
    style: next,
    children: [
      for (final child in node.children ?? const <md.Node>[])
        _inline(child, next, isDark: isDark),
    ],
  );
}

/// Replaces flutter_markdown's default SelectableText (tight line boxes,
/// default Material selection) with [previewSelectableRichText].
class PreviewTextBuilder extends MarkdownElementBuilder {
  // p/h*/blockquote are already block tags in flutter_markdown. Returning
  // true here would also mutate the package's global _kBlockTags list.
  @override
  bool isBlockElement() => false;

  // flutter_markdown only flushes the inline stack when a custom block
  // builder's visitText returns a non-null widget. The real text is rebuilt
  // from the element in visitElementAfterWithContext.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = (preferredStyle ?? parentStyle ?? const TextStyle()).copyWith(
      backgroundColor: Colors.transparent,
      leadingDistribution: TextLeadingDistribution.even,
    );
    return previewSelectableRichText(
      markdownInlineSpan(element, style, isDark: isDark),
      style: style,
    );
  }
}

/// Heading with Markdown Reader / GitHub-style spacing and h1/h2 rules.
class PreviewHeadingBuilder extends PreviewTextBuilder {
  PreviewHeadingBuilder(this.level);
  final int level;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final child = super.visitElementAfterWithContext(
      context,
      element,
      preferredStyle,
      parentStyle,
    );
    if (child == null) return null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD0D7DE);
    final pad = level == 1
        ? const EdgeInsets.only(top: 12, bottom: 12)
        : level == 2
        ? const EdgeInsets.only(top: 24, bottom: 10)
        : const EdgeInsets.only(top: 16, bottom: 8);
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: level <= 2 ? 8 : 0),
      padding: pad.copyWith(bottom: level <= 2 ? 10 : pad.bottom),
      decoration: level <= 2
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: hairline, width: 1)),
            )
          : null,
      child: child,
    );
  }
}

class _AlertLook {
  const _AlertLook(this.label, this.icon, this.accent, this.bg);
  final String label;
  final IconData icon;
  final Color accent;
  final Color bg;
}

/// GitHub-style quotes, plus `[!NOTE]` / `[!TIP]` / … alerts.
class PreviewQuoteBuilder extends PreviewTextBuilder {
  static final _alert = RegExp(
    r'^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*',
    caseSensitive: false,
  );

  static _AlertLook? _look(String kind, {required bool isDark}) {
    switch (kind.toUpperCase()) {
      case 'NOTE':
        return _AlertLook(
          'Note',
          Icons.info_outline,
          isDark ? const Color(0xFF6CB6FF) : const Color(0xFF0969DA),
          isDark ? const Color(0xFF152334) : const Color(0xFFDDF4FF),
        );
      case 'TIP':
        return _AlertLook(
          'Tip',
          Icons.lightbulb_outline,
          isDark ? const Color(0xFF3FB950) : const Color(0xFF1A7F37),
          isDark ? const Color(0xFF12261A) : const Color(0xFFDAFBE1),
        );
      case 'IMPORTANT':
        return _AlertLook(
          'Important',
          Icons.priority_high,
          isDark ? const Color(0xFFD2A8FF) : const Color(0xFF8250DF),
          isDark ? const Color(0xFF241A33) : const Color(0xFFFBEFFF),
        );
      case 'WARNING':
        return _AlertLook(
          'Warning',
          Icons.warning_amber_outlined,
          isDark ? const Color(0xFFD29922) : const Color(0xFF9A6700),
          isDark ? const Color(0xFF2A2111) : const Color(0xFFFFF8C5),
        );
      case 'CAUTION':
        return _AlertLook(
          'Caution',
          Icons.report_outlined,
          isDark ? const Color(0xFFFF7B72) : const Color(0xFFD1242F),
          isDark ? const Color(0xFF2D1517) : const Color(0xFFFFEBE9),
        );
    }
    return null;
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final raw = element.textContent.trim();
    final alert = _alert.firstMatch(raw);
    if (alert != null) {
      final look = _look(alert.group(1)!, isDark: isDark);
      if (look != null) {
        final body = raw.substring(alert.end).trim();
        final style = (preferredStyle ?? parentStyle ?? const TextStyle())
            .copyWith(
              color: isDark ? const Color(0xFFDDDEE3) : const Color(0xFF1C1C1E),
              backgroundColor: Colors.transparent,
            );
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: look.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: look.accent, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(look.icon, size: 16, color: look.accent),
                  const SizedBox(width: 6),
                  Text(
                    look.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: look.accent,
                    ),
                  ),
                ],
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 6),
                previewSelectableRichText(
                  TextSpan(text: body, style: style),
                  style: style,
                ),
              ],
            ],
          ),
        );
      }
    }
    final child = super.visitElementAfterWithContext(
      context,
      element,
      preferredStyle,
      parentStyle,
    );
    final hairline = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD0D7DE);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: hairline, width: 4)),
      ),
      child: child,
    );
  }
}
