import 'package:flutter_test/flutter_test.dart';
import 'package:flow_md_editor/utils/document_outline.dart';
import 'package:flow_md_editor/utils/block_splitter.dart';

void main() {
  test('outline ignores fences, respects fence length and exact offsets', () {
    const source =
        '# One\n\n````md\n# hidden\n```\n## also hidden\n````\n\n  ## Two ##\n~~~\n# hidden too\n~~~\n\nTitle\n=====\n';
    final headings = extractOutline(source);
    expect(headings.map((h) => h.title), ['One', 'Two', 'Title']);
    expect(headings.map((h) => h.level), [1, 2, 1]);
    expect(headings[1].offset, source.indexOf('  ## Two'));
  });
  test(
    'duplicate headings and non-normalized whitespace retain exact positions',
    () {
      const source = '# Same\n\n\n\nparagraph\n\n\n# Same';
      final headings = extractOutline(source);
      expect(headings.map((h) => h.offset), [0, source.lastIndexOf('# Same')]);
      final blocks = splitMarkdownBlocks(source);
      expect(
        sourceBlockIndex(source, blocks, headings.last.offset),
        blocks.length - 1,
      );
    },
  );
  test('CJK and Latin word counts and indented code', () {
    expect(documentWordCount('hello world 中文'), 4);
    expect(extractOutline('    # code\n# Real').map((h) => h.title), ['Real']);
    expect(extractOutline('#NoSpace\n# Yes').map((h) => h.title), ['Yes']);
  });
}
