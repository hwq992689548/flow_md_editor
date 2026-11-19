import "dart:async";
import "dart:io";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "package:flutter_highlight/flutter_highlight.dart";
import "package:flutter_highlight/themes/atom-one-dark.dart";
import "package:flutter_highlight/themes/atom-one-light.dart";
import "package:flutter_markdown/flutter_markdown.dart";
import "package:markdown/markdown.dart" as md;
import "package:path/path.dart" as p;
import "package:shared_preferences/shared_preferences.dart";
import "package:url_launcher/url_launcher.dart";

import "../models/editor_mode.dart";
import "../models/markdown_flavor.dart";
import "../models/open_document.dart";
import "../services/app_settings.dart";
import "../services/document_service.dart";
import "../services/html_export.dart";
import "../utils/block_splitter.dart";
import "../utils/document_outline.dart";
import "../utils/heading_toggle.dart";
import "../utils/text_finder.dart";
import "../widgets/preview_style.dart";
import "../widgets/preview_text.dart";
import "../widgets/heading_anchor.dart";
import "../widgets/find_bar.dart";
import "../widgets/outline_sidebar.dart";
import "../widgets/anchored_markdown_preview.dart";
import "../widgets/source_editor.dart";

class EditorHome extends StatefulWidget {
  const EditorHome({super.key, required this.settings});
  final AppSettings settings;
  SharedPreferences get prefs => settings.prefs;
  @override
  State<EditorHome> createState() => _EditorHomeState();
}

class _EditorHomeState extends State<EditorHome> {
  static const _modeKey = "editor_mode";
  static const _widthKey = "body_width";
  static const _wrapKey = "soft_wrap";
  static const _openPathsKey = "open_doc_paths";
  static const _activePathKey = "active_doc_path";
  static const _flavorKey = "markdown_flavor";
  static const _autoReloadKey = "auto_reload_preview";

  final _fileIO = DocumentService();
  final _controller = HighlightingTextController();
  final _focusNode = FocusNode();

  final List<OpenDocument> _openDocs = [];
  int _activeIndex = 0;

  EditorMode _mode = EditorMode.live;
  bool _wrap = true;
  double _bodyWidth = 780;
  bool _findVisible = false;
  String _findQuery = "";
  int _matchIndex = 0;
  List<TextHit> _matches = const [];
  bool _findCaseSensitive = false;
  FindMatchMode _findMatchMode = FindMatchMode.contains;
  int _activeBlock = -1;
  String _lastText = "";
  int? _headingOffset;
  final _readKeys = <int, GlobalKey>{};
  final _blockKeys = <int, GlobalKey>{};
  final _sourceScroll = ScrollController();
  final _previewScroll = ScrollController();
  double _splitRatio = 0.5;
  String _previewSource = "";
  Timer? _previewDebounce;
  int? _lastEnsuredBlockStart;
  MarkdownFlavor _flavor = MarkdownFlavor.gfm;
  bool _autoReloadPreview = true;
  bool _previewHtmlTab = false;

  String? get _path =>
      _openDocs.isEmpty ? null : _openDocs[_activeIndex].path;

  bool get _dirty =>
      _openDocs.isEmpty ? false : _openDocs[_activeIndex].dirty;

  double get _fontSize => widget.settings.fontSize.value;
  double get _sourceLineHeight => _fontSize * 1.5;


  set _dirty(bool value) {
    if (_openDocs.isEmpty) return;
    _openDocs[_activeIndex].dirty = value;
  }

  @override
  void initState() {
    super.initState();
    _mode = EditorMode.fromName(widget.prefs.getString(_modeKey));
    _wrap = widget.prefs.getBool(_wrapKey) ?? true;
    _bodyWidth = widget.prefs.getDouble(_widthKey) ?? 780;
    _flavor = MarkdownFlavor.fromName(widget.prefs.getString(_flavorKey));
    _autoReloadPreview = widget.prefs.getBool(_autoReloadKey) ?? true;
    _bootstrapDocuments();
    _controller.addListener(_onTextChanged);
  }

  void _bootstrapDocuments() {
    final paths = widget.prefs.getStringList(_openPathsKey) ?? const <String>[];
    final restored = <OpenDocument>[];
    for (final path in paths) {
      try {
        final file = File(path);
        if (!file.existsSync()) continue;
        restored.add(
          OpenDocument(path: path, text: file.readAsStringSync(), dirty: false),
        );
      } catch (_) {
        // Skip unreadable paths quietly.
      }
    }
    if (restored.isEmpty) {
      restored.add(OpenDocument(text: _welcome, dirty: false));
    }
    _openDocs
      ..clear()
      ..addAll(restored);
    final activePath = widget.prefs.getString(_activePathKey);
    var idx = 0;
    if (activePath != null) {
      final found = _openDocs.indexWhere((d) => d.path == activePath);
      if (found >= 0) idx = found;
    }
    _activeIndex = idx;
    _applyActiveToEditor(resetPreview: true);
  }

