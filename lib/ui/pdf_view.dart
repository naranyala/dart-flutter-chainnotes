import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../app/workspace_controller.dart';
import '../core/pdf/pdf_outline.dart';
import '../sessions/pdf_session.dart';
import 'widgets.dart' as w;

/// The PDF Reader: a paged reader with a contents sidebar, remembered paths,
/// zoom, and the outline link panel.
class PdfView extends StatefulWidget {
  const PdfView({
    super.key,
    required this.controller,
    required this.pdf,
    this.files = const FileService(),
  });

  final WorkspaceController controller;
  final PdfSession pdf;
  final FileService files;

  @override
  State<PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<PdfView> {
  final ScrollController _scroll = ScrollController();
  double _boxWidth = 720;
  int _currentPage = 1;

  PdfSession get pdf => widget.pdf;
  WorkspaceController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    pdf.addListener(_onSessionChanged);
    controller.addListener(_onSessionChanged);
    _currentPage = controller.pdf.page.clamp(1, 1);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    pdf.removeListener(_onSessionChanged);
    controller.removeListener(_onSessionChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
    final target = controller.pdf.page;
    if (pdf.isOpen && target != _currentPage) {
      _currentPage = target;
      _scrollToPage(target, animated: false);
    }
  }

  void _onScroll() {
    if (!pdf.isOpen) return;
    final index = _pageAtOffset(_scroll.offset);
    if (index != _currentPage) {
      _currentPage = index;
      controller.pdf.page = index;
      widget.pdf.navigateToPage(index);
    }
  }

  double _displayWidth() => _boxWidth * pdf.renderZoom;

  double _pageHeight(int index) =>
      _displayWidth() * pdf.aspectOf(index + 1);

  double _offsetOf(int page) {
    var offset = 0.0;
    for (var i = 1; i < page; i++) {
      offset += _pageHeight(i - 1) + 16;
    }
    return offset;
  }

  int _pageAtOffset(double offset) {
    var cursor = 0.0;
    for (var i = 1; i <= pdf.pageCount; i++) {
      cursor += _pageHeight(i - 1) + 16;
      if (offset < cursor) return i;
    }
    return pdf.pageCount < 1 ? 1 : pdf.pageCount;
  }

  void _scrollToPage(int page, {required bool animated}) {
    final target = _offsetOf(page) + 16;
    final clamped =
        target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
    if (animated) {
      _scroll.animateTo(
        clamped,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(clamped);
    }
  }

  Future<void> _openPdf() async {
    final path = await widget.files.chooseFile(
      extensions: const ['pdf'],
      label: 'PDF',
    );
    if (path == null || !mounted) return;
    await pdf.openAt(path);
    if (!mounted) return;
    _currentPage = controller.pdf.page;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToPage(_currentPage, animated: false);
    });
  }

  Future<void> _openText() async {
    final path = await widget.files.chooseFile(
      extensions: const ['pdf'],
      label: 'PDF',
    );
    if (path == null || !mounted) return;
    await pdf.openAt(path);
    if (mounted) setState(() {});
  }

  void _attachPage() {
    if (!pdf.isOpen) return;
    final ok = controller.attachPdfPage(
      controller.pdf.page,
      pdf.openName,
    );
    if (ok) {
      pdf.setStatus('Page ${controller.pdf.page} attached to '
          '“${controller.linkTarget!.title}”.');
    } else if (controller.linkTarget == null) {
      pdf.setStatus('Select an outline item to attach this page to.',
          error: true);
    }
    setState(() {});
  }

