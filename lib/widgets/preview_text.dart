import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import 'preview_selection.dart';
export 'preview_selection.dart';

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
    chipColor:
        isDark ? kInlineCodeBackgroundDark : kInlineCodeBackgroundLight,
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
List<(int start, int end, Color color)> collectInlineCodeRanges(InlineSpan root) {
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
    if (_sameChips(_chips, chips) && _sameRects(_highlights, highlights)) {
      return;
    }
    setState(() {
      _chips = chips;
      _highlights = highlights;
    });
  }

  List<Rect> _measureHighlights() {
    final paragraph = _findParagraph(_textKey.currentContext?.findRenderObject());
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

  List<_CodeChip> _measureChips() {
    final paragraph = _findParagraph(_textKey.currentContext?.findRenderObject());
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
    // Rebuild when the parent SelectionArea selection changes.
    PreviewSelectionScope.maybeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    final base = _base;
    final highlight = DefaultSelectionStyle.of(context).selectionColor ??
        Theme.of(context).textSelectionTheme.selectionColor ??
        const Color(0xFFB3D7FF);
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
      ),
      child: Text.rich(
        widget.span,
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
  });

  final List<_CodeChip> chips;
  final List<Rect> highlights;
  final Color highlightColor;

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
    paint.color = highlightColor;
    for (final rect in highlights) {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewBackgroundPainter oldDelegate) {
    return oldDelegate.highlightColor != highlightColor ||
        !_sameRects(oldDelegate.highlights, highlights) ||
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

InlineSpan _inline(
  md.Node node,
  TextStyle style, {
  required bool isDark,
}) {
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
