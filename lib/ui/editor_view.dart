import 'package:flutter/material.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../app/workspace_controller.dart';
import '../core/workspace/workspace_models.dart';
import 'widgets.dart' as w;

/// The Text Editor: one draft buffer bound to the active outline item, with
/// prev/next navigation and text import/export.
class EditorView extends StatefulWidget {
  const EditorView({
    super.key,
    required this.controller,
    this.files = const FileService(),
  });

  final WorkspaceController controller;
  final FileService files;

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _lastSyncedItem;

  WorkspaceController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _text.text = controller.editorContent;
    _text.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _text.removeListener(_onTextChanged);
    _text.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    controller.setEditorContent(_text.text);
    _updateCursor();
  }

  void _updateCursor() {
    final selection = _text.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    final text = _text.text;
    var line = 1;
    var lastBreak = -1;
    for (var i = 0; i < selection.baseOffset && i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0a) {
        line++;
        lastBreak = i;
      }
    }
    final column = selection.baseOffset - lastBreak;
    controller.setCursorPosition('Line $line, Col $column');
  }

  void _syncFromRecord() {
    // Never mutate the TextEditingController synchronously inside build:
    // on mobile IMEs that fights the composing region. Defer to post-frame.
    final active = controller.activeTocItem;
    final wantText =
        active == null ? controller.editorContent : active.content;
    final wantId = active?.id;
    if (_lastSyncedItem == wantId && _text.text == wantText) return;
    final syncedId = wantId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_lastSyncedItem == syncedId && _text.text == wantText) return;
      _lastSyncedItem = syncedId;
      if (_text.text != wantText) {
        _text.text = wantText;
        _text.selection = TextSelection.collapsed(offset: _text.text.length);
      }
    });
  }

  Future<void> _importDraft() async {
    final path = await widget.files.chooseFile(
      extensions: const ['txt', 'md', 'markdown'],
      label: 'Text',
    );
    if (path == null || !mounted) return;
    final file = await widget.files.readTextFile(path);
    if (!mounted) return;
    if (!file.ok) {
      controller.setEditorNotice(file.error!, error: true);
      return;
    }
    _text.text = file.content;
    controller.setEditorNotice('Imported ${file.name}.');
  }

  Future<void> _exportDraft() async {
    if (_text.text.isEmpty) return;
    final active = controller.activeTocItem;
    final path = await widget.files.choosePath(
      suggestedName: suggestFileName(active?.title ?? 'draft', 'md'),
      extensions: const ['md', 'txt'],
    );
    if (path == null || !mounted) return;
    final ok = await widget.files.writeTextFile(path, _text.text);
    controller.setEditorNotice(
      ok ? 'Exported to $path.' : 'The draft could not be written.',
      error: !ok,
    );
  }

  void _goTo(TocItem? item) {
    if (item == null) return;
    controller.selectTocItem(item);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        _syncFromRecord();
        final active = controller.activeTocItem;
        if (active == null) return _gate();
        return Column(
          // Stretch so the toolbar fills the window width.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(active),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  key: const Key('values'),
                  controller: _text,
                  focusNode: _focusNode,
                  maxLines: null,
                  minLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 14.5, height: 1.5),
                  decoration: const InputDecoration(
                    hintText: 'Start writing…',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.all(4),
                  ),
                ),
              ),
            ),
            _footer(active),
          ],
        );
      },
    );
  }

  Widget _gate() {
    final items = controller.tocItems;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: WorkspaceColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WorkspaceColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const w.Eyebrow('TEXT EDITOR'),
                const SizedBox(height: 8),
                const Text(
                  'What are you writing?',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Pick a section to write, or declare a new one in the TOC Manager.',
                  style: TextStyle(color: WorkspaceColors.textMuted),
                ),
                const SizedBox(height: 18),
                if (items.isEmpty)
                  const Text(
                    'No sections yet. Declare your first section to give this editor something to hold.',
                    style: TextStyle(color: WorkspaceColors.textMuted),
                  )
                else
                  ...items.map(
                    (item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: WorkspaceColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: WorkspaceColors.border),
                        ),
                        child: Text(
                          'H${clampLevel(item.level)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: WorkspaceColors.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(item.title),
                      subtitle: Text(
                        '${countWords(item.content)} words · '
                        '${item.content.trim().isEmpty ? 'no draft yet' : 'draft saved'}',
                        style: const TextStyle(
                            fontSize: 11.5, color: WorkspaceColors.textMuted),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => controller.selectTocItem(item),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => controller.selectView('toc'),
                  child: Text(items.isEmpty
                      ? 'Declare the first section'
                      : 'Declare another section'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar(TocItem active) {
    final links = active.links;
    final index = controller.activeTocIndex;
    return Container(
      constraints: const BoxConstraints(minHeight: topBarHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: WorkspaceColors.surface,
        border: Border(bottom: BorderSide(color: WorkspaceColors.borderSubtle)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          w.ToolbarButton(
            label: '‹ Outline',
            onPressed: () => controller.selectView('toc'),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: WorkspaceColors.surfaceRaised,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: WorkspaceColors.border),
            ),
            child: Text(
              'H${clampLevel(active.level)}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: WorkspaceColors.accent,
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              active.title,
              key: const Key('document-title-text'),
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          if (links.pdfPage != null)
            w.ToolbarButton(
              label: 'PDF p.${links.pdfPage}',
              onPressed: () => controller.selectView('pdf'),
            ),
          if (links.location != null)
            w.ToolbarButton(
              label: 'Location',
              onPressed: () => controller.selectView('map'),
            ),
          w.ToolbarButton(
            label: '‹ Prev',
            onPressed: controller.previousTocItem == null
                ? null
                : () => _goTo(controller.previousTocItem),
          ),
          w.ToolbarButton(
            label: 'Next ›',
            onPressed: controller.nextTocItem == null
                ? null
                : () => _goTo(controller.nextTocItem),
          ),
          w.ToolbarButton(label: 'Import…', onPressed: _importDraft),
          w.ToolbarButton(
            label: 'Export…',
            onPressed: _text.text.isEmpty ? null : _exportDraft,
          ),
          const SizedBox(width: 4),
          Text(
            'Item ${index + 1} of ${controller.tocItems.length}',
            style: const TextStyle(
                fontSize: 12, color: WorkspaceColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _footer(TocItem active) {
    final notice = controller.editorNotice;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Row(
        children: [
          Text(
            key: const Key('document-status'),
            '${countWords(controller.editorContent)} words · ${controller.saveLabel}',
            style:
                const TextStyle(fontSize: 11.5, color: WorkspaceColors.textMuted),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: w.StatusLine(
              id: 'editor-notice',
              message: notice.message,
              error: notice.isError,
            ),
          ),
          Text(
            key: const Key('cursor-position'),
            controller.editorCursorPosition,
            style: const TextStyle(
                fontSize: 11.5, color: WorkspaceColors.textMuted),
          ),
        ],
      ),
    );
  }
}
