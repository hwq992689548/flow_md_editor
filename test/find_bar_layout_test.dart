import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_md_editor/utils/text_finder.dart';
import 'package:flow_md_editor/widgets/find_bar.dart';

Future<void> _pumpBar(
  WidgetTester tester, {
  required ThemeData theme,
  required bool replaceOpen,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(1600, 400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: RepaintBoundary(
            key: const ValueKey('find-bar-shot'),
            child: FindBar(
              visible: true,
              matchLabel: '3/12',
              caseSensitive: false,
              matchMode: FindMatchMode.contains,
              onCaseSensitiveChanged: (_) {},
              onMatchModeChanged: (_) {},
              onClose: () {},
              onQueryChanged: (_) {},
              onNext: () {},
              onPrevious: () {},
              onReplace: (s, {required all}) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (replaceOpen) {
    await tester.tap(find.byTooltip('Find / Replace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace').last);
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('find bar controls are all 26px and fields match in replace mode',
      (tester) async {
    await _pumpBar(
      tester,
      theme: ThemeData.light(useMaterial3: true),
      replaceOpen: true,
    );

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    final textSize = tester.getSize(fields.at(0));
    // The TextField itself is inside the 26px chrome; the chrome is the
    // AnimatedContainer ancestor. Measure the field boxes via their top-left
    // containers of exact height.
    expect(textSize.height, lessThanOrEqualTo(26));
    expect(tester.getSize(fields.at(1)).height, lessThanOrEqualTo(26));
    expect((tester.getRect(fields.at(0)).center.dy - tester.getRect(fields.at(0)).top).abs(),
        greaterThan(4));

    // Outer chrome of each text field is the AnimatedContainer of height 26.
    final chromes = find.byType(AnimatedContainer);
    expect(tester.getSize(chromes.at(0)).height, 26);
    expect(tester.getSize(chromes.at(1)).height, 26);
    // Same width: search field and replace field.
    expect(tester.getSize(chromes.at(0)).width, tester.getSize(chromes.at(1)).width);

    // Aa, Done, Replace, Replace All should be 26px.
    for (final label in ['Aa', 'Done', 'Replace All']) {
      final rect = tester.getRect(find.text(label).first);
      // The control chrome is at least the text, but the tappable box is 26.
      expect(rect.height, lessThanOrEqualTo(26));
    }
    // The Done button Material is 26px tall.
    final doneRect = tester.getRect(find.byTooltip('Done'));
    expect(doneRect.height, 26);
    final aaRect = tester.getRect(find.byTooltip('Case Sensitive'));
    expect(aaRect.height, 26);
    final segment = tester.getRect(find.byKey(const ValueKey('find-prev-next')));
    expect(segment.height, 26);
    final prevRect = tester.getRect(find.byTooltip('Previous'));
    final nextRect = tester.getRect(find.byTooltip('Next'));
    // Joined: same top, adjacent (share a vertical edge, no gap), one outer chrome.
    expect(prevRect.top, closeTo(nextRect.top, 0.5));
    expect(prevRect.right, closeTo(nextRect.left, 2));
    expect(prevRect.left, closeTo(segment.left, 2));
    expect(nextRect.right, closeTo(segment.right, 2));

    // Replace button starts at the same X as Aa (the trailing column).
    final replaceBtn = tester.getRect(find.byTooltip('Replace'));
    expect(replaceBtn.left, closeTo(aaRect.left, 1));
    expect(replaceBtn.height, 26);

    // Search and replace field left edges align.
    expect(
      tester.getTopLeft(chromes.at(0)).dx,
      closeTo(tester.getTopLeft(chromes.at(1)).dx, 0.5),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('rasterize light replace find bar to /tmp/findbar_check.png',
      (tester) async {
    await _pumpBar(
      tester,
      theme: ThemeData.light(useMaterial3: true),
      replaceOpen: true,
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('find-bar-shot')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytesList = bytes!.buffer.asUint8List();
      for (final path in [
        '/tmp/findbar_check.png',
        '/Users/feixiang/Desktop/study/flow_md_editor/local_backups/findbar_check.png',
      ]) {
        await File(path).writeAsBytes(bytesList);
      }
    });
    final file = File(
      '/Users/feixiang/Desktop/study/flow_md_editor/local_backups/findbar_check.png',
    );
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(1000));
  });

  testWidgets('dark theme find bar also uses 26px controls', (tester) async {
    await _pumpBar(
      tester,
      theme: ThemeData.dark(useMaterial3: true),
      replaceOpen: true,
    );
    final chromes = find.byType(AnimatedContainer);
    expect(tester.getSize(chromes.at(0)).height, 26);
    expect(tester.getSize(chromes.at(1)).height, 26);
    expect(tester.getSize(chromes.at(0)).width, tester.getSize(chromes.at(1)).width);
    expect(tester.getRect(find.byTooltip('Done')).height, 26);
    expect(tester.takeException(), isNull);
  });


  testWidgets('find field text and placeholder are vertically centered',
      (tester) async {
    await _pumpBar(
      tester,
      theme: ThemeData.light(useMaterial3: true),
      replaceOpen: true,
    );

    Future<void> expectCentered(Finder field, {required bool typed}) async {
      if (typed) {
        await tester.enterText(field, 'Ay');
        await tester.pump();
      }
      final chrome = find.ancestor(
        of: field,
        matching: find.byType(AnimatedContainer),
      ).first;
      final chromeRect = tester.getRect(chrome);
      final editable = tester.state<EditableTextState>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      ).renderEditable;
      final local = editable.getLocalRectForCaret(const TextPosition(offset: 0));
      final caret = local.shift(editable.localToGlobal(Offset.zero));
      final delta = (caret.center.dy - chromeRect.center.dy).abs();
      expect(
        delta,
        lessThan(2.5),
        reason: 'caret center ${caret.center.dy} vs field center '
            '${chromeRect.center.dy} (typed=$typed, hint='
            '${tester.widget<TextField>(field).decoration?.hintText})',
      );
    }

    final textField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Text',
    );
    final replaceField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Replace',
    );
    expect(textField, findsOneWidget);
    expect(replaceField, findsOneWidget);

    // Placeholder (empty) and typed text both sit on the vertical center.
    await expectCentered(textField, typed: false);
    await expectCentered(replaceField, typed: false);
    await expectCentered(textField, typed: true);
  });
}
