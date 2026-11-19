import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/text_finder.dart';

/// Exact height of every find-bar control (fields, pills, buttons).
const kFindBarControlHeight = 26.0;
const _kRadius = 6.0;
const _kGap = 8.0;
const _kTightGap = 6.0;

class FindBar extends StatefulWidget {
  const FindBar({
    super.key,
    required this.visible,
    required this.onClose,
    required this.onQueryChanged,
    required this.onNext,
    required this.onPrevious,
    required this.matchLabel,
    required this.caseSensitive,
    required this.onCaseSensitiveChanged,
    required this.matchMode,
    required this.onMatchModeChanged,
    this.onReplace,
  });

  final bool visible;
  final VoidCallback onClose;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final String matchLabel;
  final bool caseSensitive;
  final ValueChanged<bool> onCaseSensitiveChanged;
  final FindMatchMode matchMode;
  final ValueChanged<FindMatchMode> onMatchModeChanged;
  final void Function(String replace, {required bool all})? onReplace;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  final _find = TextEditingController();
  final _replace = TextEditingController();
  final _focus = FocusNode();
  bool _replaceMode = false;

  @override
  void didUpdateWidget(covariant FindBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focus.requestFocus(),
      );
    }
  }

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    final c = _XcodeFindColors.of(context);

    final modePill = _ModePill(
      replaceMode: _replaceMode,
      colors: c,
      onChanged: (replace) {
        if (widget.onReplace == null && replace) return;
        setState(() => _replaceMode = replace);
      },
    );

    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AaToggle(
          selected: widget.caseSensitive,
          colors: c,
          onPressed: () =>
              widget.onCaseSensitiveChanged(!widget.caseSensitive),
        ),
        const SizedBox(width: _kTightGap),
        _ContainsPill(
          mode: widget.matchMode,
          colors: c,
          onChanged: widget.onMatchModeChanged,
        ),
        const SizedBox(width: _kTightGap),
        _PrevNextSegment(
          colors: c,
          onPrevious: widget.onPrevious,
          onNext: widget.onNext,
        ),
        const SizedBox(width: _kTightGap),
        _MacButton(
          label: 'Done',
          colors: c,
          onPressed: widget.onClose,
        ),
      ],
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Material(
        color: c.barBg,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: c.barBg,
            border: Border(bottom: BorderSide(color: c.hairline, width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              modePill,
              const SizedBox(width: _kGap),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SearchField(
                      controller: _find,
                      focusNode: _focus,
                      hintText: 'Text',
                      matchLabel: widget.matchLabel,
                      colors: c,
                      onChanged: widget.onQueryChanged,
                      onSubmitted: (_) => widget.onNext(),
                    ),
                    if (_replaceMode && widget.onReplace != null) ...[
                      const SizedBox(height: _kTightGap),
                      _SearchField(
                        controller: _replace,
                        hintText: 'Replace',
                        colors: c,
                        showPlus: false,
                        onSubmitted: (_) =>
                            widget.onReplace!(_replace.text, all: false),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: _kGap),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  trailing,
                  if (_replaceMode && widget.onReplace != null) ...[
                    const SizedBox(height: _kTightGap),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MacButton(
                          label: 'Replace',
                          colors: c,
                          onPressed: () =>
                              widget.onReplace!(_replace.text, all: false),
                        ),
                        const SizedBox(width: _kTightGap),
                        _MacButton(
                          label: 'Replace All',
                          colors: c,
                          onPressed: () =>
                              widget.onReplace!(_replace.text, all: true),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _XcodeFindColors {
  const _XcodeFindColors({
    required this.dark,
    required this.barBg,
    required this.fieldBg,
    required this.border,
    required this.hairline,
    required this.fg,
    required this.muted,
    required this.selectedBg,
    required this.focus,
  });

  final bool dark;
  final Color barBg;
  final Color fieldBg;
  final Color border;
  final Color hairline;
  final Color fg;
  final Color muted;
  final Color selectedBg;
  final Color focus;

  static _XcodeFindColors of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return const _XcodeFindColors(
        dark: true,
        barBg: Color(0xFF2C2C2E),
        fieldBg: Color(0xFF1C1C1E),
        border: Color(0xFF636366),
        hairline: Color(0xFF3A3A3C),
        fg: Color(0xFFF2F2F7),
        muted: Color(0xFF8E8E93),
        selectedBg: Color(0xFF48484A),
        focus: Color(0xFF0A84FF),
      );
    }
    return const _XcodeFindColors(
      dark: false,
      barBg: Color(0xFFF5F5F7),
      fieldBg: Colors.white,
      border: Color(0xFFC6C6C8),
      hairline: Color(0xFFD2D2D7),
      fg: Color(0xFF1C1C1E),
      muted: Color(0xFF8E8E93),
      selectedBg: Color(0xFFE8E8ED),
      focus: Color(0xFF007AFF),
    );
  }
}

const _labelStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w500,
  height: 1.0,
);

RoundedRectangleBorder _controlShape(_XcodeFindColors c, {bool selected = false}) {
  return RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_kRadius),
    side: BorderSide(color: c.border, width: 1),
  );
}

/// Shared 26px bordered chrome for pills and push buttons.
class _MacChrome extends StatelessWidget {
  const _MacChrome({
    required this.colors,
    required this.child,
    this.selected = false,
    this.onPressed,
    this.tooltip,
    this.width,
  });

  final _XcodeFindColors colors;
  final Widget child;
  final bool selected;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(
      height: kFindBarControlHeight,
      width: width,
      child: Material(
        color: selected ? colors.selectedBg : colors.fieldBg,
        elevation: 0,
        shape: _controlShape(colors, selected: selected),
        clipBehavior: Clip.antiAlias,
        child: onPressed == null
            ? child
            : InkWell(
                onTap: onPressed,
                child: child,
              ),
      ),
    );
    return tooltip == null ? box : Tooltip(message: tooltip!, child: box);
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.replaceMode,
    required this.colors,
    required this.onChanged,
  });

  final bool replaceMode;
  final _XcodeFindColors colors;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _MacChrome(
      colors: colors,
      tooltip: 'Find / Replace',
      child: PopupMenuButton<bool>(
        tooltip: '',
        padding: EdgeInsets.zero,
        offset: const Offset(0, kFindBarControlHeight + 2),
        style: const ButtonStyle(
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: WidgetStatePropertyAll(Size.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        onSelected: onChanged,
        itemBuilder: (ctx) => const [
          PopupMenuItem(value: false, height: 32, child: Text('Find')),
          PopupMenuItem(value: true, height: 32, child: Text('Replace')),
        ],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 13, color: colors.fg),
              const SizedBox(width: 4),
              Text(
                replaceMode ? 'Replace' : 'Find',
                style: _labelStyle.copyWith(color: colors.fg),
              ),
              Icon(Icons.unfold_more, size: 14, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContainsPill extends StatelessWidget {
  const _ContainsPill({
    required this.mode,
    required this.colors,
    required this.onChanged,
  });

  final FindMatchMode mode;
  final _XcodeFindColors colors;
  final ValueChanged<FindMatchMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return _MacChrome(
      colors: colors,
      tooltip: 'Match mode',
      child: PopupMenuButton<FindMatchMode>(
        tooltip: '',
        padding: EdgeInsets.zero,
        offset: const Offset(0, kFindBarControlHeight + 2),
        style: const ButtonStyle(
          padding: WidgetStatePropertyAll(EdgeInsets.zero),
          minimumSize: WidgetStatePropertyAll(Size.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        onSelected: onChanged,
        itemBuilder: (ctx) => [
          for (final m in FindMatchMode.values)
            PopupMenuItem(value: m, height: 32, child: Text(m.menuLabel)),
        ],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 2, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(mode.pillLabel, style: _labelStyle.copyWith(color: colors.fg)),
              Icon(Icons.unfold_more, size: 14, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AaToggle extends StatelessWidget {
  const _AaToggle({
    required this.selected,
    required this.colors,
    required this.onPressed,
  });

  final bool selected;
  final _XcodeFindColors colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _MacChrome(
      colors: colors,
      selected: selected,
      tooltip: 'Case Sensitive',
      width: 28,
      onPressed: onPressed,
      child: Center(
        child: Text(
          'Aa',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.0,
            color: selected ? colors.fg : colors.muted,
          ),
        ),
      ),
    );
  }
}

class _PrevNextSegment extends StatelessWidget {
  const _PrevNextSegment({
    required this.colors,
    required this.onPrevious,
    required this.onNext,
  });

  final _XcodeFindColors colors;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('find-prev-next'),
      height: kFindBarControlHeight,
      decoration: BoxDecoration(
        color: colors.fieldBg,
        borderRadius: BorderRadius.circular(_kRadius),
        border: Border.all(color: colors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segCell(
            tooltip: 'Previous',
            icon: Icons.chevron_left,
            onPressed: onPrevious,
          ),
          Container(width: 1, color: colors.border),
          _segCell(
            tooltip: 'Next',
            icon: Icons.chevron_right,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }

  Widget _segCell({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 24,
          height: double.infinity,
          child: Icon(icon, size: 18, color: colors.fg),
        ),
      ),
    );
  }
}

class _MacButton extends StatelessWidget {
  const _MacButton({
    required this.label,
    required this.colors,
    required this.onPressed,
  });

  final String label;
  final _XcodeFindColors colors;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _MacChrome(
      colors: colors,
      tooltip: label,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Center(
          child: Text(label, style: _labelStyle.copyWith(color: colors.fg)),
        ),
      ),
    );
  }
}

/// 26px field: collapsed TextField inside a fixed chrome box so the
/// placeholder and caret sit on the vertical center, never on the border.
class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.colors,
    this.focusNode,
    this.matchLabel = '',
    this.showPlus = true,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final String matchLabel;
  final bool showPlus;
  final _XcodeFindColors colors;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late FocusNode _node;
  bool _owned = false;

  @override
  void initState() {
    super.initState();
    _owned = widget.focusNode == null;
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant _SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _node.removeListener(_handleFocus);
      if (_owned) _node.dispose();
      _owned = widget.focusNode == null;
      _node = widget.focusNode ?? FocusNode();
      _node.addListener(_handleFocus);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_handleFocus);
    if (_owned) _node.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final focused = _node.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      height: kFindBarControlHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.fieldBg,
        borderRadius: BorderRadius.circular(_kRadius),
        border: Border.all(
          color: focused ? c.focus : c.border,
          width: 1,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: c.focus.withValues(alpha: 0.28),
                  blurRadius: 3,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SizedBox(
              height: 16,
              child: TextField(
                controller: widget.controller,
                focusNode: _node,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.0,
                  leadingDistribution: TextLeadingDistribution.even,
                  color: c.fg,
                ),
                strutStyle: const StrutStyle(
                  fontSize: 13,
                  height: 1.0,
                  forceStrutHeight: true,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
                textAlignVertical: TextAlignVertical.center,
                cursorHeight: 13,
                cursorColor: c.focus,
                scrollPadding: EdgeInsets.zero,
                decoration: InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: widget.hintText,
                  hintStyle: TextStyle(
                    fontSize: 13,
                    height: 1.0,
                    leadingDistribution: TextLeadingDistribution.even,
                    color: c.muted,
                  ),
                ),
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
              ),
            ),
          ),
          if (widget.matchLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 2),
              child: Text(
                widget.matchLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1.0,
                  color: c.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          if (widget.showPlus)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Icon(Icons.add, size: 14, color: c.muted),
            ),
        ],
      ),
    );
  }
}

class FindIntent extends Intent {
  const FindIntent();
}

class FindNextIntent extends Intent {
  const FindNextIntent();
}

class FindPreviousIntent extends Intent {
  const FindPreviousIntent();
}

class CloseFindIntent extends Intent {
  const CloseFindIntent();
}

class SaveIntent extends Intent {
  const SaveIntent();
}

class OpenIntent extends Intent {
  const OpenIntent();
}

class NewIntent extends Intent {
  const NewIntent();
}
