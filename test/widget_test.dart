import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flow_md_editor/app.dart';
import 'package:flow_md_editor/widgets/anchored_markdown_preview.dart';
import 'package:flow_md_editor/widgets/preview_text.dart';
import 'package:flow_md_editor/widgets/source_editor.dart';

Future<void> launch(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
}) async {
  tester.view.resetPhysicalSize();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(FlowMdApp(prefs: prefs));
  await tester.pumpAndSettle();
}

Future<void> mode(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desktop shell defaults system theme with honest mode controls', (
    tester,
  ) async {
    await launch(tester);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Structure'), findsOneWidget);
    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('Live'), findsNothing);
    expect(find.text('本地 Markdown 预览'), findsNothing);
    expect(find.byTooltip('主题'), findsOneWidget);
    expect(find.byTooltip('查找 (⌘F / Ctrl+F)'), findsOneWidget);
    expect(find.byTooltip('文档设置'), findsOneWidget);
    // Default themeMode is system; widget tests use light platform brightness.
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.light,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact desktop size does not overflow', (tester) async {
    await launch(tester, size: const Size(800, 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'source outline navigation selects exact duplicate heading without marking dirty',
    (tester) async {
      await launch(tester);
      await mode(tester, 'Editor');
      final field = find.byType(TextField).last;
      final controller = tester.widget<TextField>(field).controller!;
      expect(find.text('未命名.md •'), findsNothing);
      await tester.tap(find.text('快捷键').first);
      await tester.pumpAndSettle();
      expect(
        controller.selection.baseOffset,
        controller.text.indexOf('## 快捷键'),
      );
      expect(find.text('未命名.md •'), findsNothing);
      await tester.enterText(field, '# Same\n\n\nParagraph\n\n## Same');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Same').last);
      await tester.pumpAndSettle();
      expect(
        controller.selection.baseOffset,
        controller.text.lastIndexOf('## Same'),
      );
      expect(find.text('未命名.md •'), findsWidgets);
    },
  );

  testWidgets('outline scrolls distant headings in preview; split left-only', (
    tester,
  ) async {
    await launch(tester);
    await mode(tester, 'Editor');
    final source = [
      for (var i = 0; i < 12; i++)
        '## Section $i\n\n${'Paragraph content. ' * 20}',
    ].join('\n\n');
    await tester.enterText(find.byType(TextField).last, source);
    await tester.pumpAndSettle();

    // Preview: outline still scrolls the rendered heading into view.
    await mode(tester, 'Preview');
    final outlinePreview = find.text('Section 11').first;
    await tester.ensureVisible(outlinePreview);
    await tester.tap(outlinePreview);
    await tester.pumpAndSettle();
    final rendered = find.text('Section 11').last;
    final position = tester.getTopLeft(rendered);
    expect(position.dy, greaterThan(100));
    expect(position.dy, lessThan(850));

    // Split: outline moves left caret only (no auto right sync).
    await mode(tester, 'Split');
    final field = find.byType(TextField).last;
    final controller = tester.widget<TextField>(field).controller!;
    final outlineSplit = find.text('Section 11').first;
    await tester.ensureVisible(outlineSplit);
    await tester.tap(outlineSplit);
    await tester.pumpAndSettle();
    expect(
      controller.selection.baseOffset,
      controller.text.indexOf('## Section 11'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('split mode shows source editor and preview side by side', (
    tester,
  ) async {
    await launch(tester);
    await mode(tester, 'Split');
    expect(find.text('自动刷新预览'), findsOneWidget);
    expect(find.text('定位'), findsOneWidget);
    expect(find.byTooltip('定位到编辑位置'), findsOneWidget);
    expect(find.byTooltip('查找 (⌘F / Ctrl+F)'), findsOneWidget);
    // Left source TextField + right rendered welcome heading.
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('Flow MD Editor'), findsWidgets);
    final field = find.byType(TextField).last;
    await tester.enterText(field, '# Hello Split\n\nBody text here.');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Hello Split'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview renders github-style alerts', (tester) async {
    await launch(tester);
    await mode(tester, 'Editor');
    await tester.enterText(
      find.byType(TextField).last,
      '# Alerts\n\n> [!NOTE]\n> Keep this in mind.\n',
    );
    await tester.pumpAndSettle();
    await mode(tester, 'Preview');
    expect(find.text('Note'), findsOneWidget);
    expect(find.textContaining('Keep this in mind.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('code copy icon becomes a check then copy again', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnchoredMarkdownPreview(
              source: '```dart\nvoid main() {}\n```\n',
              blockKeys: <int, GlobalKey>{},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.copy), findsOneWidget);
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tables render in preview and split', (tester) async {
    await launch(tester);
    await mode(tester, 'Editor');
    await tester.enterText(
      find.byType(TextField).last,
      '# Table\n\n| Name | Value |\n| --- | --- |\n| **A** | `one` |\n| B | two |',
    );
    await tester.pumpAndSettle();
    for (final name in ['Preview', 'Split']) {
      await mode(tester, name);
      final tables = tester.widgetList<Table>(find.byType(Table));
      expect(tables, isNotEmpty, reason: name);
      final table = tables.last;
      expect(table.children.length, 3);
      expect(table.children[1].decoration, isNot(table.children[2].decoration));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('find in preview stays in preview and scrolls to match', (
    tester,
  ) async {
    await launch(tester);
    await mode(tester, 'Editor');
    final source = [
      for (var i = 0; i < 12; i++)
        '## Section $i\n\n${'Paragraph content. ' * 20} uniquehit$i',
    ].join('\n\n');
    await tester.enterText(find.byType(TextField).last, source);
    await tester.pumpAndSettle();
    await mode(tester, 'Preview');
    await tester.tap(find.byTooltip('查找 (⌘F / Ctrl+F)'));
    await tester.pumpAndSettle();
    final findField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Text',
    );
    await tester.enterText(findField, 'uniquehit11');
    await tester.pumpAndSettle();
    expect(find.byType(SourceEditor), findsNothing);
    final rendered = find.textContaining('uniquehit11');
    expect(rendered, findsWidgets);
    final dy = tester.getTopLeft(rendered.last).dy;
    expect(dy, greaterThan(80));
    expect(dy, lessThan(850));
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(find.byType(SourceEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview find paints a glyph highlight on the match', (
    tester,
  ) async {
    await launch(tester);
    await mode(tester, 'Editor');
    await tester.enterText(
      find.byType(TextField).last,
      '# 仓库结构分层说明\n\n正文里也有分层两个字。',
    );
    await tester.pumpAndSettle();
    await mode(tester, 'Preview');
    await tester.tap(find.byTooltip('查找 (⌘F / Ctrl+F)'));
    await tester.pumpAndSettle();
    final findField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Text',
    );
    await tester.enterText(findField, '分层');
    await tester.pumpAndSettle();
    expect(find.textContaining('分层'), findsWidgets);
    expect(find.byType(SourceEditor), findsNothing);
    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byType(PreviewSelectableRichText),
        matching: find.byType(Text),
      ),
    );
    var boxed = 0;
    for (final text in texts) {
      final span = text.textSpan;
      if (span == null) continue;
      void walk(InlineSpan node) {
        if (node is TextSpan) {
          if (node.text == '分层' && node.style?.backgroundColor != null) {
            boxed++;
          }
          for (final child in node.children ?? const <InlineSpan>[]) {
            walk(child);
          }
        }
      }
      walk(span);
    }
    expect(
      boxed,
      greaterThan(0),
      reason: 'Preview find must box the matched 分层 glyphs',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('find next stays in split and selects match in source', (
    tester,
  ) async {
    await launch(tester);
    await mode(tester, 'Editor');
    await tester.enterText(
      find.byType(TextField).last,
      '# Alpha\n\nfindme one\n\n## Beta\n\nfindme two',
    );
    await tester.pumpAndSettle();
    await mode(tester, 'Split');
    // Open find via the toolbar button (reliable under widget tests).
    await tester.tap(find.byTooltip('查找 (⌘F / Ctrl+F)'));
    await tester.pumpAndSettle();
    final findField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Text',
    );
    await tester.enterText(findField, 'findme');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(find.text('定位'), findsOneWidget);
    final sourceField = find.byType(TextField).last;
    final controller = tester.widget<TextField>(sourceField).controller!;
    expect(controller.selection.isValid, isTrue);
    expect(
      controller.text
          .substring(controller.selection.start, controller.selection.end)
          .toLowerCase(),
      'findme',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('locate button scrolls preview to caret block', (tester) async {
    await launch(tester);
    await mode(tester, 'Editor');
    final source = [
      for (var i = 0; i < 12; i++)
        '## Section $i\n\n${'Paragraph content. ' * 20}',
    ].join('\n\n');
    await tester.enterText(find.byType(TextField).last, source);
    await tester.pumpAndSettle();
    await mode(tester, 'Split');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    final field = find.byType(TextField).last;
    final controller = tester.widget<TextField>(field).controller!;
    final target = controller.text.indexOf('## Section 11');
    controller.selection = TextSelection.collapsed(offset: target + 4);
    await tester.pump();
    // Without auto-sync, distant heading may still be far down.
    // Press 定位 to scroll the right pane.
    await tester.tap(find.byTooltip('定位到编辑位置'));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();

    final section = find.text('Section 11');
    expect(section, findsWidgets);
    final dy = tester.getTopLeft(section.last).dy;
    expect(dy, greaterThan(80));
    expect(dy, lessThan(850));
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing updates split preview without auto-scroll', (
    tester,
  ) async {
    await launch(tester);
    await mode(tester, 'Editor');
    const source =
        '# Title\n\nOne block here.\n\nTwo block here.\n\nThree block here.';
    await tester.enterText(find.byType(TextField).last, source);
    await tester.pumpAndSettle();
    await mode(tester, 'Split');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    final field = find.byType(TextField).last;
    final controller = tester.widget<TextField>(field).controller!;
    final at =
        controller.text.indexOf('Two block here.') + 'Two block here.'.length;
    controller.selection = TextSelection.collapsed(offset: at);
    await tester.pump();
    final next = controller.text.replaceRange(at, at, ' EXTRA');
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + ' EXTRA'.length),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Two block here. EXTRA'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new document adds another tab without discarding dirty', (
    tester,
  ) async {
    await launch(tester);
    await mode(tester, 'Editor');
    final field = find.byType(TextField).last;
    await tester.enterText(field, '# Keep Me\n\nDirty body');
    await tester.pumpAndSettle();
    expect(find.text('未命名.md •'), findsWidgets);
    await tester.tap(find.byTooltip('新建 (⌘N)'));
    await tester.pumpAndSettle();
    // Two open docs: dirty original stays listed, new blank is active.
    expect(find.text('未命名.md •'), findsWidgets);
    expect(find.text('Documents'), findsOneWidget);
    final controller = tester
        .widget<TextField>(find.byType(TextField).last)
        .controller!;
    expect(controller.text, isEmpty);
    // Switch back to dirty doc via sidebar title.
    await tester.tap(find.text('未命名.md •').first);
    await tester.pumpAndSettle();
    final restored = tester
        .widget<TextField>(find.byType(TextField).last)
        .controller!;
    expect(restored.text, contains('Keep Me'));
    expect(find.text('Keep Me'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toolbar theme and font size controls', (tester) async {
    await launch(tester);
    expect(find.byTooltip('主题'), findsOneWidget);
    expect(find.byTooltip('文档设置'), findsOneWidget);
    expect(find.text('外观'), findsNothing);

    await tester.tap(find.byTooltip('主题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色').last);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );

    await tester.tap(find.byTooltip('主题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('浅色').last);
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.light,
    );

    await tester.tap(find.byTooltip('增大字号'));
    await tester.pumpAndSettle();
    final field = find.byType(TextField).last;
    final style = tester.widget<TextField>(field).style!;
    expect(style.fontSize, 15);
    expect(tester.takeException(), isNull);
  });

  testWidgets('persisted theme and font load on launch', (tester) async {
    tester.view.resetPhysicalSize();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'theme_mode': 'dark',
      'font_size': 18.0,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(FlowMdApp(prefs: prefs));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).brightness,
      Brightness.dark,
    );
    final field = find.byType(TextField).last;
    expect(tester.widget<TextField>(field).style!.fontSize, 18);
    expect(find.text('深色'), findsWidgets);
    expect(find.text('18'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('xcode-style find bar switches to replace and closes on Done', (
    tester,
  ) async {
    await launch(tester);
    await tester.tap(find.byTooltip('查找 (⌘F / Ctrl+F)'));
    await tester.pumpAndSettle();
    final findField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Text',
    );
    expect(findField, findsOneWidget);
    expect(find.text('Find'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Contains'), findsOneWidget);
    expect(find.text('Aa'), findsOneWidget);
    expect(find.text('Replace All'), findsNothing);

    await tester.enterText(findField, 'Markdown');
    await tester.pumpAndSettle();
    expect(find.textContaining('/'), findsWidgets);

    await tester.tap(find.byTooltip('Find / Replace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace').last);
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Replace',
      ),
      findsOneWidget,
    );
    expect(find.text('Replace All'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(findField, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light theme preview headings are readable ink not a fill', (
    tester,
  ) async {
    await launch(tester);
    await mode(tester, 'Preview');
    // Rendered welcome title "# Flow MD Editor"
    final heading = find.byWidgetPredicate((w) {
      if (w is RichText) {
        final style = w.text.style;
        final plain = w.text.toPlainText();
        return plain.contains('Flow MD Editor') && (style?.fontSize ?? 0) >= 20;
      }
      if (w is SelectableText) {
        final plain = w.textSpan?.toPlainText() ?? w.data ?? '';
        final style = w.textSpan?.style ?? w.style;
        return plain.contains('Flow MD Editor') && (style?.fontSize ?? 0) >= 20;
      }
      return false;
    });
    expect(heading, findsWidgets);
    final widget = tester.widget(heading.first);
    TextStyle? style;
    if (widget is RichText) style = widget.text.style;
    if (widget is SelectableText) {
      style = widget.textSpan?.style ?? widget.style;
    }
    expect(style, isNotNull);
    expect(style!.color, isNotNull);
    // Dark ink on a light page, not a filled/black decoration.
    expect(style.color!.computeLuminance(), lessThan(0.45));
    expect(style.color!.computeLuminance(), greaterThan(0.0));
    expect(
      style.backgroundColor == null ||
          style.backgroundColor == Colors.transparent ||
          style.backgroundColor!.a == 0.0,
      isTrue,
    );
    expect(
      style.decoration == null || style.decoration == TextDecoration.none,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('H2 toolbar prefix applies to the current source line', (
    tester,
  ) async {
    await launch(tester);
    await mode(tester, 'Editor');
    final field = find.byType(TextField).last;
    await tester.enterText(field, 'plain heading');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('heading-h2')));
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(field).controller!;
    expect(controller.text, startsWith('## '));
    expect(controller.text, contains('plain heading'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto reload off waits for refresh; locate stays available', (
    tester,
  ) async {
    await launch(tester);
    await mode(tester, 'Split');
    expect(find.text('定位'), findsOneWidget);
    expect(find.byTooltip('查找 (⌘F / Ctrl+F)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('auto-reload-preview')));
    await tester.pumpAndSettle();

    final field = find.byType(TextField).last;
    await tester.enterText(field, '# Hello Manual\n\nBody text.');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Flow MD Editor'), findsWidgets);

    await tester.tap(find.byTooltip('刷新预览'));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(find.text('Hello Manual'), findsWidgets);
    expect(find.text('定位'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
