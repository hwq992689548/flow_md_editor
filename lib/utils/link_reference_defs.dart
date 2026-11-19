/// Collects CommonMark link-reference definition lines from [source],
/// skipping fenced code so they can be reattached when rendering a slice.
String extractLinkReferenceDefinitions(String source) {
  if (source.isEmpty) return '';
  final lines = source.split('\n');
  final out = <String>[];
  String? fence;
  var fenceLength = 0;
  final def = RegExp(r'^ {0,3}\[[^\]\n]+\]:\s+\S');
  for (final raw in lines) {
    final line = raw.replaceAll('\r', '');
    final marker = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$').firstMatch(line);
    if (fence != null) {
      if (marker != null &&
          marker[1]![0] == fence &&
          marker[1]!.length >= fenceLength &&
          marker[2]!.trim().isEmpty) {
        fence = null;
      }
      continue;
    }
    if (marker != null) {
      fence = marker[1]![0];
      fenceLength = marker[1]!.length;
      continue;
    }
    if (def.hasMatch(line)) out.add(line);
  }
  return out.join('\n');
}
