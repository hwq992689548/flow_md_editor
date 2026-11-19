/// Result of rewriting the heading prefix on the line that contains [caret].
class HeadingEdit {
  const HeadingEdit({required this.text, required this.caret});

  final String text;
  final int caret;
}

/// Set or toggle an ATX heading of [level] (1–6) on the line at [offset].
///
/// Same level again strips the prefix; a different level replaces it.
HeadingEdit toggleHeadingLine({
  required String text,
  required int offset,
  required int level,
}) {
  assert(level >= 1 && level <= 6);
  final clamped = offset.clamp(0, text.length);
  final lineStart = clamped == 0 ? 0 : text.lastIndexOf('\n', clamped - 1) + 1;
  var lineEnd = text.indexOf('\n', clamped);
  if (lineEnd < 0) lineEnd = text.length;
  final line = text.substring(lineStart, lineEnd);

  final match =
      RegExp(r'^(#{1,6})([ \t]+)').firstMatch(line) ??
      RegExp(r'^(#{1,6})$').firstMatch(line);
  final prefix = '${'#' * level} ';
  final String nextLine;
  if (match != null && match.group(1)!.length == level) {
    nextLine = match.end <= line.length ? line.substring(match.end) : '';
  } else if (match != null) {
    nextLine = prefix + line.substring(match.end);
  } else {
    nextLine = prefix + line;
  }

  return HeadingEdit(
    text: text.replaceRange(lineStart, lineEnd, nextLine),
    caret: lineStart + nextLine.length,
  );
}
