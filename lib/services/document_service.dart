import 'dart:io';

import 'package:path/path.dart' as p;

class DocumentService {
  Future<String> readFile(String path) => File(path).readAsString();

  Future<void> writeFile(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  Future<String> saveScreenshotAsset({
    required String documentPath,
    required List<int> bytes,
    String extension = 'png',
  }) async {
    final dir = Directory(p.join(p.dirname(documentPath), 'assets'));
    await dir.create(recursive: true);
    final name = 'paste_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes);
    return p.join('assets', name);
  }
}
