import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../utils/text_finder.dart';
import 'preview_text.dart';

/// Paints find hits on top of every [RenderParagraph] in [child], including
/// table cells and fenced code that do not use [PreviewSelectableRichText].
class PreviewFindOverlay extends StatefulWidget {
  const PreviewFindOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<PreviewFindOverlay> createState() => _PreviewFindOverlayState();
}

class _PreviewFindOverlayState extends State<PreviewFindOverlay> {
  final _childKey = GlobalKey();
  List<Rect> _rects = const [];

  @override
  Widget build(BuildContext context) {
    final spec = PreviewFindScope.maybeOf(context);
    final active = PreviewFindActive.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(spec));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = active
        ? (isDark ? kPreviewFindFillActiveDark : kPreviewFindFillActiveLight)
        : (isDark ? kPreviewFindFillDark : kPreviewFindFillLight);
    final border = active
        ? (isDark ? const Color(0xFFFFD54F) : const Color(0xFFEF6C00))
        : (isDark ? const Color(0xFFFFC107) : const Color(0xFFF9A825));
    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        KeyedSubtree(key: _childKey, child: widget.child),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: PreviewFindOverlayPainter(
                rects: _rects,
                fill: fill,
                border: border,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _sync(PreviewFindHighlight? spec) {
    if (!mounted) return;
    final rects = _measure(spec);
    if (_sameRects(_rects, rects)) return;
    setState(() => _rects = rects);
  }

  List<Rect> _measure(PreviewFindHighlight? spec) {
    if (spec == null || spec.query.isEmpty) return const [];
    final overlay = context.findRenderObject() as RenderBox?;
    final root = _childKey.currentContext?.findRenderObject();
    if (overlay == null ||
        root == null ||
        !overlay.hasSize ||
        !overlay.attached) {
      return const [];
    }
    final rects = <Rect>[];
    void walk(RenderObject node) {
      if (node is RenderParagraph && node.hasSize && node.attached) {
        rects.addAll(_boxesForParagraph(node, overlay, spec));
      }
      node.visitChildren(walk);
    }

    walk(root);
    return rects;
  }

  List<Rect> _boxesForParagraph(
    RenderParagraph paragraph,
    RenderBox overlay,
    PreviewFindHighlight spec,
  ) {
    final plain = paragraph.text.toPlainText(includeSemanticsLabels: false);
    final hits = findTextHits(
      plain,
      spec.query,
      caseSensitive: spec.caseSensitive,
      mode: spec.mode,
    );
    if (hits.isEmpty) return const [];
    final origin = overlay.globalToLocal(paragraph.localToGlobal(Offset.zero));
    final rects = <Rect>[];
    for (final hit in hits) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: hit.start, extentOffset: hit.end),
        boxHeightStyle: BoxHeightStyle.includeLineSpacingMiddle,
        boxWidthStyle: BoxWidthStyle.tight,
      );
      if (boxes.isEmpty) {
        rects.add(
          Rect.fromLTWH(
            origin.dx - 2,
            origin.dy,
            paragraph.size.width + 4,
            paragraph.size.height,
          ),
        );
        continue;
      }
      for (final box in boxes) {
        rects.add(
          Rect.fromLTWH(
            origin.dx + box.left - 2,
            origin.dy + box.top,
            (box.right - box.left) + 4,
            box.bottom - box.top,
          ),
        );
      }
    }
    return rects;
  }
}

class PreviewFindOverlayPainter extends CustomPainter {
  const PreviewFindOverlayPainter({
    required this.rects,
    required this.fill,
    required this.border,
  });

  final List<Rect> rects;
  final Color fill;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    if (rects.isEmpty) return;
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = border;
    for (final rect in rects) {
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant PreviewFindOverlayPainter oldDelegate) {
    return oldDelegate.fill != fill ||
        oldDelegate.border != border ||
        !_sameRects(oldDelegate.rects, rects);
  }
}

bool _sameRects(List<Rect> a, List<Rect> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
