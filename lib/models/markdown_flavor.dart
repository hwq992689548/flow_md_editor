import 'package:markdown/markdown.dart' as md;

enum MarkdownFlavor {
  gfm,
  commonMark;

  String get label {
    switch (this) {
      case MarkdownFlavor.gfm:
        return 'GitHub Flavored Markdown';
      case MarkdownFlavor.commonMark:
        return 'CommonMark';
    }
  }

  String get shortLabel {
    switch (this) {
      case MarkdownFlavor.gfm:
        return 'GFM';
      case MarkdownFlavor.commonMark:
        return 'CommonMark';
    }
  }

  md.ExtensionSet get extensionSet {
    switch (this) {
      case MarkdownFlavor.gfm:
        return md.ExtensionSet.gitHubFlavored;
      case MarkdownFlavor.commonMark:
        return md.ExtensionSet.commonMark;
    }
  }

  static MarkdownFlavor fromName(String? name) {
    return MarkdownFlavor.values.firstWhere(
      (e) => e.name == name,
      orElse: () => MarkdownFlavor.gfm,
    );
  }
}
