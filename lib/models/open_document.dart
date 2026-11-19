import 'package:path/path.dart' as p;

/// One open Markdown tab kept in memory (dirty docs survive switching).
class OpenDocument {
  OpenDocument({
    this.path,
    required this.text,
    this.dirty = false,
    this.selection = 0,
  });

  String? path;
  String text;
  bool dirty;
  int selection;

  String get fileName =>
      path != null ? p.basename(path!) : '未命名.md';

  String get titleLabel => dirty ? '$fileName •' : fileName;
}
