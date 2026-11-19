import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_md_editor/widgets/anchored_markdown_preview.dart';

const _source = '''
# 补充

- 打开 `0x60` 电源
- 发送 **控制** 命令
- 第二项完成校验
''';

void main() {
  String? lastSelection;

  Widget app() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        textSelectionTheme: const TextSelectionThemeData(
          selectionColor: Color(0xFFB3D7FF),
          cursorColor: Color(0xFF007AFF),
        ),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: AnchoredMarkdownPreview(
            source: _source,
            blockKeys: <int, GlobalKey>{},
            onSelectionChanged: (text) => lastSelection = text,
          ),
        ),
      ),
    );
  }

  testWidgets('drag selection spans a heading into a later list item',
      (tester) async {
    lastSelection = null;
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final heading = find.text('补充', findRichText: true);
    final laterItem = find.textContaining('第二项', findRichText: true);
    expect(heading, findsOneWidget);
    expect(laterItem, findsOneWidget);

    final start = tester.getRect(heading).centerLeft + const Offset(6, 0);
    final end = tester.getRect(laterItem).center;
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final text = lastSelection ?? '';
    expect(text, contains('补充'), reason: 'selected: "$text"');
    expect(text, contains('第二项'), reason: 'selected: "$text"');
    expect(
      RegExp(r'补充[\s\S]*\n[\s\S]*第二项').hasMatch(text),
      isTrue,
      reason: 'expected a newline between heading and list item, got: "$text"',
    );
  });

  testWidgets('select-all copies heading and list items together',
      (tester) async {
    lastSelection = null;
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final region =
        tester.state<SelectionAreaState>(find.byType(SelectionArea)).selectableRegion;
    region.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final text = lastSelection ?? '';
    expect(text, contains('补充'), reason: 'selected: "$text"');
    expect(text, contains('0x60'), reason: 'selected: "$text"');
    expect(text, contains('第二项'), reason: 'selected: "$text"');
  });
}