  void _flushEditorToActive() {
    if (_openDocs.isEmpty) return;
    final doc = _openDocs[_activeIndex];
    doc.text = _controller.text;
    final sel = _controller.selection;
    doc.selection = sel.isValid
        ? sel.extentOffset.clamp(0, doc.text.length)
        : 0;
  }

  void _applyActiveToEditor({bool resetPreview = false}) {
    if (_openDocs.isEmpty) return;
    final doc = _openDocs[_activeIndex];
    _controller.removeListener(_onTextChanged);
    _controller.value = TextEditingValue(
      text: doc.text,
      selection: TextSelection.collapsed(
        offset: doc.selection.clamp(0, doc.text.length),
      ),
    );
    _controller.addListener(_onTextChanged);
    _lastText = doc.text;
    if (resetPreview || _previewSource != doc.text) {
      _previewSource = doc.text;
    }
    _activeBlock = -1;
    _headingOffset = null;
    _lastEnsuredBlockStart = null;
    _blockKeys.clear();
    _readKeys.clear();
    _matches = const [];
    _matchIndex = 0;
  }

  Future<void> _persistOpenPaths() async {
    final paths = [
      for (final d in _openDocs)
        if (d.path != null) d.path!,
    ];
    await widget.prefs.setStringList(_openPathsKey, paths);
    final active = _path;
    if (active != null) {
      await widget.prefs.setString(_activePathKey, active);
    } else {
      await widget.prefs.remove(_activePathKey);
    }
  }

  void _activateDocument(int index) {
    if (index < 0 || index >= _openDocs.length || index == _activeIndex) {
      return;
    }
    _flushEditorToActive();
    setState(() {
      _activeIndex = index;
      _applyActiveToEditor(resetPreview: true);
    });
    _persistOpenPaths();
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _sourceScroll.dispose();
    _previewScroll.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final textChanged = _controller.text != _lastText;
    if (textChanged) {
      _lastText = _controller.text;
      if (_openDocs.isNotEmpty) {
        _openDocs[_activeIndex].text = _controller.text;
      }
      setState(() {
        _dirty = true;
        _headingOffset = null;
      });
      _schedulePreviewUpdate();
    }
    _refreshMatches(keepIndex: true);
    _syncActiveBlockFromSelection();
    // Never mutate selection/composing here (IME-safe).
    // Split preview sync is manual via the 定位 button — no per-caret/scroll follow.
  }

