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
import 'preview_style.dart';

typedef BlockChangedCallback = void Function(int index, String text);

/// FlowMD-like live preview: one active source block, others rendered.
class LivePreview extends StatefulWidget {
  const LivePreview({
    super.key,
    required this.source,
    required this.activeIndex,
    required this.onActiveChanged,
    required this.onBlockChanged,
    required this.documentPath,
    this.maxWidth = 780,
    this.onSourceChanged,
    this.navigationOffset,
    this.navigationRevision = 0,
  });

  final String source;
  final ValueChanged<String>? onSourceChanged;
  final int activeIndex; // -1 = all rendered
  final ValueChanged<int> onActiveChanged;
  final BlockChangedCallback onBlockChanged;
  final String? documentPath;
  final double maxWidth;
  final int? navigationOffset;
  final int navigationRevision;

  @override
  State<LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends State<LivePreview> {
  late List<String> _blocks;
  late String _localSource;
  final _itemKeys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _localSource = widget.source;
    _blocks = splitMarkdownBlocks(widget.source);
  }

  @override
  void didUpdateWidget(covariant LivePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationRevision != widget.navigationRevision &&
        widget.navigationOffset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final index = sourceBlockIndex(
          widget.source,
          _blocks,
          widget.navigationOffset!,
        );
        final target = _itemKeys[index]?.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 220),
            alignment: 0,
          );
        }
      });
    }
    if (oldWidget.source == widget.source || widget.source == _localSource) {
      return;
    }

    // Only external document changes reset boundaries. Local edits may contain
    // blank lines, and must remain one source field until the user leaves it.
    _localSource = widget.source;
    _blocks = splitMarkdownBlocks(widget.source);
    _itemKeys.clear();
  }

  GlobalKey _keyFor(int i) => _itemKeys.putIfAbsent(i, GlobalKey.new);

  void _activate(int index) {
    if (widget.activeIndex != index) {
      widget.onActiveChanged(index);
    }
  }

  void _deactivateIfStill(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.activeIndex == index) {
        widget.onActiveChanged(-1);
      }
    });
  }

  void _onLocalChanged(int index, String value) {
    if (index < 0 || index >= _blocks.length) return;
    final starts = sourceBlockOffsets(_localSource, _blocks);
    final start = starts[index];
    final next = _localSource.replaceRange(
      start,
      start + _blocks[index].length,
      value,
    );
    setState(() {
      _blocks[index] = value;
      _localSource = next;
    });
    if (widget.onSourceChanged != null) {
      widget.onSourceChanged!(next);
    } else {
      widget.onBlockChanged(index, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(_blocks.length, (index) {
              final block = _blocks[index];
              final active = index == widget.activeIndex;
              return KeyedSubtree(
                key: _keyFor(index),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: active
                      ? _SourceBlock(
                          text: block,
                          isDark: isDark,
                          onChanged: (v) => _onLocalChanged(index, v),
                          onBlur: () => _deactivateIfStill(index),
                          onEscapeUp: index > 0
                              ? () => _activate(index - 1)
                              : () => widget.onActiveChanged(-1),
                          onEscapeDown: index < _blocks.length - 1
                              ? () => _activate(index + 1)
                              : () => widget.onActiveChanged(-1),
                        )
                      : _RenderedBlock(
                          source: block,
                          isDark: isDark,
                          documentPath: widget.documentPath,
                          onActivate: () => _activate(index),
                          onToggleTask: (checked) {
                            final from = checked ? '[x]' : '[ ]';
                            final to = checked ? '[ ]' : '[x]';
                            final i = block.toLowerCase().indexOf(
                              from.toLowerCase(),
                            );
                            if (i < 0) return;
                            final next = block.replaceRange(i, i + 3, to);
                            _onLocalChanged(index, next);
                          },
                        ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _SourceBlock extends StatefulWidget {
  const _SourceBlock({
    required this.text,
    required this.isDark,
    required this.onChanged,
    required this.onBlur,
    this.onEscapeUp,
    this.onEscapeDown,
  });

  final String text;
  final bool isDark;
  final ValueChanged<String> onChanged;
  final VoidCallback onBlur;
  final VoidCallback? onEscapeUp;
  final VoidCallback? onEscapeDown;

  @override
  State<_SourceBlock> createState() => _SourceBlockState();
}

class _SourceBlockState extends State<_SourceBlock> {
  late final TextEditingController _c;
  final _focus = FocusNode();
  var _syncing = false;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.text);
    _focus.addListener(_handleFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _handleFocus() {
    if (!_focus.hasFocus) {
      widget.onBlur();
    }
  }

  @override
  void didUpdateWidget(covariant _SourceBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only replace text when external source changed and we are not typing.
    if (!_focus.hasFocus &&
        oldWidget.text != widget.text &&
        _c.text != widget.text) {
      _syncing = true;
      _c.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
      _syncing = false;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_handleFocus);
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final sel = _c.selection;
    if (!sel.isValid) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onBlur();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        sel.baseOffset == 0 &&
        sel.extentOffset == 0 &&
        widget.onEscapeUp != null) {
      widget.onEscapeUp!();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        sel.baseOffset == _c.text.length &&
        sel.extentOffset == _c.text.length &&
        widget.onEscapeDown != null) {
      widget.onEscapeDown!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final border = widget.isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFE6E6E6);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color(0xFF252526).withValues(alpha: 0.55)
            : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Focus(
        onKeyEvent: _onKey,
        child: TextField(
          controller: _c,
          focusNode: _focus,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          style: TextStyle(
            fontFamily: 'Menlo',
            fontSize: 14,
            height: 1.55,
            color: widget.isDark ? Colors.white : const Color(0xFF1F2328),
          ),
          cursorColor: const Color(0xFF0A84FF),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (v) {
            if (_syncing) return;
            widget.onChanged(v);
          },
        ),
      ),
    );
  }
}

class _RenderedBlock extends StatelessWidget {
  const _RenderedBlock({
    required this.source,
    required this.isDark,
    required this.documentPath,
    required this.onActivate,
    required this.onToggleTask,
  });

  final String source;
  final bool isDark;
  final String? documentPath;
  final VoidCallback onActivate;
  final ValueChanged<bool> onToggleTask;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onActivate,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.transparent),
          ),
          child: MarkdownBody(
            data: source.isEmpty ? ' ' : source,
            selectable: false,
            extensionSet: md.ExtensionSet.gitHubFlavored,
            styleSheet: previewStyle(context),
            builders: {'code': _CodeBuilder(isDark: isDark)},
            // ignore: deprecated_member_use
            imageBuilder: (uri, title, alt) {
              final path = uri.toString();
              if (path.startsWith('http://') || path.startsWith('https://')) {
                return Image.network(
                  path,
                  errorBuilder: (_, _, _) {
                    return Text(alt ?? path);
                  },
                );
              }
              final base = documentPath != null
                  ? p.dirname(documentPath!)
                  : Directory.current.path;
              final file = File(p.normalize(p.join(base, path)));
              if (file.existsSync()) {
                return Image.file(
                  file,
                  errorBuilder: (_, _, _) {
                    return Text(alt ?? path);
                  },
                );
              }
              return Text(alt ?? path);
            },
            onTapLink: (text, href, title) async {
              if (href == null) return;
              final uri = Uri.tryParse(href);
              if (uri != null) {
                await launchUrl(uri);
              }
            },
            checkboxBuilder: (checked) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: Checkbox(
                    value: checked,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => onToggleTask(checked),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CodeBuilder extends MarkdownElementBuilder {
  _CodeBuilder({required this.isDark});
  final bool isDark;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final language = element.attributes['class']?.replaceFirst('language-', '');
    final text = element.textContent;
    // Inline code has no class and short content handled by stylesheet.
    if (element.tag == 'code' && language == null) {
      return null;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: HighlightView(
        text,
        language: language ?? 'plaintext',
        theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
        padding: const EdgeInsets.all(12),
        textStyle: const TextStyle(
          fontFamily: 'Menlo',
          fontSize: 13,
          height: 1.45,
        ),
      ),
    );
  }
}