  void _importHeadings() {
    if (pdf.headings.isEmpty) {
      pdf.setStatus('Open a PDF first so there are headings to import.',
          error: true);
      return;
    }
    final headings = [
      for (final heading in pdf.headings)
        <String, Object?>{
          'title': heading.title,
          'level': heading.level,
          'page': heading.page,
        },
    ];
    final added =
        controller.importPdfHeadings(headings, pdf.openName);
    if (added == 0) {
      pdf.setStatus('Every heading is already in the outline.', error: true);
    } else {
      pdf.setStatus('$added heading${added == 1 ? '' : 's'} imported.');
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, pdf]),
      builder: (context, _) {
        return Column(
          children: [
            _toolbar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (pdf.sidebarOpen) _sidebar(),
                  Expanded(child: pdf.isOpen ? _reader() : _empty()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _toolbar() {
    final status = pdf.status;
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
          const w.Eyebrow('PDF READER'),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              pdf.isOpen ? pdf.openName : 'No document open',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 140, maxWidth: 420),
            child: w.StatusLine(
              id: 'pdf-status',
              message: status.message,
              error: status.isError,
            ),
          ),
          const SizedBox(width: 4),
          if (pdf.isOpen)
            w.ToolbarButton(
              label: 'Open another',
              variant: w.ToolbarVariant.primary,
              onPressed: _openPdf,
            ),
          w.ToolbarButton(
            label: pdf.sidebarOpen ? 'Hide contents' : 'Contents',
            onPressed: pdf.toggleSidebar,
          ),
        ],
      ),
    );
  }

  Widget _sidebar() {
    final headings = pdf.headings;
    return Container(
      width: 272,
      decoration: const BoxDecoration(
        color: WorkspaceColors.surface,
        border: Border(right: BorderSide(color: WorkspaceColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const w.Eyebrow('CONTENTS'),
                const SizedBox(height: 4),
                Text(
                  key: const Key('toc-count'),
                  pdf.headingsLoading
                      ? 'Reading…'
                      : '${headings.length} heading${headings.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 12, color: WorkspaceColors.textMuted),
                ),
              ],
            ),
          ),
          Expanded(
            child: headings.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      pdf.headingsMessage,
                      style: const TextStyle(
                          fontSize: 12.5, color: WorkspaceColors.textMuted),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                    children: [
                      for (final heading in headings)
                        _headingRow(heading),
                    ],
                  ),
          ),
          const Divider(),
          _linkPanel(),
        ],
      ),
    );
  }

  Widget _headingRow(PdfOutlineEntry heading) {
    final page = heading.page;
    final active = page != null && page == controller.pdf.page;
    return TextButton(
      onPressed: page == null ? null : () => pdf.goToHeading(heading),
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.only(
          left: 8.0 + (heading.level - 1) * 14,
          right: 8,
          top: 7,
          bottom: 7,
        ),
        backgroundColor:
            active ? WorkspaceColors.surfaceRaised : Colors.transparent,
        foregroundColor:
            active ? WorkspaceColors.accent : WorkspaceColors.text,
      ),
      child: Text(
        '${heading.title}${page != null ? '  ·  p.$page' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5),
      ),
    );
  }

  Widget _linkPanel() {
    final target = controller.linkTarget;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const w.Eyebrow('OUTLINE LINK'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: controller.linkTargetId,
            hint: const Text('Select outline item',
                style: TextStyle(fontSize: 12.5)),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Select outline item',
                    style: TextStyle(fontSize: 12.5)),
              ),
              for (final item in controller.tocItems)
                DropdownMenuItem<String?>(
                  value: item.id,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 210),
                    child: Text(
                      item.title,
                      style: const TextStyle(fontSize: 12.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
            onChanged: (value) {
              controller.setLinkTarget(value);
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: w.ToolbarButton(
                  label: 'Attach page ${controller.pdf.page}',
                  variant: w.ToolbarVariant.primary,
                  onPressed: target == null || !pdf.isOpen ? null : _attachPage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: w.ToolbarButton(
                  label: 'Import ${pdf.headings.length} heading'
                      '${pdf.headings.length == 1 ? '' : 's'}',
                  onPressed: pdf.headings.isEmpty ? null : _importHeadings,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _reader() {
    final controls = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: WorkspaceColors.surfaceRaised,
        border:
            Border(bottom: BorderSide(color: WorkspaceColors.borderSubtle)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          w.ToolbarButton(
            label: 'Previous',
            onPressed: controller.pdf.page <= 1
                ? null
                : () => _goToPage(controller.pdf.page - 1),
          ),
          Text(
            'Page ${controller.pdf.page} of ${pdf.pageCount}',
            style: const TextStyle(fontSize: 12.5),
          ),
          w.ToolbarButton(
            label: 'Next',
            onPressed: controller.pdf.page >= pdf.pageCount
                ? null
                : () => _goToPage(controller.pdf.page + 1),
          ),
          const SizedBox(width: 8),
          const Text('Zoom',
              style: TextStyle(
                  fontSize: 12, color: WorkspaceColors.textMuted)),
          w.ToolbarButton(
            label: '−',
            onPressed: () => _changeZoom(-0.1),
          ),
          SizedBox(
            width: 54,
            child: Text(
              '${(pdf.renderZoom * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          w.ToolbarButton(label: '+', onPressed: () => _changeZoom(0.1)),
        ],
      ),
    );

    return Column(
      children: [
        controls,
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _boxWidth = constraints.maxWidth;
              final dpr = MediaQuery.devicePixelRatioOf(context);
              final displayWidth = _displayWidth();
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: pdf.pageCount,
                itemBuilder: (context, index) {
                  final page = index + 1;
                  final height = displayWidth * pdf.aspectOf(page);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SizedBox(
                      height: height,
                      child: _PdfPage(
                        pdf: pdf,
                        page: page,
                        pixelWidth: displayWidth * dpr,
                        pixelHeight: height * dpr,
                        displayWidth: displayWidth,
                        displayHeight: height,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _goToPage(int page) {
    controller.pdf.page = page;
    pdf.navigateToPage(page);
    _scrollToPage(page, animated: true);
    setState(() {});
  }

  void _changeZoom(double delta) {
    final anchor = _currentPage;
    pdf.changeZoom(delta);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToPage(anchor, animated: false);
    });
    setState(() {});
  }

  Widget _empty() {
    final remembered = controller.pdf.recentPaths;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: WorkspaceColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: WorkspaceColors.border),
                ),
                child: const Text('PDF',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: WorkspaceColors.accent)),
              ),
              const SizedBox(height: 14),
              const Text('Open a PDF',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'Pick a document from this machine, or reopen one you remember.',
                textAlign: TextAlign.center,
                style: TextStyle(color: WorkspaceColors.textMuted),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _openText,
                child: const Text('Browse files'),
              ),
              if (remembered.isNotEmpty) ...[
                const SizedBox(height: 26),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: w.Eyebrow('REMEMBERED'),
                ),
                const SizedBox(height: 8),
                for (final path in remembered.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () async {
                          await pdf.openAt(path);
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.history, size: 15),
                        label: Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          backgroundColor: WorkspaceColors.card,
                          foregroundColor: WorkspaceColors.text,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfPage extends StatefulWidget {
  const _PdfPage({
    required this.pdf,
    required this.page,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.displayWidth,
    required this.displayHeight,
  });

  final PdfSession pdf;
  final int page;
  final double pixelWidth;
  final double pixelHeight;
  final double displayWidth;
  final double displayHeight;

  @override
  State<_PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<_PdfPage> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.pdf.renderPage(
      widget.page,
      pixelWidth: widget.pixelWidth,
      pixelHeight: widget.pixelHeight,
    );
  }

  @override
  void didUpdateWidget(covariant _PdfPage old) {
    super.didUpdateWidget(old);
    if (old.pixelWidth != widget.pixelWidth ||
        old.pixelHeight != widget.pixelHeight) {
      _future = widget.pdf.renderPage(
        widget.page,
        pixelWidth: widget.pixelWidth,
        pixelHeight: widget.pixelHeight,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<Uint8List?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return SizedBox(
              width: widget.displayWidth,
              height: widget.displayHeight,
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            return SizedBox(
              width: widget.displayWidth,
              height: widget.displayHeight,
              child: const Center(
                child: Text(
                  'This page could not be rendered.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
            );
          }
          return SizedBox(
            width: widget.displayWidth,
            height: widget.displayHeight,
            child: Image.memory(
              bytes,
              width: widget.displayWidth,
              height: widget.displayHeight,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
          );
        },
      ),
    );
  }
}