  void _schedulePreviewUpdate() {
    if (!_autoReloadPreview) return;
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      if (_previewSource == _controller.text) return;
      setState(() => _previewSource = _controller.text);
    });
  }

  void _reloadPreview() {
    _previewDebounce?.cancel();
    setState(() => _previewSource = _controller.text);
  }

  /// Manual Split sync: scroll the right preview to the block for [charOffset].
  void _ensurePreviewForSourceOffset(int charOffset, {bool force = false}) {
    if (_mode != EditorMode.live) return;
    // Keys belong to the rendered preview source.
    final text = _previewSource.isEmpty ? _controller.text : _previewSource;
    if (text.isEmpty) return;
    final start = anchoredBlockStartForOffset(text, charOffset);
    if (start == null) return;
    if (!force && start == _lastEnsuredBlockStart) {
      final key = _blockKeys[start];
      if (key?.currentContext != null &&
          _isContextVisible(key!.currentContext!)) {
        return;
      }
    }
    void run() {
      if (!mounted || _mode != EditorMode.live) return;
      final key = _blockKeys[start];
      final ctx = key?.currentContext;
      if (ctx == null) return;
      if (!force && _isContextVisible(ctx)) {
        _lastEnsuredBlockStart = start;
        return;
      }
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 160),
        alignment: 0.08,
        curve: Curves.easeOut,
      ).whenComplete(() {
        _lastEnsuredBlockStart = start;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }

  bool _isContextVisible(BuildContext context, {double padding = 12}) {
    final object = context.findRenderObject();
    if (object is! RenderBox || !object.hasSize || !object.attached) {
      return false;
    }
    final viewport = RenderAbstractViewport.maybeOf(object);
    if (viewport == null) return false;
    final top = viewport.getOffsetToReveal(object, 0.0).offset;
    final bottom = viewport.getOffsetToReveal(object, 1.0).offset;
    if (!_previewScroll.hasClients) return false;
    final viewTop = _previewScroll.offset;
    final viewBottom = viewTop + _previewScroll.position.viewportDimension;
    // Visible if the block overlaps the viewport (with a little padding).
    return bottom >= viewTop + padding && top <= viewBottom - padding;
  }

  void _locatePreviewToCaret() {
    final sel = _controller.selection;
    final offset = sel.isValid
        ? sel.extentOffset.clamp(0, _controller.text.length)
        : 0;
    _ensurePreviewForSourceOffset(offset, force: true);
  }

  void _syncActiveBlockFromSelection() {
    // Live mode owns active block via click/focus; don't fight it from caret.
    if (_mode != EditorMode.source) return;
    final blocks = splitMarkdownBlocks(_controller.text);
    final offset = _controller.selection.baseOffset.clamp(
      0,
      _controller.text.length,
    );
    final idx = blockIndexForOffset(blocks, offset);
    if (idx != _activeBlock) setState(() => _activeBlock = idx);
  }

  Future<void> _setMode(EditorMode mode) async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _mode = mode;
      _activeBlock = -1;
      if (mode == EditorMode.live || mode == EditorMode.read) {
        _previewSource = _controller.text;
      }
      if (mode == EditorMode.live) {
        _lastEnsuredBlockStart = null;
      }
    });
    await widget.prefs.setString(_modeKey, mode.name);
  }

  Future<void> _newDoc() async {
    _flushEditorToActive();
    setState(() {
      _openDocs.add(OpenDocument(text: "", dirty: false));
      _activeIndex = _openDocs.length - 1;
      _applyActiveToEditor(resetPreview: true);
    });
    await _persistOpenPaths();
  }

  Future<void> _openDoc() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ["md", "markdown"],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    _flushEditorToActive();
    var activated = _activeIndex;
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      final existing = _openDocs.indexWhere((d) => d.path == path);
      if (existing >= 0) {
        activated = existing;
        continue;
      }
      final text = await _fileIO.readFile(path);
      _openDocs.add(OpenDocument(path: path, text: text, dirty: false));
      activated = _openDocs.length - 1;
    }
    setState(() {
      _activeIndex = activated;
      _applyActiveToEditor(resetPreview: true);
    });
    await _persistOpenPaths();
  }

  Future<bool> _saveDoc({bool saveAs = false}) async {
    _flushEditorToActive();
    var path = _path;
    if (path == null || saveAs) {
      path = await FilePicker.platform.saveFile(
        dialogTitle: "保存 Markdown",
        fileName: path != null ? p.basename(path) : "untitled.md",
        type: FileType.custom,
        allowedExtensions: const ["md", "markdown"],
      );
      if (path == null) return false;
      if (!path.endsWith(".md") && !path.endsWith(".markdown")) {
        path = "$path.md";
      }
    }
    await _fileIO.writeFile(path, _controller.text);
    setState(() {
      final doc = _openDocs[_activeIndex];
      doc.path = path;
      doc.text = _controller.text;
      doc.dirty = false;
    });
    await _persistOpenPaths();
    return true;
  }

  Future<void> _reloadFromDisk() async {
    final path = _path;
    if (path == null) return;
    if (_dirty) {
      final ok =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("从磁盘重新载入"),
              content: const Text("未保存的修改会被丢弃，确定继续？"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("取消"),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("重新载入"),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;
    }
    final text = await _fileIO.readFile(path);
    setState(() {
      _controller.text = text;
      _openDocs[_activeIndex].text = text;
      _openDocs[_activeIndex].dirty = false;
      _lastText = text;
      _previewSource = text;
    });
  }

  Future<bool> _confirmCloseDocument(int index) async {
    final doc = _openDocs[index];
    if (!doc.dirty) return true;
    // Temporarily show that doc's name in dialog.
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("关闭 ${doc.fileName}"),
        content: const Text("有未保存的修改，要先保存吗？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, "cancel"),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, "discard"),
            child: const Text("不保存"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, "save"),
            child: const Text("保存"),
          ),
        ],
      ),
    );
    if (r == "cancel" || r == null) return false;
    if (r == "discard") return true;
    // Save that document: activate if needed then save.
    if (index != _activeIndex) {
      _flushEditorToActive();
      setState(() {
        _activeIndex = index;
        _applyActiveToEditor(resetPreview: true);
      });
    }
    return _saveDoc();
  }

  Future<void> _closeDocument(int index) async {
    if (index < 0 || index >= _openDocs.length) return;
    if (!await _confirmCloseDocument(index)) return;
    _flushEditorToActive();
    setState(() {
      _openDocs.removeAt(index);
      if (_openDocs.isEmpty) {
        _openDocs.add(OpenDocument(text: "", dirty: false));
        _activeIndex = 0;
      } else if (_activeIndex > index) {
        _activeIndex -= 1;
      } else if (_activeIndex >= _openDocs.length) {
        _activeIndex = _openDocs.length - 1;
      }
      _applyActiveToEditor(resetPreview: true);
    });
    await _persistOpenPaths();
  }

  Future<void> _exportHtml() async {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final html = exportSelfContainedHtml(
      title: _path != null ? p.basename(_path!) : "untitled",
      markdownSource: _controller.text,
      dark: dark,
      extensionSet: _flavor.extensionSet,
    );
    final out = await FilePicker.platform.saveFile(
      dialogTitle: "导出 HTML",
      fileName: "${p.basenameWithoutExtension(_path ?? "untitled")}.html",
      type: FileType.custom,
      allowedExtensions: const ["html"],
    );
    if (out == null) return;
    final path = out.endsWith(".html") ? out : "$out.html";
    await File(path).writeAsString(html);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("已导出：$path")));
  }

  void _refreshMatches({bool keepIndex = false}) {
    final q = _findQuery;
    if (q.isEmpty) {
      // Avoid setState on every selection drag when find is idle.
      if (_matches.isEmpty && _matchIndex == 0) return;
      setState(() {
        _matches = const [];
        _matchIndex = 0;
      });
      return;
    }
    final list = findTextHits(
      _controller.text,
      q,
      caseSensitive: _findCaseSensitive,
      mode: _findMatchMode,
    );
    setState(() {
      _matches = list;
      if (!keepIndex) {
        _matchIndex = 0;
      } else if (_matchIndex >= list.length) {
        _matchIndex = list.isEmpty ? 0 : list.length - 1;
      }
    });
  }

  void _gotoMatch(int delta) {
    if (_matches.isEmpty) return;
    setState(() {
      _matchIndex = (_matchIndex + delta) % _matches.length;
      if (_matchIndex < 0) _matchIndex += _matches.length;
    });
    final hit = _matches[_matchIndex];
    final start = hit.start;
    final end = hit.end;
    _controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    // Split stays Split; Preview jumps to Editor so the match is editable.
    if (_mode == EditorMode.read) {
      _setMode(EditorMode.source);
    }
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollSourceToOffset(start);
      // Split right pane: user presses 定位 when they want preview sync.
    });
  }

  void _replace({required String replacement, required bool all}) {
    if (_findQuery.isEmpty) return;
    if (all) {
      final next = replaceAllHits(
        _controller.text,
        _findQuery,
        replacement,
        caseSensitive: _findCaseSensitive,
        mode: _findMatchMode,
      );
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    } else {
      if (_matches.isEmpty) return;
      final hit = _matches[_matchIndex];
      final next = _controller.text.replaceRange(hit.start, hit.end, replacement);
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: hit.start + replacement.length),
      );
    }
    _refreshMatches();
  }

  void _applyHeading(int level) {
    final sel = _controller.selection;
    final offset = sel.isValid
        ? sel.extentOffset.clamp(0, _controller.text.length)
        : 0;
    final edit = toggleHeadingLine(
      text: _controller.text,
      offset: offset,
      level: level,
    );
    _controller.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.caret),
    );
    _focusNode.requestFocus();
  }

  void _wrapSelection(String left, String right) {
    final sel = _controller.selection;
    if (!sel.isValid) return;
    final text = _controller.text;
    final start = sel.start;
    final end = sel.end;
    final selected = text.substring(start, end);
    final next = text.replaceRange(start, end, "$left$selected$right");
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection(
        baseOffset: start + left.length,
        extentOffset: start + left.length + selected.length,
      ),
    );
  }


  String get _title =>
      _openDocs.isEmpty ? "未命名.md" : _openDocs[_activeIndex].titleLabel;

  @override
  Widget build(BuildContext context) {
    final matchLabel = _findQuery.isEmpty
        ? ""
        : (_matches.isEmpty ? "0/0" : "${_matchIndex + 1}/${_matches.length}");

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
            const FindIntent(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            const FindIntent(),
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true):
            const FindNextIntent(),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true):
            const FindNextIntent(),
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true, shift: true):
            const FindPreviousIntent(),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true, shift: true):
            const FindPreviousIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            const SaveIntent(),
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true):
            const OpenIntent(),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            const NewIntent(),
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
            const _BoldIntent(),
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true):
            const _ItalicIntent(),
        const SingleActivator(LogicalKeyboardKey.escape):
            const CloseFindIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          FindIntent: CallbackAction<FindIntent>(
            onInvoke: (_) {
              setState(() => _findVisible = true);
              return null;
            },
          ),
          FindNextIntent: CallbackAction<FindNextIntent>(
            onInvoke: (_) {
              _gotoMatch(1);
              return null;
            },
          ),
          FindPreviousIntent: CallbackAction<FindPreviousIntent>(
            onInvoke: (_) {
              _gotoMatch(-1);
              return null;
            },
          ),
          SaveIntent: CallbackAction<SaveIntent>(
            onInvoke: (_) {
              _saveDoc();
              return null;
            },
          ),
          OpenIntent: CallbackAction<OpenIntent>(
            onInvoke: (_) {
              _openDoc();
              return null;
            },
          ),
          NewIntent: CallbackAction<NewIntent>(
            onInvoke: (_) {
              _newDoc();
              return null;
            },
          ),
          _BoldIntent: CallbackAction<_BoldIntent>(
            onInvoke: (_) {
              _wrapSelection("**", "**");
              return null;
            },
          ),
          _ItalicIntent: CallbackAction<_ItalicIntent>(
            onInvoke: (_) {
              _wrapSelection("*", "*");
              return null;
            },
          ),
          CloseFindIntent: CallbackAction<CloseFindIntent>(
            onInvoke: (_) {
              if (_findVisible) {
                setState(() => _findVisible = false);
                _focusNode.requestFocus();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Row(
              children: [
                _sidebar(),
                Expanded(
                  child: Column(
                    children: [
                      _topBar(),
                      FindBar(
                        visible: _findVisible,
                        matchLabel: matchLabel,
                        caseSensitive: _findCaseSensitive,
                        matchMode: _findMatchMode,
                        onCaseSensitiveChanged: (v) {
                          setState(() => _findCaseSensitive = v);
                          _refreshMatches(keepIndex: true);
                        },
                        onMatchModeChanged: (m) {
                          setState(() => _findMatchMode = m);
                          _refreshMatches(keepIndex: true);
                        },
                        onClose: () {
                          setState(() => _findVisible = false);
                          _focusNode.requestFocus();
                        },
                        onQueryChanged: (q) {
                          _findQuery = q;
                          _refreshMatches();
                        },
                        onNext: () => _gotoMatch(1),
                        onPrevious: () => _gotoMatch(-1),
                        onReplace: (r, {required all}) =>
                            _replace(replacement: r, all: all),
                      ),
                      Expanded(child: _documentPane()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int get _wordCount => documentWordCount(_controller.text);

  Widget _sidebar() => OutlineSidebar(
    documents: _openDocs,
    activeIndex: _activeIndex,
    wordCount: _wordCount,
    headings: extractOutline(
      _controller.text,
    ).where((h) => h.level <= 3).toList(),
    activeOffset: _headingOffset,
    onHeadingTap: _navigateHeading,
    onOpen: _openDoc,
    onNew: _newDoc,
    onSelectDocument: _activateDocument,
    onCloseDocument: _closeDocument,
  );

  Widget _vSep(Color color) {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: color,
    );
  }

  Widget _dropdownChip<T>({
    required T value,
    required List<T> values,
    required String Function(T) labelOf,
    required ValueChanged<T> onSelected,
    required String tooltip,
    String Function(T)? chipLabelOf,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? const Color(0xFFD1D1D6) : const Color(0xFF3A3A3C);
    final chipBg = dark ? const Color(0xFF1C1C1E) : const Color(0xFFE8E8ED);
    final chipSide = dark ? const Color(0xFF48484A) : const Color(0xFFD2D2D7);
    return PopupMenuButton<T>(
      tooltip: tooltip,
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (ctx) => [
        for (final v in values)
          PopupMenuItem<T>(value: v, child: Text(labelOf(v))),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: chipSide),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              (chipLabelOf ?? labelOf)(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: fg),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: fg),
          ],
        ),
      ),
    );
  }

  Widget _headingBtn(int level, Color fg) {
    return Tooltip(
      message: 'H$level',
      child: InkWell(
        onTap: () => _applyHeading(level),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            'H$level',
            key: ValueKey('heading-h$level'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barBg = dark ? const Color(0xFF2C2C2E) : const Color(0xFFF5F5F7);
    final barBorder = dark ? const Color(0xFF3A3A3C) : const Color(0xFFD2D2D7);
    final segBg = dark ? const Color(0xFF1C1C1E) : const Color(0xFFE8E8ED);
    final segSelected = dark ? const Color(0xFF48484A) : Colors.white;
    final segFg = dark ? const Color(0xFFAEAEB2) : const Color(0xFF6C6C70);
    final segSide = dark ? const Color(0xFF48484A) : const Color(0xFFD2D2D7);
    final titleColor = dark ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E);
    final themeMode = widget.settings.themeMode.value;
    final fontSize = widget.settings.fontSize.value;

    final segStyle = SegmentedButton.styleFrom(
      visualDensity: const VisualDensity(horizontal: -2, vertical: -1),
      backgroundColor: segBg,
      selectedBackgroundColor: segSelected,
      selectedForegroundColor: dark ? Colors.white : const Color(0xFF1C1C1E),
      foregroundColor: segFg,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      side: BorderSide(color: segSide),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 10),
    );

    Widget leftFit(Widget child) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: child,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: barBg,
        border: Border(bottom: BorderSide(color: barBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: titleColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    flex: 2,
                    child: leftFit(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _dropdownChip<MarkdownFlavor>(
                            value: _flavor,
                            values: MarkdownFlavor.values,
                            labelOf: (f) => f.label,
                            chipLabelOf: (f) => f.shortLabel,
                            tooltip: 'Markdown 方言',
                            onSelected: (f) async {
                              setState(() => _flavor = f);
                              await widget.prefs.setString(_flavorKey, f.name);
                            },
                          ),
                          const SizedBox(width: 10),
                          _dropdownChip<ThemeMode>(
                            value: themeMode,
                            values: ThemeMode.values,
                            labelOf: AppSettings.themeModeLabel,
                            tooltip: '主题',
                            onSelected: widget.settings.setThemeMode,
                          ),
                          const SizedBox(width: 16),
                          SegmentedButton<EditorMode>(
                            showSelectedIcon: false,
                            style: segStyle,
                            segments: const [
                              ButtonSegment(
                                value: EditorMode.live,
                                label: Text('Split'),
                                tooltip: '左右分栏：源码 | 预览',
                              ),
                              ButtonSegment(
                                value: EditorMode.source,
                                label: Text('Editor'),
                              ),
                              ButtonSegment(
                                value: EditorMode.read,
                                label: Text('Preview'),
                              ),
                            ],
                            selected: {_mode},
                            onSelectionChanged: (s) => _setMode(s.first),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, thickness: 1, color: barBorder),
          SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: leftFit(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '查找 (⌘F / Ctrl+F)',
                            onPressed: () =>
                                setState(() => _findVisible = true),
                            icon: const Icon(Icons.search, size: 20),
                            visualDensity: VisualDensity.compact,
                          ),
                          _vSep(segSide),
                          for (var i = 1; i <= 6; i++)
                            _headingBtn(i, titleColor),
                          _vSep(segSide),
                          Container(
                            height: 30,
                            decoration: BoxDecoration(
                              color: segBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: segSide),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: '减小字号',
                                  onPressed:
                                      fontSize <= AppSettings.minFontSize
                                      ? null
                                      : () =>
                                            widget.settings.bumpFontSize(-1),
                                  icon: Icon(
                                    Icons.remove,
                                    size: 16,
                                    color: segFg,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 30,
                                    minHeight: 30,
                                  ),
                                ),
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '${fontSize.round()}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: titleColor,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '增大字号',
                                  onPressed:
                                      fontSize >= AppSettings.maxFontSize
                                      ? null
                                      : () =>
                                            widget.settings.bumpFontSize(1),
                                  icon: Icon(
                                    Icons.add,
                                    size: 16,
                                    color: segFg,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 30,
                                    minHeight: 30,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: "文档设置",
                    icon: const Icon(Icons.tune, size: 20),
                    onSelected: (v) async {
                      switch (v) {
                        case "new":
                          await _newDoc();
                        case "open":
                          await _openDoc();
                        case "save":
                          await _saveDoc();
                        case "saveAs":
                          await _saveDoc(saveAs: true);
                        case "reload":
                          await _reloadFromDisk();
                        case "export":
                          await _exportHtml();
                        case "wrap":
                          setState(() => _wrap = !_wrap);
                          await widget.prefs.setBool(_wrapKey, _wrap);
                        case "width":
                          await _editWidth();
                      }
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: "new", child: Text("新建")),
                      PopupMenuItem(value: "open", child: Text("打开…")),
                      PopupMenuItem(value: "save", child: Text("保存")),
                      PopupMenuItem(value: "saveAs", child: Text("另存为…")),
                      PopupMenuItem(
                        value: "reload",
                        child: Text("从磁盘重新载入"),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: "export",
                        child: Text("导出 HTML"),
                      ),
                      PopupMenuItem(
                        value: "wrap",
                        child: Text("切换自动换行"),
                      ),
                      PopupMenuItem(
                        value: "width",
                        child: Text("正文宽度…"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _documentPane() {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: _buildBody(),
    );
  }

  void _navigateHeading(DocumentHeading heading) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _activeBlock = -1;
      _headingOffset = heading.offset;
    });
    if (_mode == EditorMode.source || _mode == EditorMode.live) {
      _controller.selection = TextSelection.collapsed(offset: heading.offset);
      _focusNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollSourceToOffset(heading.offset);
        // Split: outline moves left caret/scroll only; use 定位 for right.
      });
    } else if (_mode == EditorMode.read) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _readKeys[heading.offset]?.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 220),
            alignment: 0,
          );
        }
      });
    }
  }

  void _scrollSourceToOffset(int offset) {
    if (!_sourceScroll.hasClients) return;
    final text = _controller.text;
    final clamped = offset.clamp(0, text.length);
    final line = '\n'.allMatches(text.substring(0, clamped)).length;
    final target = (line * _sourceLineHeight).clamp(
      0.0,
      _sourceScroll.position.maxScrollExtent,
    );
    _sourceScroll.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _editWidth() async {
    final ctrl = TextEditingController(text: _bodyWidth.toStringAsFixed(0));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("正文宽度"),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: "px"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(ctrl.text.trim())),
            child: const Text("确定"),
          ),
        ],
      ),
    );
    if (v == null) return;
    setState(() => _bodyWidth = v.clamp(480, 1400));
    await widget.prefs.setDouble(_widthKey, _bodyWidth);
  }

  Widget _buildBody() {
    switch (_mode) {
      case EditorMode.source:
        return _sourceEditor(scrollController: _sourceScroll);
      case EditorMode.read:
        return SingleChildScrollView(
          controller: _previewScroll,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 60),
          child: _markdownView(
            _controller.text,
            editableTasks: false,
            anchorHeadings: true,
          ),
        );
      case EditorMode.live:
        return _splitView();
    }
  }

  Widget _splitView() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? const Color(0xFF9399A8) : const Color(0xFF6C6C70);
    final barBg = dark ? const Color(0xFF222426) : const Color(0xFFF3F3F5);
    final barBorder = dark ? const Color(0xFF3A3A3C) : const Color(0xFFD2D2D7);
    final paneBg = dark ? const Color(0xFF1C1C1E) : Colors.white;
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        final divider = 5.0;
        final left = (total * _splitRatio).clamp(180.0, total - 180.0 - divider);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: left,
              child: _sourceEditor(scrollController: _sourceScroll),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _splitRatio =
                        ((_splitRatio * total + details.delta.dx) / total)
                            .clamp(0.22, 0.78);
                  });
                },
                child: Container(
                  width: divider,
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: paneBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 42,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: barBg,
                          border: Border(
                            bottom: BorderSide(color: barBorder),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                    Checkbox(
                                      key: const ValueKey(
                                        'auto-reload-preview',
                                      ),
                                      value: _autoReloadPreview,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                      onChanged: (v) async {
                                        final next = v ?? true;
                                        setState(
                                          () => _autoReloadPreview = next,
                                        );
                                        await widget.prefs.setBool(
                                          _autoReloadKey,
                                          next,
                                        );
                                        if (next) _reloadPreview();
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '自动刷新预览',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: muted,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    SegmentedButton<bool>(
                                      showSelectedIcon: false,
                                      style: SegmentedButton.styleFrom(
                                        visualDensity: const VisualDensity(
                                          horizontal: -2,
                                          vertical: -2,
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 12,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                      ),
                                      segments: const [
                                        ButtonSegment(
                                          value: false,
                                          label: Text('Preview'),
                                        ),
                                        ButtonSegment(
                                          value: true,
                                          label: Text('HTML'),
                                        ),
                                      ],
                                      selected: {_previewHtmlTab},
                                      onSelectionChanged: (s) {
                                        setState(
                                          () => _previewHtmlTab = s.first,
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 16),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 200,
                                      ),
                                      child: Text(
                                        _title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: muted,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '刷新预览',
                                      onPressed: _reloadPreview,
                                      icon: const Icon(Icons.refresh, size: 18),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Tooltip(
                                message: '定位到编辑位置',
                                child: TextButton.icon(
                                  onPressed: () {
                                    if (_previewHtmlTab) {
                                      setState(() => _previewHtmlTab = false);
                                    }
                                    _locatePreviewToCaret();
                                  },
                                  icon: const Icon(Icons.my_location, size: 16),
                                  label: const Text(
                                    '定位',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: muted,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _previewHtmlTab
                          ? SingleChildScrollView(
                              controller: _previewScroll,
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
                              child: SelectableText(
                                markdownToHtmlFragment(
                                  _previewSource,
                                  extensionSet: _flavor.extensionSet,
                                ),
                                style: TextStyle(
                                  fontFamily: 'Menlo',
                                  fontSize: 12.5,
                                  height: 1.45,
                                  color: dark
                                      ? const Color(0xFFD7DAE0)
                                      : const Color(0xFF1F2328),
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              controller: _previewScroll,
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
                              child: AnchoredMarkdownPreview(
                                source: _previewSource,
                                blockKeys: _blockKeys,
                                documentPath: _path,
                                imageBuilder: _previewImage,
                                extensionSet: _flavor.extensionSet,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sourceEditor({ScrollController? scrollController}) {
    return SourceEditor(
      controller: _controller,
      focusNode: _focusNode,
      scrollController: scrollController ?? _sourceScroll,
      fontSize: _fontSize,
      fileName: _openDocs.isEmpty
          ? 'Untitled'
          : (_openDocs[_activeIndex].path == null
                ? 'Untitled'
                : _openDocs[_activeIndex].fileName),
      onTap: _syncActiveBlockFromSelection,
    );
  }

  Widget _markdownView(
    String source, {
    required bool editableTasks,
    int? blockIndex,
    bool anchorHeadings = false,
  }) {
    final headingBuilder = HeadingAnchorBuilder(
      extractOutline(source),
      (offset) => _readKeys.putIfAbsent(offset, GlobalKey.new),
      source,
      _previewImage,
    );
    final textBuilder = PreviewTextBuilder();
    return PreviewSelectionSurface(
      child: MarkdownBody(
      data: source,
      styleSheet: previewStyle(context),
      selectable: false,
      extensionSet: _flavor.extensionSet,
      onTapLink: (text, href, title) async {
        if (href == null) return;
        final uri = Uri.tryParse(href);
        if (uri != null) await launchUrl(uri);
      },
      builders: {
        if (anchorHeadings)
          for (var level = 1; level <= 6; level++) "h$level": headingBuilder,
        if (!anchorHeadings)
          for (var level = 1; level <= 6; level++) "h$level": textBuilder,
        "p": textBuilder,
        "blockquote": textBuilder,
        "li": textBuilder,
        "code": _CodeBuilder(
          isDark: Theme.of(context).brightness == Brightness.dark,
        ),
      },
      checkboxBuilder: (checked) {
        return Checkbox(
          value: checked,
          onChanged: !editableTasks
              ? null
              : (_) => _toggleTaskInSource(source, checked, blockIndex),
        );
      },
      // ignore: deprecated_member_use
      imageBuilder: _previewImage,
    ),
    );
  }

  Widget _previewImage(Uri uri, String? title, String? alt) {
    if (uri.scheme == "http" || uri.scheme == "https") {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text("[外链图片：默认不自动加载]"),
      );
    }
    final base = _path != null ? p.dirname(_path!) : null;
    final filePath = base == null
        ? uri.toString()
        : p.normalize(p.join(base, uri.path));
    final file = File(filePath);
    if (!file.existsSync()) return Text("[缺少图片: ${uri.path}]");
    return Image.file(file, fit: BoxFit.contain);
  }

  void _toggleTaskInSource(
    String blockSource,
    bool currentlyChecked,
    int? blockIndex,
  ) {
    final from = currentlyChecked ? "[x]" : "[ ]";
    final to = currentlyChecked ? "[ ]" : "[x]";
    final idx = blockSource.toLowerCase().indexOf(from.toLowerCase());
    if (idx < 0) return;
    final replaced = blockSource.replaceRange(idx, idx + 3, to);
    if (blockIndex == null) {
      _controller.text = _controller.text.replaceFirst(blockSource, replaced);
      return;
    }
    final blocks = splitMarkdownBlocks(_controller.text);
    if (blockIndex >= blocks.length) return;
    blocks[blockIndex] = replaced;
    _controller.text = joinBlocks(blocks);
  }
}

class _BoldIntent extends Intent {
  const _BoldIntent();
}

class _ItalicIntent extends Intent {
  const _ItalicIntent();
}

class _CodeBuilder extends MarkdownElementBuilder {
  _CodeBuilder({required this.isDark});
  final bool isDark;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    if (!element.attributes.containsKey("class")) return null;
    final language =
        element.attributes["class"]?.replaceFirst("language-", "") ?? "";
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
              textStyle: const TextStyle(fontFamily: "Menlo", fontSize: 13),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton(
              tooltip: "复制",
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
      case "js":
      case "javascript":
        return "javascript";
      case "ts":
      case "typescript":
        return "typescript";
      case "py":
      case "python":
        return "python";
      case "sh":
      case "shell":
      case "bash":
        return "bash";
      case "yml":
        return "yaml";
      default:
        return language.isEmpty ? "plaintext" : language;
    }
  }
}

const _welcome = """# Flow MD Editor

本地优先的 Markdown 编辑器。Split 模式左右对照：左侧源码，右侧预览；右侧「定位」可同步到编辑位置。

## 快捷键

- `⌘N` 新建 · `⌘O` 打开 · `⌘S` 保存
- `⌘F` / `Ctrl+F` 查找 · `⌘G` / `⇧⌘G` 上下匹配
- `⌘B` 加粗 · `⌘I` 斜体

## 任务列表

- [ ] 未完成
- [x] 已完成

## 代码

```python
print("hello")
```

> 标题栏可切换：Split（左右分栏）/ Editor（源码）/ Preview（阅读）
""";
