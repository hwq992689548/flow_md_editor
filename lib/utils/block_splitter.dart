/// Top-level Markdown blocks for FlowMD-style live preview.
/// Keeps fences, tables, lists, and blockquotes as single blocks.
List<String> splitMarkdownBlocks(String source) {
  if (source.isEmpty) return [''];
  final lines = source.split('\n');
  final blocks = <String>[];
  final buf = <String>[];
  var inFence = false;
  String? fenceChar;
  var fenceLen = 0;

  bool isFence(String line) {
    final t = line.trimLeft();
    final m = RegExp(r'^(`{3,}|~{3,})').firstMatch(t);
    return m != null;
  }

  bool isTableRow(String line) => line.trim().contains('|');

  bool isListItem(String line) {
    final t = line.trimLeft();
    return RegExp(r'^([-*+]|\d+\.)\s+').hasMatch(t) ||
        RegExp(r'^[-*+] \[[ xX]\]\s+').hasMatch(t);
  }

  bool isQuote(String line) => line.trimLeft().startsWith('>');

  bool continuesBlock(String line) {
    if (line.trim().isEmpty) return false;
    if (isListItem(line) || isQuote(line) || isTableRow(line)) return true;
    // Indented continuation of list/quote
    if (line.startsWith('  ') || line.startsWith('\t')) return true;
    return false;
  }

  void flush() {
    while (buf.isNotEmpty && buf.last.trim().isEmpty) {
      buf.removeLast();
    }
    if (buf.isEmpty) return;
    blocks.add(buf.join('\n'));
    buf.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();

    if (inFence) {
      buf.add(line);
      if (trimmed.startsWith(fenceChar! * fenceLen) &&
          trimmed.replaceAll(RegExp(r'[`~]'), '').trim().isEmpty) {
        inFence = false;
        fenceChar = null;
        fenceLen = 0;
        flush();
      }
      continue;
    }

    if (isFence(line)) {
      if (buf.isNotEmpty && buf.every((e) => e.trim().isEmpty)) {
        buf.clear();
      } else if (buf.isNotEmpty) {
        flush();
      }
      final m = RegExp(r'^(`{3,}|~{3,})').firstMatch(trimmed)!;
      fenceChar = m.group(1)![0];
      fenceLen = m.group(1)!.length;
      inFence = true;
      buf.add(line);
      continue;
    }

    // Blank line: end current block unless inside table/list gathering handled below
    if (line.trim().isEmpty) {
      if (buf.isEmpty) continue;
      // Peek ahead: if next non-empty continues list/table/quote, keep blank inside
      var j = i + 1;
      while (j < lines.length && lines[j].trim().isEmpty) {
        j++;
      }
      if (j < lines.length &&
          continuesBlock(lines[j]) &&
          (isListItem(buf.first) ||
              isQuote(buf.first) ||
              buf.any(isTableRow))) {
        buf.add(line);
        continue;
      }
      flush();
      continue;
    }

    // Start table: gather consecutive table rows
    if (isTableRow(line) &&
        (buf.isEmpty || buf.every((e) => e.trim().isEmpty))) {
      buf.clear();
      buf.add(line);
      while (i + 1 < lines.length &&
          (isTableRow(lines[i + 1]) ||
              lines[i + 1].trim().isEmpty &&
                  i + 2 < lines.length &&
                  isTableRow(lines[i + 2]))) {
        i++;
        buf.add(lines[i]);
      }
      flush();
      continue;
    }

    // List / quote aggregation
    if (buf.isEmpty) {
      buf.add(line);
      continue;
    }

    final first = buf.first;
    if ((isListItem(first) || isQuote(first)) && continuesBlock(line)) {
      buf.add(line);
      continue;
    }

    // Heading always own block
    if (trimmed.startsWith('#')) {
      flush();
      buf.add(line);
      flush();
      continue;
    }

    // HR
    if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(trimmed)) {
      flush();
      buf.add(line);
      flush();
      continue;
    }

    // Default paragraph: if current is list/quote and line doesn't continue, flush
    if ((isListItem(first) || isQuote(first)) && !continuesBlock(line)) {
      flush();
      buf.add(line);
      continue;
    }

    buf.add(line);
  }

  if (buf.isNotEmpty) flush();
  return blocks.isEmpty ? [''] : blocks;
}

int blockIndexForOffset(List<String> blocks, int offset) {
  var cursor = 0;
  for (var i = 0; i < blocks.length; i++) {
    final end = cursor + blocks[i].length;
    if (offset <= end) return i;
    cursor = end + (i < blocks.length - 1 ? 2 : 0);
  }
  return blocks.isEmpty ? 0 : blocks.length - 1;
}

String joinBlocks(List<String> blocks) => blocks.join('\n\n');

({int start, int end}) blockRange(List<String> blocks, int index) {
  var start = 0;
  for (var i = 0; i < index; i++) {
    start += blocks[i].length;
    if (i < blocks.length - 1) start += 2;
  }
  return (start: start, end: start + blocks[index].length);
}
