import 'package:flutter_test/flutter_test.dart';
import 'package:flow_md_editor/utils/heading_toggle.dart';

void main() {
  test('adds heading prefix on a plain line', () {
    const text = 'hello world';
    final edit = toggleHeadingLine(text: text, offset: 3, level: 2);
    expect(edit.text, '## hello world');
    expect(edit.caret, edit.text.length);
  });

  test('replaces a different heading level', () {
    const text = '# Title\n\nbody';
    final edit = toggleHeadingLine(text: text, offset: 2, level: 3);
    expect(edit.text, '### Title\n\nbody');
  });

  test('toggles off the same heading level', () {
    const text = '## Title\n\nbody';
    final edit = toggleHeadingLine(text: text, offset: 4, level: 2);
    expect(edit.text, 'Title\n\nbody');
  });

  test('edits only the current line', () {
    const text = 'aaa\nplain\nccc';
    final offset = text.indexOf('plain') + 1;
    final edit = toggleHeadingLine(text: text, offset: offset, level: 1);
    expect(edit.text, 'aaa\n# plain\nccc');
  });
}
