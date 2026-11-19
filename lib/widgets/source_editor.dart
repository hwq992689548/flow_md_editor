import 'dart:ui' show BoxHeightStyle, BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:highlight/highlight.dart' show Node, highlight;

/// Text controller that paints Markdown tokens while remaining IME-safe.
class HighlightingTextController extends TextEditingController {
  HighlightingTextController({super.text, Map<String, TextStyle>? theme})
    : theme = theme ?? atomOneDarkTheme;

  Map<String, TextStyle> theme;

  void applyTheme(Map<String, TextStyle> next) {
    theme = next;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: true,
      );
    }
    final result = highlight.parse(text, language: 'markdown');
    final children = _convert(result.nodes ?? const <Node>[], theme, style);
    return TextSpan(style: style, children: children);
  }
}

List<InlineSpan> _convert(
  List<Node> nodes,
  Map<String, TextStyle> theme,
  TextStyle? base,
) {
  final spans = <InlineSpan>[];
  for (final node in nodes) {
    final nodeStyle = node.className == null ? null : theme[node.className!];
    if (node.value != null) {
      spans.add(TextSpan(text: node.value, style: nodeStyle ?? base));
    } else if (node.children != null) {
      spans.add(
        TextSpan(
          style: nodeStyle,
          children: _convert(node.children!, theme, base),
        ),
      );
    }
  }
  return spans;
}

/// Source pane: filename tab, line-number gutter, highlighted Markdown field.
class SourceEditor extends StatefulWidget {
  const SourceEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.fontSize,
    required this.fileName,
    this.onTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final double fontSize;
  final String fileName;
  final VoidCallback? onTap;

  @override
  State<SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<SourceEditor> {
  static const _topPad = 8.0;
  static const _gutterWidth = 48.0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_repaint);
    widget.controller.addListener(_repaint);
  }

  @override
  void didUpdateWidget(covariant SourceEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_repaint);
      widget.scrollController.addListener(_repaint);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_repaint);
      widget.controller.addListener(_repaint);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_repaint);
    widget.controller.removeListener(_repaint);
    super.dispose();
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  double get _lineHeight => widget.fontSize * 1.5;

  int get _lineCount {
    final text = widget.controller.text;
    if (text.isEmpty) return 1;
    return '\n'.allMatches(text).length + 1;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (widget.controller is HighlightingTextController) {
      (widget.controller as HighlightingTextController).applyTheme(
        dark ? atomOneDarkTheme : atomOneLightTheme,
      );
    }
    final gutterFg = dark ? const Color(0xFF636A76) : const Color(0xFFA0A4AE);
    final gutterBg = dark ? const Color(0xFF1A1C1E) : const Color(0xFFF3F3F5);
    final tabBg = dark ? const Color(0xFF222426) : const Color(0xFFEDEDF0);
    final paneBg = dark ? const Color(0xFF1C1C1E) : Colors.white;
    final border = dark ? const Color(0xFF3A3A3C) : const Color(0xFFD2D2D7);
    final tabFg = dark ? const Color(0xFFD1D1D6) : const Color(0xFF1C1C1E);
    final scrollOffset = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0.0;
    final textStyle = TextStyle(
      fontFamily: 'Menlo',
      fontSize: widget.fontSize,
      height: 1.5,
      color: dark ? const Color(0xFFD7DAE0) : const Color(0xFF1F2328),
    );

    return ColoredBox(
      color: paneBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tabBg,
                border: Border(bottom: BorderSide(color: border)),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: paneBg,
                    border: Border(
                      right: BorderSide(color: border),
                    ),
                  ),
                  child: Text(
                    widget.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: tabFg),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ColoredBox(
                  color: gutterBg,
                  child: SizedBox(
                    width: _gutterWidth,
                    child: CustomPaint(
                      painter: _GutterPainter(
                        lineCount: _lineCount,
                        lineHeight: _lineHeight,
                        scrollOffset: scrollOffset,
                        color: gutterFg,
                        topPadding: _topPad,
                        fontSize: widget.fontSize,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    scrollController: widget.scrollController,
                    maxLines: null,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    style: textStyle,
                    cursorColor: const Color(0xFF0A84FF),
                    selectionHeightStyle:
                        BoxHeightStyle.includeLineSpacingMiddle,
                    selectionWidthStyle: BoxWidthStyle.tight,
                    scrollPadding: const EdgeInsets.all(8),
                    decoration: const InputDecoration.collapsed(
                      hintText: '开始书写 Markdown…',
                    ).copyWith(
                      contentPadding: const EdgeInsets.fromLTRB(8, _topPad, 12, 24),
                    ),
                    onTap: widget.onTap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GutterPainter extends CustomPainter {
  _GutterPainter({
    required this.lineCount,
    required this.lineHeight,
    required this.scrollOffset,
    required this.color,
    required this.topPadding,
    required this.fontSize,
  });

  final int lineCount;
  final double lineHeight;
  final double scrollOffset;
  final Color color;
  final double topPadding;
  final double fontSize;

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final style = TextStyle(
      fontFamily: 'Menlo',
      fontSize: fontSize * 0.85,
      height: 1.5,
      color: color,
    );
    for (var i = 0; i < lineCount; i++) {
      final y = topPadding + i * lineHeight - scrollOffset;
      if (y + lineHeight < 0 || y > size.height) continue;
      tp.text = TextSpan(text: '${i + 1}', style: style);
      tp.layout();
      tp.paint(canvas, Offset(size.width - 6 - tp.width, y));
    }
  }

  @override
  bool shouldRepaint(covariant _GutterPainter old) {
    return old.lineCount != lineCount ||
        old.lineHeight != lineHeight ||
        old.scrollOffset != scrollOffset ||
        old.color != color ||
        old.fontSize != fontSize;
  }
}
