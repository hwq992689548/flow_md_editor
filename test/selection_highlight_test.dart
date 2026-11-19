import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_md_editor/widgets/preview_text.dart';
import 'package:markdown/markdown.dart' as md;

const _lightSelection = Color(0xFFB3D7FF);
const _darkSelection = Color(0xFF3F638B);

const _headingText = '3. BLE 控制服务 `0x60~0x65` / `0x5E`';
const _paragraphText = '选中这一段时，`0x60~0x65` 与 `0x5E` 应与正文同色高亮。';

md.Element _inlineElement(String markdown) {
  final nodes = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)
      .parseInline(markdown);
  return md.Element('p', nodes);
}

TextStyle _headingStyle(bool isDark) {
  return TextStyle(
    inherit: false,
    fontSize: 18,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: isDark ? const Color(0xFFDDDEE3) : const Color(0xFF1C1C1E),
    textBaseline: TextBaseline.alphabetic,
    backgroundColor: Colors.transparent,
    decoration: TextDecoration.none,
    fontFamily: 'Hiragino Sans GB',
    fontFamilyFallback: const ['PingFang SC', 'SF Pro Text', 'Menlo'],
  );
}

TextStyle _bodyStyle(bool isDark) {
  return TextStyle(
    inherit: false,
    fontSize: 15,
    height: 1.7,
    leadingDistribution: TextLeadingDistribution.even,
    color: isDark ? const Color(0xFFDDDEE3) : const Color(0xFF1C1C1E),
    textBaseline: TextBaseline.alphabetic,
    backgroundColor: Colors.transparent,
    decoration: TextDecoration.none,
    fontFamily: 'Hiragino Sans GB',
    fontFamilyFallback: const ['PingFang SC', 'SF Pro Text', 'Menlo'],
  );
}

ThemeData _theme(Brightness brightness) {
  final selection =
      brightness == Brightness.dark ? _darkSelection : _lightSelection;
  final cursor = brightness == Brightness.dark
      ? const Color(0xFF0A84FF)
      : const Color(0xFF007AFF);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Hiragino Sans GB',
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: selection,
      cursorColor: cursor,
    ),
  );
}

Future<void> _loadSystemFonts() async {
  Future<void> load(String family, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    final loader = FontLoader(family);
    loader.addFont(
      Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
    );
    await loader.load();
  }

  await load('SF Pro Text', '/System/Library/Fonts/SFNS.ttf');
  await load('.AppleSystemUIFont', '/System/Library/Fonts/SFNS.ttf');
  await load('Hiragino Sans GB', '/System/Library/Fonts/Hiragino Sans GB.ttc');
  await load('PingFang SC', '/System/Library/Fonts/Hiragino Sans GB.ttc');
  await load('Menlo', '/System/Library/Fonts/Menlo.ttc');
}

int _channel(double c) => (c * 255.0).round().clamp(0, 255);

int _maxDelta(Color a, Color b) {
  final dR = (_channel(a.r) - _channel(b.r)).abs();
  final dG = (_channel(a.g) - _channel(b.g)).abs();
  final dB = (_channel(a.b) - _channel(b.b)).abs();
  return math.max(dR, math.max(dG, dB));
}

void main() {
  setUpAll(() async {
    await _loadSystemFonts();
  });

  test('collectInlineCodeRanges finds backtick spans', () {
    final span = markdownInlineSpan(
      _inlineElement(_headingText),
      _headingStyle(false),
      isDark: false,
    );
    final ranges = collectInlineCodeRanges(span);
    expect(ranges, hasLength(2));
    expect(
      span.toPlainText().substring(ranges[0].$1, ranges[0].$2),
      '0x60~0x65',
    );
    expect(span.toPlainText().substring(ranges[1].$1, ranges[1].$2), '0x5E');
    expect(ranges[0].$3, kInlineCodeBackgroundLight);
  });

  testWidgets(
    'selected heading and paragraph keep a uniform highlight over inline code',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 320));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final light = await _rasterTheme(tester, brightness: Brightness.light);
      final dark = await _rasterTheme(tester, brightness: Brightness.dark);

      await tester.runAsync(() async {
        final composite = await _stitchVertically(light.image, dark.image);
        final png =
            (await composite.toByteData(format: ui.ImageByteFormat.png))!;
        File(
          '/Users/feixiang/Desktop/study/flow_md_editor/local_backups/selection_check.png',
        ).writeAsBytesSync(png.buffer.asUint8List());
        File('/tmp/selection_check.png').writeAsBytesSync(
          png.buffer.asUint8List(),
        );
      });

      expect(light.image.height, greaterThan(10));
      expect(dark.image.height, greaterThan(10));
    },
  );

  testWidgets('unselected inline code still paints a chip behind the glyphs',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final isDark = false;
    final style = _headingStyle(isDark);
    final span = markdownInlineSpan(
      _inlineElement(_headingText),
      style,
      isDark: isDark,
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        home: ColoredBox(
          color: Colors.white,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: const ValueKey('unselected-raster'),
              child: ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: PreviewSelectableRichText(span: span, style: style),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    late ui.Image image;
    late ByteData pixels;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('unselected-raster')),
      );
      image = await boundary.toImage(pixelRatio: 2);
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });

    var chips = 0;
    for (var i = 0; i < pixels.lengthInBytes; i += 4) {
      final color = Color.fromARGB(
        pixels.getUint8(i + 3),
        pixels.getUint8(i),
        pixels.getUint8(i + 1),
        pixels.getUint8(i + 2),
      );
      if (_maxDelta(color, kInlineCodeBackgroundLight) <= 8) chips++;
    }
    expect(
      chips,
      greaterThan(80),
      reason: 'unselected inline code should still show a chip (found $chips)',
    );
  });
}

