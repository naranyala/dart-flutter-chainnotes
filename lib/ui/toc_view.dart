import 'package:flutter/material.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../app/workspace_controller.dart';
import '../core/pdf/outline_pdf_writer.dart';
import '../core/workspace/workspace_models.dart';
import '../sessions/image_session.dart';
import '../sessions/map_session.dart';
import '../sessions/pdf_session.dart';
import 'widgets.dart' as w;

/// The TOC Manager: the outline spine, its links to the other tools, the draft
/// binding, and the JSON/PDF transfers.
class TocView extends StatefulWidget {
  const TocView({
    super.key,
    required this.controller,
    required this.pdf,
    required this.images,
    required this.map,
    this.files = const FileService(),
  });

  final WorkspaceController controller;
  final PdfSession pdf;
  final ImageSession images;
  final MapSession map;
  final FileService files;

  @override
  State<TocView> createState() => _TocViewState();
}

class _TocViewState extends State<TocView> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _filterController = TextEditingController();
  final TextEditingController _editController = TextEditingController();
  int _level = 1;
  int _editLevel = 1;
  OutlinePdfResult? _lastOutlinePdf;
  bool _busy = false;

  WorkspaceController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _filterController.text = controller.tocFilterQuery;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _filterController.dispose();
    _editController.dispose();
    super.dispose();
  }

  /* --- actions ------------------------------------------------------------- */

  Future<void> _importJson() async {
    final path = await widget.files.chooseFile(extensions: const ['json']);
    if (path == null || !mounted) return;
    final file = await widget.files.readTextFile(path);
    if (!mounted) return;
    if (!file.ok) {
      setState(() {
        controller.tocStatus.set(file.error!, error: true);
      });
      return;
    }
    controller.importTocJson(file.content);
    setState(() {});
  }

  Future<void> _exportJson() async {
    final path = await widget.files.choosePath(
      suggestedName: suggestFileName(
        controller.activeTocItem?.title ?? 'outline',
        'json',
      ),
      extensions: const ['json'],
    );
    if (path == null || !mounted) return;
    final ok = await widget.files.writeTextFile(path, controller.exportTocJson());
    if (!mounted) return;
    setState(() {
      controller.tocStatus.set(
        ok ? 'Outline exported.' : 'The outline could not be written.',
        error: !ok,
      );
    });
  }

  Future<void> _combineToPdf() async {
    if (controller.tocItems.isEmpty || _busy) return;
    setState(() => _busy = true);
    final directory = await widget.files.chooseDirectory(
      confirmButtonText: 'Choose a folder for the combined PDF',
    );
    if (!mounted) return;
    if (directory == null) {
      setState(() {
        _busy = false;
        controller.tocStatus.set('No folder chosen.');
      });
      return;
    }
    final title = controller.activeTocItem?.title ??
        (controller.tocItems.isNotEmpty ? controller.tocItems.first.title : 'outline');
    try {
      final result = await renderOutlinePdf(
        directory: directory,
        suggestedName: title,
        title: null,
        items: controller.tocItems,
      );
      controller.pdf.workspaceDirectory = directory;
      controller.touch();
      setState(() {
        _lastOutlinePdf = result;
        _busy = false;
        controller.tocStatus
            .set('Combined to ${result.name} · ${result.pages} pages.');
      });
    } catch (_) {
      setState(() {
        _busy = false;
        controller.tocStatus.set('The combined PDF could not be written.',
            error: true);
      });
    }
  }

  void _openLinkedPdf(TocItem item) {
    final page = item.links.pdfPage;
    if (page == null) return;
    final name = item.links.pdfName;
    controller.selectView('pdf');
    if (widget.pdf.isOpen) {
      if (name.isEmpty || widget.pdf.openName == name) {
        widget.pdf.navigateToPage(page);
        return;
      }
    }
    final match = controller.pdf.recentPaths
        .where((path) => path.endsWith(name) && name.isNotEmpty)
        .toList();
    if (match.isNotEmpty) {
      widget.pdf.openAt(match.first).then((_) {
        if (mounted) widget.pdf.navigateToPage(page);
      });
      return;
    }
    widget.pdf.setStatus(
      name.isEmpty
          ? 'Open a PDF to jump to page $page.'
          : 'Open “$name” to jump to page $page.',
      error: true,
    );
  }

  void _openLinkedImages(TocItem item) {
    controller.selectView('images');
    final paths = item.links.images;
    if (paths.isEmpty) return;
    if (!widget.images.hasImages) {
      widget.images.setStatus('Open the folder that holds these images.',
          error: true);
      return;
    }
    final visible = widget.images.visibleImages;
    for (var i = 0; i < visible.length; i++) {
      if (paths.contains(visible[i].path)) {
        widget.images.openLightbox(i);
        return;
      }
    }
    widget.images.setStatus('Those images are not in the open folder.',
        error: true);
  }

  void _openLinkedLocation(TocItem item) {
    final location = item.links.location;
    controller.selectView('map');
    if (location == null) return;
    widget.map.flyTo(location.lat, location.lon);
  }

  /* --- layout -------------------------------------------------------------- */

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.filteredTocItems;
        return Column(
          children: [
            _toolbar(),
            if (_lastOutlinePdf != null ||
                controller.pdf.workspaceDirectory.isNotEmpty)
              _outlinePdfBar(),
            _declareBar(),
            if (controller.showTocFilter) _filterBar(),
            Expanded(
              child: items.isEmpty
                  ? _emptyState(controller.tocFilterQuery)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) =>
                          _row(items[index], index, items.length),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _toolbar() {
    final status = controller.tocStatus;
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
          const w.Eyebrow('TOC MANAGER'),
          Text(
            controller.tocItemLabel,
            style: const TextStyle(fontSize: 12.5, color: WorkspaceColors.textMuted),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 420),
            child: w.StatusLine(
              id: 'toc-manager-status',
              message: status.message,
              error: status.isError,
            ),
          ),
          const SizedBox(width: 4),
          w.ToolbarButton(label: 'Import…', onPressed: _importJson),
          w.ToolbarButton(
            label: 'Export…',
            onPressed: controller.tocItems.isEmpty ? null : _exportJson,
          ),
          w.ToolbarButton(
            label: _busy ? 'Combining…' : 'Combine to PDF',
            variant: w.ToolbarVariant.primary,
            onPressed:
                controller.tocItems.isEmpty || _busy ? null : _combineToPdf,
          ),
          if (controller.lastRemoved != null)
            w.ToolbarButton(label: 'Undo remove', onPressed: controller.undoTocRemoval),
          w.ToolbarButton(
            label: 'Resume writing',
            onPressed: controller.activeTocItem == null
                ? null
                : () => controller.selectTocItem(controller.activeTocItem!),
          ),
        ],
      ),
    );
  }

  Widget _outlinePdfBar() {
    final result = _lastOutlinePdf;
    final directory = controller.pdf.workspaceDirectory;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: WorkspaceColors.surfaceRaised,
      child: Row(
        children: [
          if (directory.isNotEmpty) ...[
            const Icon(Icons.folder_outlined, size: 15,
                color: WorkspaceColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                directory,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: WorkspaceColors.textMuted),
              ),
            ),
          ] else
            const Spacer(),
          if (result != null) ...[
            w.ToolbarButton(
              label: 'Preview ${result.name} · ${result.pages} pages',
              onPressed: () {
                controller.pdf
                  ..path = result.path
                  ..name = result.name;
                controller.selectView('pdf');
                widget.pdf.openAt(result.path);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _declareBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: WorkspaceColors.surface,
        border: Border(bottom: BorderSide(color: WorkspaceColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Form(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    key: const Key('toc-title-input'),
                    controller: _titleController,
                    maxLength: 120,
                    style: const TextStyle(fontSize: 13.5),
                    decoration: const InputDecoration(
                      hintText: 'New section title…',
                      counterText: '',
                    ),
                    onFieldSubmitted: (_) => _declare(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _level,
                    style: const TextStyle(fontSize: 13.5),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('H1 · Chapter')),
                      DropdownMenuItem(value: 2, child: Text('H2 · Section')),
                      DropdownMenuItem(value: 3, child: Text('H3 · Subsection')),
                    ],
                    onChanged: (value) => setState(() => _level = value ?? 1),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _declare,
                  child: const Text('Add section'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Each section becomes a row here and a draft in the Text Editor.',
            style: TextStyle(fontSize: 11.5, color: WorkspaceColors.textMuted),
          ),
        ],
      ),
    );
  }

  void _declare() {
    controller.addTocItem(title: _titleController.text, level: _level);
    if (controller.tocStatus.isError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(controller.tocStatus.message)),
      );
    }
    _titleController.clear();
    setState(() {});
  }

  Widget _filterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: TextFormField(
        controller: _filterController,
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration(
          hintText: 'Filter sections…',
          prefixIcon: Icon(Icons.search, size: 16),
        ),
        onChanged: (value) {
          controller.tocFilterQuery = value;
          controller.notifyChanged();
        },
      ),
    );
  }

  Widget _emptyState(String query) {
    if (query.trim().isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('No sections match “$query”.'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                _filterController.clear();
                controller.tocFilterQuery = '';
                controller.notifyChanged();
              },
              child: const Text('Clear filter'),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.list_alt, size: 56, color: WorkspaceColors.border),
          SizedBox(height: 12),
          Text('No outline items yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text(
            'Declare your first section above, then select it to start writing.',
            textAlign: TextAlign.center,
            style: TextStyle(color: WorkspaceColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _row(TocItem item, int index, int total) {
    final active = item.id == controller.activeTocId;
    final editing = controller.editingTocId == item.id;
    final filterActive = controller.tocFilterQuery.trim().isNotEmpty;
    final words = countWords(item.content);
    final indent = (clampLevel(item.level) - 1) * 14.0;

    return Container(
      decoration: BoxDecoration(
        color: active ? WorkspaceColors.surfaceRaised : WorkspaceColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? WorkspaceColors.accent : WorkspaceColors.borderSubtle,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      child: editing ? _editRow(item) : Row(
        children: [
          SizedBox(
            width: indent,
            child: const SizedBox.shrink(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => controller.selectTocItem(item),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: WorkspaceColors.surfaceRaised,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: WorkspaceColors.border),
                        ),
                        child: Text(
                          'H${clampLevel(item.level)}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: WorkspaceColors.accent,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            decoration: active
                                ? TextDecoration.underline
                                : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        words == 0
                            ? 'no draft yet'
                            : '$words words · draft saved',
                        style: const TextStyle(
                            fontSize: 11.5, color: WorkspaceColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (item.links.pdfPage != null)
                      _chip(
                        'p.${item.links.pdfPage}',
                        onTap: () => _openLinkedPdf(item),
                      ),
                    if (item.links.images.isNotEmpty)
                      _chip(
                        'IMG ${item.links.images.length}',
                        onTap: () => _openLinkedImages(item),
                      ),
                    if (item.links.location != null)
                      _chip('LOC', onTap: () => _openLinkedLocation(item)),
                    if (item.links.images.isEmpty &&
                        item.links.pdfPage == null &&
                        item.links.location == null)
                      const Text(
                        'no links yet',
                        style: TextStyle(
                            fontSize: 11, color: WorkspaceColors.textMuted),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              Row(
                children: [
                  _iconButton(
                    Icons.arrow_upward,
                    tooltip: 'Move up',
                    enabled: index > 0 && !filterActive,
                    onTap: () => controller.moveTocItem(item, -1),
                  ),
                  _iconButton(
                    Icons.arrow_downward,
                    tooltip: 'Move down',
                    enabled: index < total - 1 && !filterActive,
                    onTap: () => controller.moveTocItem(item, 1),
                  ),
                ],
              ),
              Row(
                children: [
                  _iconButton(
                    Icons.edit_outlined,
                    tooltip: 'Edit',
                    onTap: () {
                      controller.startTocEdit(item);
                      _editController.text = item.title;
                      _editLevel = item.level;
                    },
                  ),
                  _iconButton(
                    Icons.close,
                    tooltip: 'Remove',
                    onTap: () {
                      controller.removeTocItem(item);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _editRow(TocItem item) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            key: const Key('toc-edit-input'),
            controller: _editController,
            maxLength: 120,
            style: const TextStyle(fontSize: 13.5),
            decoration: const InputDecoration(counterText: ''),
            onFieldSubmitted: (_) => _saveEdit(item),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: _editLevel,
            items: const [
              DropdownMenuItem(value: 1, child: Text('H1 · Chapter')),
              DropdownMenuItem(value: 2, child: Text('H2 · Section')),
              DropdownMenuItem(value: 3, child: Text('H3 · Subsection')),
            ],
            onChanged: (value) => setState(() => _editLevel = value ?? 1),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => _saveEdit(item),
          child: const Text('Save'),
        ),
        const SizedBox(width: 6),
        OutlinedButton(
          onPressed: controller.cancelTocEdit,
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  void _saveEdit(TocItem item) {
    controller.tocEditTitle = _editController.text;
    controller.tocEditLevel = _editLevel;
    controller.saveTocEdit(item);
    setState(() {});
  }

  Widget _chip(String label, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: WorkspaceColors.surfaceRaised,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: WorkspaceColors.border),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, color: WorkspaceColors.accent),
        ),
      ),
    );
  }

  Widget _iconButton(
    IconData icon, {
    required String tooltip,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 16),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      color: WorkspaceColors.text,
      disabledColor: WorkspaceColors.border,
    );
  }
}
