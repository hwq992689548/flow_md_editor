import 'package:flutter_test/flutter_test.dart';
import 'package:flow_md_editor/utils/text_finder.dart';

void main() {
  const text = 'Find find FIND finder\nStart here';

  test('contains is case-insensitive by default', () {
    final hits = findTextHits(
      text,
      'find',
      caseSensitive: false,
      mode: FindMatchMode.contains,
    );
    expect(hits.map((h) => text.substring(h.start, h.end)).toList(),
        ['Find', 'find', 'FIND', 'find']);
  });

  test('case-sensitive contains', () {
    final hits = findTextHits(
      text,
      'Find',
      caseSensitive: true,
      mode: FindMatchMode.contains,
    );
    expect(hits, hasLength(1));
    expect(hits.first.start, 0);
  });

  test('full word skips prefixes', () {
    final hits = findTextHits(
      text,
      'find',
      caseSensitive: false,
      mode: FindMatchMode.fullWord,
    );
    expect(hits.map((h) => text.substring(h.start, h.end)).toList(),
        ['Find', 'find', 'FIND']);
  });

  test('starts with matches word prefixes', () {
    final hits = findTextHits(
      text,
      'fin',
      caseSensitive: false,
      mode: FindMatchMode.startsWith,
    );
    expect(hits.map((h) => text.substring(h.start, h.end)).toList(),
        ['Fin', 'fin', 'FIN', 'fin']);
  });

  test('regex finds captures and replaceAllHits is literal', () {
    final hits = findTextHits(
      'a1 a22 b3',
      r'a\d+',
      caseSensitive: true,
      mode: FindMatchMode.regex,
    );
    expect(hits.map((h) => 'a1 a22 b3'.substring(h.start, h.end)).toList(),
        ['a1', 'a22']);
    expect(
      replaceAllHits(
        'a1 a22 b3',
        r'a\d+',
        'X',
        caseSensitive: true,
        mode: FindMatchMode.regex,
      ),
      'X X b3',
    );
  });

  test('invalid regex yields no hits', () {
    expect(
      findTextHits(
        'abc',
        r'(',
        caseSensitive: false,
        mode: FindMatchMode.regex,
      ),
      isEmpty,
    );
  });
}