class _ThemeRaster {
  const _ThemeRaster({
    required this.image,
    required this.pixels,
    required this.samples,
  });
  final ui.Image image;
  final ByteData pixels;
  final List<Offset> samples;
}

Future<_ThemeRaster> _rasterTheme(
  WidgetTester tester, {
  required Brightness brightness,
}) async {
  final isDark = brightness == Brightness.dark;
  final headingStyle = _headingStyle(isDark);
  final bodyStyle = _bodyStyle(isDark);
  final headingSpan = markdownInlineSpan(
    _inlineElement(_headingText),
    headingStyle,
    isDark: isDark,
  );
  final bodySpan = markdownInlineSpan(
    _inlineElement(_paragraphText),
    bodyStyle,
    isDark: isDark,
  );

  final background = isDark ? const Color(0xFF1C1C1E) : Colors.white;

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(brightness),
      home: ColoredBox(
        color: background,
        child: PreviewSelectionSurface(
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: const ValueKey('selection-raster'),
              child: ColoredBox(
                color: background,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDark ? 'Dark' : 'Light',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontFamily: 'Hiragino Sans GB',
                        ),
                      ),
                      const SizedBox(height: 10),
                      PreviewSelectableRichText(
                        span: headingSpan,
                        style: headingStyle,
                      ),
                      const SizedBox(height: 16),
                      PreviewSelectableRichText(
                        span: bodySpan,
                        style: bodyStyle,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  final fields = find.byType(PreviewSelectableRichText);
  expect(fields, findsNWidgets(2));

  await _selectAllPreview(tester);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  final headingSamples = _leadingBandSamples(
    tester,
    fields.at(0),
    const ValueKey('selection-raster'),
  );
  final bodySamples = _leadingBandSamples(
    tester,
    fields.at(1),
    const ValueKey('selection-raster'),
  );

  late ui.Image image;
  late ByteData pixels;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('selection-raster')),
    );
    image = await boundary.toImage(pixelRatio: 2);
    pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });

  final expected = isDark ? _darkSelection : _lightSelection;
  final forbidden = isDark
      ? const [
          kInlineCodeBackgroundDark,
          Color(0xFF1C1E20),
          Color(0xFF2C2C2E),
        ]
      : const [
          kInlineCodeBackgroundLight,
          Color(0xFFF2F2F7),
        ];
  _expectUniformSelection(
    image: image,
    pixels: pixels,
    samples: headingSamples,
    expected: expected,
    forbidden: forbidden,
    label: isDark ? 'dark heading' : 'light heading',
    textColor: headingStyle.color!,
  );
  _expectUniformSelection(
    image: image,
    pixels: pixels,
    samples: bodySamples,
    expected: expected,
    forbidden: forbidden,
    label: isDark ? 'dark paragraph' : 'light paragraph',
    textColor: bodyStyle.color!,
  );

  return _ThemeRaster(
    image: image,
    pixels: pixels,
    samples: const [],
  );
}

