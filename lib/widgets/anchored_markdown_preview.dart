import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../utils/block_splitter.dart';
import '../utils/document_outline.dart';
import '../utils/link_reference_defs.dart';
import 'preview_style.dart';
import 'preview_text.dart';

/// Renders Markdown as one keyed widget per top-level source block so the
/// Split preview can scroll to the paragraph that owns a source offset.
///
/// Blocks keep exact [sourceBlockOffsets] ranges from the original document
/// (including fences/tables/lists). Link-reference definitions from the full
/// document are appended to each slice so reference links keep working.
class AnchoredMarkdownPreview extends StatelessWidget {
  const AnchoredMarkdownPreview({
    super.key,
    required this.source,
    required this.blockKeys,
    this.documentPath,
    this.imageBuilder,
    this.onSelectionChanged,
    this.extensionSet,
  });

  final String source;
  final Map<int, GlobalKey> blockKeys;
  final String? documentPath;
  final Widget Function(Uri uri, String? title, String? alt)? imageBuilder;
  final ValueChanged<String?>? onSelectionChanged;
  final md.ExtensionSet? extensionSet;

  @override
  Widget build(BuildContext context) {
    final blocks = splitMarkdownBlocks(source);
    final starts = sourceBlockOffsets(source, blocks);
    final defs = extractLinkReferenceDefinitions(source);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Drop stale keys that no longer exist in this source.
    final live = starts.toSet();
    blockKeys.removeWhere((offset, _) => !live.contains(offset));

    final textBuilder = PreviewTextBuilder();
    return PreviewSelectionSurface(
      onSelectionChanged: onSelectionChanged,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++)
          KeyedSubtree(
            key: blockKeys.putIfAbsent(starts[i], GlobalKey.new),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: MarkdownBody(
                data: defs.isEmpty ? blocks[i] : '${blocks[i]}\n\n$defs',
                styleSheet: previewStyle(context),
                selectable: false,
                extensionSet:
                    extensionSet ?? md.ExtensionSet.gitHubFlavored,
                onTapLink: (text, href, title) async {
                  if (href == null) return;
                  final uri = Uri.tryParse(href);
                  if (uri != null) await launchUrl(uri);
                },
                builders: {
                  'code': _AnchoredCodeBuilder(isDark: isDark),
                  'p': textBuilder,
                  'blockquote': textBuilder,
                  'li': textBuilder,
                  'h1': textBuilder,
                  'h2': textBuilder,
                  'h3': textBuilder,
                  'h4': textBuilder,
                  'h5': textBuilder,
                  'h6': textBuilder,
                },
                // ignore: deprecated_member_use
                imageBuilder: imageBuilder ??
                    (uri, title, alt) =>
                        _defaultImage(uri, title, alt, documentPath),
              ),
            ),
          ),
      ],
    ),
    );
  }
}

Widget _defaultImage(
  Uri uri,
  String? title,
  String? alt,
  String? documentPath,
) {
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text('[外链图片：默认不自动加载]'),
    );
  }
  final base = documentPath != null ? p.dirname(documentPath) : null;
  final filePath =
      base == null ? uri.toString() : p.normalize(p.join(base, uri.path));
  final file = File(filePath);
  if (!file.existsSync()) return Text('[缺少图片: ${uri.path}]');
  return Image.file(file, fit: BoxFit.contain);
}

class _AnchoredCodeBuilder extends MarkdownElementBuilder {
  _AnchoredCodeBuilder({required this.isDark});
  final bool isDark;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (!element.attributes.containsKey('class')) return null;
    final language =
        element.attributes['class']?.replaceFirst('language-', '') ?? '';
    final code = element.textContent;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF282C34) : const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: HighlightView(
              code,
              language: _mapLang(language),
              theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
              padding: EdgeInsets.zero,
              textStyle: const TextStyle(fontFamily: 'Menlo', fontSize: 13),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton(
              tooltip: '复制',
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () => Clipboard.setData(ClipboardData(text: code)),
            ),
          ),
        ],
      ),
    );
  }

  String _mapLang(String language) {
    switch (language) {
      case 'js':
      case 'javascript':
        return 'javascript';
      case 'ts':
      case 'typescript':
        return 'typescript';
      case 'py':
      case 'python':
        return 'python';
      case 'sh':
      case 'shell':
      case 'bash':
        return 'bash';
      case 'yml':
        return 'yaml';
      default:
        return language.isEmpty ? 'plaintext' : language;
    }
  }
}

/// Maps a source caret/scroll offset to the owning block index using exact
/// original ranges (not join-normalized offsets).
int anchoredBlockIndexForOffset(String source, int offset) {
  final blocks = splitMarkdownBlocks(source);
  if (blocks.isEmpty) return 0;
  return sourceBlockIndex(source, blocks, offset.clamp(0, source.length));
}

int? anchoredBlockStartForOffset(String source, int offset) {
  final blocks = splitMarkdownBlocks(source);
  if (blocks.isEmpty) return null;
  final starts = sourceBlockOffsets(source, blocks);
  final idx = sourceBlockIndex(source, blocks, offset.clamp(0, source.length));
  if (idx < 0 || idx >= starts.length) return null;
  return starts[idx];
}
