/// How a find query is matched against the document, following Xcode's modes.
enum FindMatchMode { contains, startsWith, fullWord, regex }

extension FindMatchModeLabel on FindMatchMode {
  String get pillLabel {
    switch (this) {
      case FindMatchMode.contains:
        return 'Contains';
      case FindMatchMode.startsWith:
        return 'Starts With';
      case FindMatchMode.fullWord:
        return 'Full Word';
      case FindMatchMode.regex:
        return 'Regex';
    }
  }

  String get menuLabel {
    switch (this) {
      case FindMatchMode.regex:
        return 'Regular Expression';
      default:
        return pillLabel;
    }
  }
}

final _unicodeWord = RegExp(r'\w', unicode: true);

class TextHit {
  const TextHit(this.start, this.end);
  final int start;
  final int end;
  int get length => end - start;
}

/// True if [index] is a letter, digit, underscore, or CJK/letter-like code unit.
bool isWordChar(String text, int index) {
  if (index < 0 || index >= text.length) return false;
  final c = text.codeUnitAt(index);
  if (c >= 48 && c <= 57) return true; // 0-9
  if (c >= 65 && c <= 90) return true; // A-Z
  if (c >= 97 && c <= 122) return true; // a-z
  if (c == 95) return true; // _
  if (c >= 0x80) {
    return _unicodeWord.hasMatch(text[index]);
  }
  return false;
}

List<TextHit> findTextHits(
  String text,
  String query, {
  required bool caseSensitive,
  required FindMatchMode mode,
}) {
  if (query.isEmpty) return const [];
  if (mode == FindMatchMode.regex) {
    try {
      final re = RegExp(query, caseSensitive: caseSensitive, unicode: true);
      return [
        for (final m in re.allMatches(text))
          if (m.end > m.start) TextHit(m.start, m.end),
      ];
    } on FormatException {
      return const [];
    }
  }

  final hay = caseSensitive ? text : text.toLowerCase();
  final needle = caseSensitive ? query : query.toLowerCase();
  if (needle.isEmpty) return const [];
  final hits = <TextHit>[];
  var from = 0;
  while (true) {
    final i = hay.indexOf(needle, from);
    if (i < 0) break;
    final end = i + needle.length;
    var ok = true;
    if (mode == FindMatchMode.fullWord) {
      ok = !isWordChar(text, i - 1) && !isWordChar(text, end);
    } else if (mode == FindMatchMode.startsWith) {
      ok = !isWordChar(text, i - 1);
    }
    if (ok) hits.add(TextHit(i, end));
    from = i + needle.length;
    if (from >= hay.length) break;
  }
  return hits;
}

String replaceAllHits(
  String text,
  String query,
  String replacement, {
  required bool caseSensitive,
  required FindMatchMode mode,
}) {
  final hits = findTextHits(
    text,
    query,
    caseSensitive: caseSensitive,
    mode: mode,
  );
  if (hits.isEmpty) return text;
  var next = text;
  for (final hit in hits.reversed) {
    next = next.replaceRange(hit.start, hit.end, replacement);
  }
  return next;
}
