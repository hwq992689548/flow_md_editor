/// A heading's exact source offset keeps duplicate titles independently navigable.
class DocumentHeading {
  const DocumentHeading(this.title, this.level, this.offset);
  final String title;
  final int level;
  final int offset;
}

List<DocumentHeading> extractOutline(String source) {
  final result = <DocumentHeading>[];
  final lines = source.split('\n');
  String? fence;
  var fenceLength = 0;
  var offset = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].replaceAll('\r', '');
    final marker = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$').firstMatch(line);
    if (fence != null) {
      if (marker != null &&
          marker[1]![0] == fence &&
          marker[1]!.length >= fenceLength &&
          marker[2]!.trim().isEmpty) {
        fence = null;
      }
    } else if (marker != null) {
      fence = marker[1]![0];
      fenceLength = marker[1]!.length;
    } else {
      final atx = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+(.*)|$)').firstMatch(line);
      if (atx != null) {
        final title = (atx[2] ?? '')
            .replaceFirst(RegExp(r'[ \t]+#+[ \t]*$'), '')
            .trim();
        result.add(
          DocumentHeading(
            title.isEmpty ? 'Untitled heading' : title,
            atx[1]!.length,
            offset,
          ),
        );
      } else if (line.trim().isNotEmpty &&
          !RegExp(r'^\s').hasMatch(line) &&
          i + 1 < lines.length &&
          RegExp(r'^ {0,3}(=+|-+)[ \t]*\r?$').hasMatch(lines[i + 1])) {
        result.add(
          DocumentHeading(
            line.trim(),
            lines[i + 1].trim().startsWith('=') ? 1 : 2,
            offset,
          ),
        );
      }
    }
    offset += lines[i].length + 1;
  }
  return result;
}

/// Locate blocks in the original document (blank lines need not be normalized).
List<int> sourceBlockOffsets(String source, List<String> blocks) {
  var cursor = 0;
  return blocks.map((block) {
    final found = source.indexOf(block, cursor);
    final start = found < 0 ? cursor : found;
    cursor = start + block.length;
    return start;
  }).toList();
}

int sourceBlockIndex(String source, List<String> blocks, int offset) {
  final starts = sourceBlockOffsets(source, blocks);
  for (var i = starts.length - 1; i >= 0; i--) {
    if (offset >= starts[i]) return i;
  }
  return 0;
}

int documentWordCount(String source) => RegExp(
  r'[\u3400-\u9fff]|[\p{L}\p{N}_]+',
  unicode: true,
).allMatches(source).length;
