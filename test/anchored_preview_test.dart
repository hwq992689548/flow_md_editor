import 'package:flutter_test/flutter_test.dart';
import 'package:flow_md_editor/utils/block_splitter.dart';
import 'package:flow_md_editor/utils/document_outline.dart';
import 'package:flow_md_editor/utils/link_reference_defs.dart';
import 'package:flow_md_editor/widgets/anchored_markdown_preview.dart';

void main() {
  test('multiple paragraphs under one heading keep distinct source ranges', () {
    const source = '# Title\n\nFirst paragraph.\n\n\nSecond paragraph.\n\nThird paragraph.';
    final blocks = splitMarkdownBlocks(source);
    final starts = sourceBlockOffsets(source, blocks);
    expect(blocks.length, greaterThanOrEqualTo(4));
    expect(starts[0], 0);

    final firstPara = source.indexOf('First paragraph.');
    final secondPara = source.indexOf('Second paragraph.');
    final thirdPara = source.indexOf('Third paragraph.');

    expect(anchoredBlockStartForOffset(source, firstPara), starts[1]);
    expect(anchoredBlockStartForOffset(source, secondPara), isNot(starts[1]));
    expect(
      anchoredBlockStartForOffset(source, secondPara),
      anchoredBlockStartForOffset(source, secondPara + 3),
    );
    expect(
      anchoredBlockIndexForOffset(source, secondPara),
      isNot(anchoredBlockIndexForOffset(source, firstPara)),
    );
    expect(
      anchoredBlockIndexForOffset(source, thirdPara),
      greaterThan(anchoredBlockIndexForOffset(source, secondPara)),
    );

    // Blank lines between paragraphs map to the preceding block.
    final blank = source.indexOf('\n\n\n') + 1;
    expect(
      anchoredBlockIndexForOffset(source, blank),
      anchoredBlockIndexForOffset(source, firstPara),
    );
  });

  test('fenced code and table stay single blocks with exact offsets', () {
    const source = '''# H

```dart
void main() {}
```

| a | b |
| - | - |
| 1 | 2 |

Tail text.''';
    final blocks = splitMarkdownBlocks(source);
    final starts = sourceBlockOffsets(source, blocks);
    final fence = source.indexOf('```dart');
    final table = source.indexOf('| a | b |');
    final tail = source.indexOf('Tail text.');
    expect(source.substring(starts[anchoredBlockIndexForOffset(source, fence)]).startsWith('```'), isTrue);
    expect(blocks[anchoredBlockIndexForOffset(source, table)].contains('| a | b |'), isTrue);
    expect(anchoredBlockStartForOffset(source, tail), starts.last);
  });

  test('link reference defs extracted outside fences', () {
    const source = '''See [x].

```
[x]: http://example.com/hidden
```

[x]: http://example.com/real
''';
    final defs = extractLinkReferenceDefinitions(source);
    expect(defs.contains('http://example.com/real'), isTrue);
    expect(defs.contains('hidden'), isFalse);
  });
}
