import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Inherited tick incremented whenever the preview [SelectionArea]
/// selection changes, so text blocks can repaint chips/highlights.
class PreviewSelectionScope extends InheritedNotifier<ValueNotifier<int>> {
  const PreviewSelectionScope({
    super.key,
    required ValueNotifier<int> super.notifier,
    required super.child,
  });

  static ValueNotifier<int>? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PreviewSelectionScope>()
        ?.notifier;
  }
}

/// One selection surface for the whole preview: drag can span headings,
/// paragraphs, lists, quotes and tables; Cmd+A selects all; Cmd+C copies
/// with newlines between stacked blocks.
class PreviewSelectionSurface extends StatefulWidget {
  const PreviewSelectionSurface({
    super.key,
    required this.child,
    this.focusNode,
    this.onSelectionChanged,
  });

  final Widget child;
  final FocusNode? focusNode;
  final ValueChanged<String?>? onSelectionChanged;

  @override
  State<PreviewSelectionSurface> createState() =>
      _PreviewSelectionSurfaceState();
}

class _PreviewSelectionSurfaceState extends State<PreviewSelectionSurface> {
  final _tick = ValueNotifier<int>(0);
  final _delegate = _PreviewSelectionDelegate();
  String? _lastPlain;

  @override
  void dispose() {
    _tick.dispose();
    _delegate.dispose();
    super.dispose();
  }

  void _onSelectionChanged(SelectedContent? content) {
    final plain = content?.plainText;
    if (plain == _lastPlain) return;
    _lastPlain = plain;
    _tick.value++;
    widget.onSelectionChanged?.call(content?.plainText);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textSelectionTheme;
    return DefaultSelectionStyle(
      selectionColor: theme.selectionColor,
      cursorColor: theme.cursorColor,
      child: PreviewSelectionScope(
        notifier: _tick,
        child: SelectionArea(
          focusNode: widget.focusNode,
          onSelectionChanged: _onSelectionChanged,
          child: SelectionContainer(
            delegate: _delegate,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Joins selected blocks with newlines when they are stacked vertically
/// (and tabs when they sit side by side, e.g. table cells).
class _PreviewSelectionDelegate extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final pieces = <({SelectedContent content, Selectable selectable})>[
      for (final selectable in selectables)
        if (selectable.getSelectedContent() case final SelectedContent data)
          (content: data, selectable: selectable),
    ];
    if (pieces.isEmpty) return null;
    final buffer = StringBuffer();
    Rect? previous;
    for (final piece in pieces) {
      final rect = _globalRect(piece.selectable);
      if (previous != null && rect != null) {
        if (rect.top > previous.bottom - 4) {
          buffer.write('\n');
        } else if (rect.left > previous.right + 2) {
          buffer.write('\t');
        }
      }
      buffer.write(piece.content.plainText);
      previous = rect ?? previous;
    }
    return SelectedContent(plainText: buffer.toString());
  }

  Rect? _globalRect(Selectable selectable) {
    try {
      final transform = selectable.getTransformTo(null);
      final origin = MatrixUtils.getAsTranslation(transform);
      final offset = origin ??
          Offset(transform.getTranslation().x, transform.getTranslation().y);
      return offset & selectable.size;
    } catch (_) {
      return null;
    }
  }
}
