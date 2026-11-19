enum EditorMode {
  live,
  read,
  source;

  String get label {
    switch (this) {
      case EditorMode.live:
        return 'Split';
      case EditorMode.read:
        return 'Preview';
      case EditorMode.source:
        return 'Editor';
    }
  }

  static EditorMode fromName(String? name) {
    return EditorMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => EditorMode.live,
    );
  }
}