Future<void> _selectAllPreview(WidgetTester tester) async {
  final region =
      tester.state<SelectionAreaState>(find.byType(SelectionArea)).selectableRegion;
  region.selectAll(SelectionChangedCause.keyboard);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

List<Offset> _leadingBandSamples(
  WidgetTester tester,
  Finder field,
  Key boundaryKey,
) {
  final origin = tester.getTopLeft(find.byKey(boundaryKey));
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: field, matching: find.byType(RichText)).first,
  );
  final selections = paragraph.selections
      .where((sel) => sel.isValid && !sel.isCollapsed)
      .toList();
  if (selections.isEmpty) {
    return const [];
  }
  final points = <Offset>[];
  for (final selection in selections) {
    final boxes = paragraph.getBoxesForSelection(
      selection,
      boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
      boxWidthStyle: ui.BoxWidthStyle.tight,
    );
    for (final box in boxes) {
      final global = paragraph.localToGlobal(Offset(box.left, box.top));
      final left = global.dx - origin.dx + 1;
      final top = global.dy - origin.dy + 1;
      final right = global.dx - origin.dx + (box.right - box.left) - 1;
      final bottom = global.dy - origin.dy + (box.bottom - box.top) - 1;
      for (var y = top; y < bottom; y += 0.5) {
        for (var x = left; x < right; x += 0.5) {
          points.add(Offset(x, y));
        }
      }
    }
  }
  return points;
}

void _expectUniformSelection({
  required ui.Image image,
  required ByteData pixels,
  required List<Offset> samples,
  required Color expected,
  required List<Color> forbidden,
  required String label,
  required Color textColor,
}) {
  expect(samples.length, greaterThan(30), reason: '$label too few samples');

  Color pixelAt(int x, int y) {
    final i = (y * image.width + x) * 4;
    return Color.fromARGB(
      pixels.getUint8(i + 3),
      pixels.getUint8(i),
      pixels.getUint8(i + 1),
      pixels.getUint8(i + 2),
    );
  }

  var considered = 0;
  var close = 0;
  var worst = 0;
  Color? worstColor;

  for (final sample in samples) {
    final x = (sample.dx * 2).round();
    final y = (sample.dy * 2).round();
    if (x < 0 || y < 0 || x >= image.width || y >= image.height) continue;
    final color = pixelAt(x, y);
    if (_channel(color.a) < 250) continue;
    // Skip typographic ink. Pure highlight must be counted before the
    // text-to-highlight AA segment check (the segment includes [expected]).
    if (_maxDelta(color, textColor) <= 40) continue;
    final d = _maxDelta(color, expected);
    if (d <= 36) {
      considered++;
      close++;
      continue;
    }
    if (_nearSegment(color, textColor, expected, tol: 20)) continue;
    considered++;
    if (d > worst) {
      worst = d;
      worstColor = color;
    }
    for (final chip in forbidden) {
      expect(
        _maxDelta(color, chip),
        greaterThan(25),
        reason: '$label hit chip color $chip at ($x,$y); got $color',
      );
    }
  }

  expect(considered, greaterThan(20), reason: '$label too few opaque samples');
  expect(
    close / considered,
    greaterThan(0.9),
    reason: '$label only $close/$considered pixels match $expected '
        '(worst $worstColor delta=$worst)',
  );
}

/// True if [p] lies near the RGB line segment from [a] to [b] (glyph AA).
bool _nearSegment(Color p, Color a, Color b, {required int tol}) {
  final px = _channel(p.r).toDouble();
  final py = _channel(p.g).toDouble();
  final pz = _channel(p.b).toDouble();
  final ax = _channel(a.r).toDouble();
  final ay = _channel(a.g).toDouble();
  final az = _channel(a.b).toDouble();
  final bx = _channel(b.r).toDouble();
  final by = _channel(b.g).toDouble();
  final bz = _channel(b.b).toDouble();
  final abx = bx - ax, aby = by - ay, abz = bz - az;
  final apx = px - ax, apy = py - ay, apz = pz - az;
  final ab2 = abx * abx + aby * aby + abz * abz;
  if (ab2 == 0) return _maxDelta(p, a) <= tol;
  var t = (apx * abx + apy * aby + apz * abz) / ab2;
  t = t.clamp(0.0, 1.0);
  final dx = px - (ax + t * abx);
  final dy = py - (ay + t * aby);
  final dz = pz - (az + t * abz);
  return math.sqrt(dx * dx + dy * dy + dz * dz) <= tol;
}

Future<ui.Image> _stitchVertically(ui.Image top, ui.Image bottom) async {
  final width = math.max(top.width, bottom.width);
  final height = top.height + bottom.height;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF888888),
  );
  canvas.drawImage(top, Offset.zero, Paint());
  canvas.drawImage(bottom, Offset(0, top.height.toDouble()), Paint());
  return recorder.endRecording().toImage(width, height);
}
