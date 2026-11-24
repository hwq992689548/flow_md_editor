import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_md_editor/utils/text_finder.dart';
import 'package:flow_md_editor/widgets/anchored_markdown_preview.dart';
import 'package:flow_md_editor/widgets/preview_find_overlay.dart';
import 'package:flow_md_editor/widgets/preview_text.dart';

bool _spanHasFindFill(InlineSpan span, String needle, Color fill) {
  if (span is TextSpan) {
    if (span.text == needle && span.style?.backgroundColor == fill) {
      return true;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (_spanHasFindFill(child, needle, fill)) return true;
    }
  }
  return false;
}

void main() {
  test('applyPreviewFindHighlight boxes 分层 in the span', () {
    const span = TextSpan(
      text: '仓库结构分层说明',
      style: TextStyle(fontSize: 24, color: Color(0xFF1C1C1E)),
    );
    final out = applyPreviewFindHighlight(
      span,
      const PreviewFindHighlight(
        query: '分层',
        caseSensitive: false,
        mode: FindMatchMode.contains,
      ),
      fill: kPreviewFindFillLight,
    );
    expect(out.toPlainText(), '仓库结构分层说明');
    expect(_spanHasFindFill(out, '分层', kPreviewFindFillLight), isTrue);
  });

  testWidgets('PreviewSelectableRichText applies find fill to matched glyphs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PreviewFindScope(
            highlight: PreviewFindHighlight(
              query: '分层',
              caseSensitive: false,
              mode: FindMatchMode.contains,
            ),
            child: PreviewSelectableRichText(
              span: TextSpan(
                text: '仓库结构分层说明',
                style: TextStyle(
                  inherit: false,
                  fontSize: 24,
                  color: Color(0xFF1C1C1E),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(PreviewSelectableRichText),
        matching: find.byType(Text),
      ),
    );
    expect(text.textSpan, isNotNull);
    expect(
      _spanHasFindFill(text.textSpan!, '分层', kPreviewFindFillLight),
      isTrue,
      reason: 'matched 分层 must carry a yellow backgroundColor',
    );
  });

  testWidgets('preview find overlay boxes a table cell match', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnchoredMarkdownPreview(
              source:
                  '| 名称 | 路径 |\n| --- | --- |\n| Adapter | *AdapterContribution* |\n',
              blockKeys: <int, GlobalKey>{},
              findHighlight: const PreviewFindHighlight(
                query: 'AdapterContribution',
                caseSensitive: false,
                mode: FindMatchMode.contains,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('AdapterContribution'), findsWidgets);
    final overlays = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<PreviewFindOverlayPainter>()
        .toList();
    expect(overlays, isNotEmpty);
    expect(
      overlays.any((painter) => painter.rects.isNotEmpty),
      isTrue,
      reason: 'table cell match must paint a find overlay rect',
    );
  });
}
