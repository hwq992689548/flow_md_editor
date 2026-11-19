import 'package:flutter/material.dart';

import '../models/open_document.dart';
import '../utils/document_outline.dart';

/// macOS-style sidebar: Documents list + Structure for the active doc.
class OutlineSidebar extends StatelessWidget {
  const OutlineSidebar({
    super.key,
    required this.documents,
    required this.activeIndex,
    required this.headings,
    required this.activeOffset,
    required this.wordCount,
    required this.onSelectDocument,
    required this.onCloseDocument,
    required this.onHeadingTap,
    required this.onOpen,
    required this.onNew,
  });

  final List<OpenDocument> documents;
  final int activeIndex;
  final List<DocumentHeading> headings;
  final int? activeOffset;
  final int wordCount;
  final ValueChanged<int> onSelectDocument;
  final ValueChanged<int> onCloseDocument;
  final ValueChanged<DocumentHeading> onHeadingTap;
  final VoidCallback onOpen;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF2A2A2C) : const Color(0xFFEDEDF0);
    final border = dark ? const Color(0xFF1A1A1C) : const Color(0xFFD2D2D7);
    final muted = dark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70);
    final body = dark ? const Color(0xFFD1D1D6) : const Color(0xFF1C1C1E);
    final divider = dark ? const Color(0xFF3A3A3C) : const Color(0xFFD2D2D7);
    final sectionStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      color: muted,
    );

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: bg,
        border: Border(right: BorderSide(color: border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 6, 6),
            child: Row(
              children: [
                Text('Documents', style: sectionStyle),
                const Spacer(),
                _IconAction(
                  tooltip: '新建 (⌘N)',
                  icon: Icons.note_add_outlined,
                  onPressed: onNew,
                  color: muted,
                ),
                _IconAction(
                  tooltip: '打开文件 (⌘O)',
                  icon: Icons.folder_open_outlined,
                  onPressed: onOpen,
                  color: muted,
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              itemCount: documents.length,
              itemBuilder: (context, index) {
                final doc = documents[index];
                final active = index == activeIndex;
                return _DocRow(
                  title: doc.titleLabel,
                  active: active,
                  dark: dark,
                  onTap: () => onSelectDocument(index),
                  onClose: () => onCloseDocument(index),
                );
              },
            ),
          ),
          Divider(height: 1, thickness: 0.5, color: divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Text('Structure', style: sectionStyle),
                const Spacer(),
                Text(
                  '$wordCount 词',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: headings.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      '暂无标题，使用 # 添加',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: headings.length,
                    itemBuilder: (context, index) {
                      final heading = headings[index];
                      final active = activeOffset == heading.offset;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Material(
                          color: active
                              ? const Color(0xFF0A84FF)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => onHeadingTap(heading),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                8 + (heading.level - 1).clamp(0, 3) * 10.0,
                                5,
                                8,
                                5,
                              ),
                              child: Tooltip(
                                message: heading.title,
                                child: Text(
                                  heading.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.35,
                                    fontWeight: active
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: active ? Colors.white : body,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    required this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 28),
      icon: Icon(icon, size: 16, color: color),
    );
  }
}

class _DocRow extends StatefulWidget {
  const _DocRow({
    required this.title,
    required this.active,
    required this.dark,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final bool active;
  final bool dark;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_DocRow> createState() => _DocRowState();
}

class _DocRowState extends State<_DocRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final activeBg =
        widget.dark ? const Color(0xFF3A3A3C) : const Color(0xFFDCDCE0);
    final hoverBg =
        widget.dark ? const Color(0xFF333336) : const Color(0xFFE4E4E8);
    final body =
        widget.dark ? const Color(0xFFD1D1D6) : const Color(0xFF1C1C1E);
    final muted =
        widget.dark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: widget.active
              ? activeBg
              : (_hover ? hoverBg : Colors.transparent),
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 14,
                    color: widget.active
                        ? const Color(0xFF0A84FF)
                        : muted,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Tooltip(
                      message: widget.title,
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: widget.active
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: widget.active
                              ? (widget.dark ? Colors.white : body)
                              : body,
                        ),
                      ),
                    ),
                  ),
                  if (_hover || widget.active)
                    IconButton(
                      tooltip: '关闭',
                      onPressed: widget.onClose,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      icon: Icon(Icons.close, size: 13, color: muted),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
