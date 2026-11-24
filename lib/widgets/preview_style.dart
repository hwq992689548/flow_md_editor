import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/app_settings.dart';

/// Markdown stylesheet scaled by [fontSize] and tinted for light/dark.
MarkdownStyleSheet previewStyle(BuildContext context, {double? fontSize}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final base =
      (fontSize ??
              Theme.of(context).textTheme.bodyMedium?.fontSize ??
              AppSettings.defaultFontSize)
          .clamp(AppSettings.minFontSize, AppSettings.maxFontSize);
  final scale = base / AppSettings.defaultFontSize;

  final text = isDark ? const Color(0xFFDDDEE3) : const Color(0xFF1C1C1E);
  final muted = isDark ? const Color(0xFF999DA9) : const Color(0xFF6C6C70);
  // Soft near-ink in light mode so large bold CJK/Latin headings stay
  // readable instead of filling in as a solid black block.
  final heading = isDark ? const Color(0xFFF4F4F6) : const Color(0xFF1D1D1F);
  final heading2 = isDark ? const Color(0xFFF0F0F4) : const Color(0xFF2C2C2E);
  final grid = isDark ? const Color(0xFF343638) : const Color(0xFFD2D2D7);
  final codeFg = isDark ? const Color(0xFFD2DCF0) : const Color(0xFF1F2328);
  final codeBlockBg = isDark
      ? const Color(0xFF151719)
      : const Color(0xFFF7F7F9);
  final tableBg = isDark ? const Color(0xFF161819) : const Color(0xFFFAFAFC);
  final link = isDark ? const Color(0xFF79A7FF) : const Color(0xFF0A84FF);

  double s(double n) => n * scale;

  const fallbacks = <String>[
    '.AppleSystemUIFont',
    'PingFang SC',
    'Hiragino Sans GB',
    'Heiti SC',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  TextStyle headingStyle({
    required double size,
    required FontWeight weight,
    required Color color,
    double height = 1.35,
  }) {
    return TextStyle(
      inherit: false,
      fontSize: size,
      height: height,
      fontWeight: weight,
      color: color,
      textBaseline: TextBaseline.alphabetic,
      backgroundColor: Colors.transparent,
      decoration: TextDecoration.none,
      decorationColor: Colors.transparent,
      fontFamilyFallback: fallbacks,
    );
  }

  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: TextStyle(
      inherit: false,
      fontSize: s(16),
      height: 1.75,
      leadingDistribution: TextLeadingDistribution.even,
      color: text,
      textBaseline: TextBaseline.alphabetic,
      backgroundColor: Colors.transparent,
      decoration: TextDecoration.none,
      fontFamilyFallback: fallbacks,
    ),
    h1: headingStyle(size: s(32), weight: FontWeight.w700, color: heading),
    h2: headingStyle(size: s(24), weight: FontWeight.w600, color: heading2),
    h3: headingStyle(
      size: s(20),
      weight: FontWeight.w600,
      color: text,
      height: 1.4,
    ),
    h4: headingStyle(
      size: s(16),
      weight: FontWeight.w600,
      color: text,
      height: 1.4,
    ),
    h5: headingStyle(
      size: s(15),
      weight: FontWeight.w600,
      color: text,
      height: 1.4,
    ),
    h6: headingStyle(
      size: s(14),
      weight: FontWeight.w600,
      color: muted,
      height: 1.4,
    ),
    h1Padding: const EdgeInsets.only(top: 8, bottom: 12),
    h2Padding: const EdgeInsets.only(top: 20, bottom: 10),
    h3Padding: const EdgeInsets.only(top: 16, bottom: 8),
    blockSpacing: 18,
    listIndent: 28,
    a: TextStyle(color: link, decoration: TextDecoration.none),
    blockquote: TextStyle(fontSize: s(16), height: 1.7, color: muted),
    // Quote chrome is painted by [PreviewQuoteBuilder] so alerts can replace it.
    blockquotePadding: EdgeInsets.zero,
    blockquoteDecoration: const BoxDecoration(),
    // No TextStyle.backgroundColor: Flutter paints span backgrounds over
    // the selection highlight. Inline chips are drawn behind the text by
    // PreviewSelectableRichText instead.
    code: TextStyle(
      fontFamily: 'Menlo',
      fontSize: s(15),
      height: 1.7,
      leadingDistribution: TextLeadingDistribution.even,
      color: codeFg,
      backgroundColor: Colors.transparent,
    ),
    codeblockPadding: const EdgeInsets.all(16),
    codeblockDecoration: BoxDecoration(
      color: codeBlockBg,
      borderRadius: BorderRadius.circular(8),
    ),
    tableBorder: TableBorder(
      horizontalInside: BorderSide(color: grid, width: 0.7),
      top: BorderSide(color: grid, width: 0.7),
      bottom: BorderSide(color: grid, width: 0.7),
    ),
    tableCellsDecoration: BoxDecoration(color: tableBg),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    tableHead: TextStyle(
      fontSize: s(14),
      fontWeight: FontWeight.w600,
      color: text,
    ),
    tableBody: TextStyle(fontSize: s(14), height: 1.6, color: text),
    tableHeadAlign: TextAlign.left,
    tableColumnWidth: const FlexColumnWidth(),
    tableVerticalAlignment: TableCellVerticalAlignment.middle,
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: grid, width: 0.7)),
    ),
  );
}
