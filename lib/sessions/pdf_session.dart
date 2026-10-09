import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app/workspace_controller.dart';
import '../core/pdf/pdf_outline.dart';
import 'pdf_backend.dart';

/// The PDF Reader session: the open document, its contents sidebar, the
/// remembered paths, and the reading position that reaches disk.
///
/// Rendering needs a platform backend, so opening goes through [PdfOpener]:
/// `pdfx` on Android/iOS/macOS/Windows, `pdfrx` (PDFium) on Linux.
/// Unsupported platforms get a precise sentence and never touch a renderer
/// whose detached platform assert no `try/catch` could contain.
class PdfSession extends ChangeNotifier {
  PdfSession(this.controller, {PdfOpener? opener})
      : _opener = opener ?? platformPdfOpener();

  final WorkspaceController controller;
  final PdfOpener _opener;

  final ToolStatus status = ToolStatus('Open a PDF from your local system.');
  bool sidebarOpen = true;

  PdfEngineDocument? _document;
  int pageCount = 0;
  String? openPath;
  String openName = '';
  int openSize = 0;

  List<PdfOutlineEntry> headings = const [];
  String headingsMessage = 'Contents are extracted when a document opens.';
  bool headingsLoading = false;
  bool headingsFromCache = false;

  double renderZoom = 1.0;
  final Map<int, Uint8List> _pageCache = <int, Uint8List>{};
  final Map<int, double> _aspects = <int, double>{};
  int _renderToken = 0;

  /// Source aspect ratio (height / width) for a page. A4 until the renderer
  /// has seen the real one, so the scroll math always has a number.
  double aspectOf(int pageNumber) => _aspects[pageNumber] ?? 1.4142;

  bool get isOpen => _document != null && pageCount > 0;

  String get badge {
    if (isOpen) {
      return '$openName · page ${controller.pdf.page} of $pageCount';
    }
    final remembered = controller.pdf.recentPaths.length;
    if (remembered > 0) {
      return '$remembered remembered document${remembered == 1 ? '' : 's'}';
    }
    return 'Open a PDF from your local system';
  }

  void setStatus(String message, {bool error = false}) {
    status.set(message, error: error);
    notifyListeners();
  }

  void toggleSidebar() {
    sidebarOpen = !sidebarOpen;
    notifyListeners();
  }

  /// Opens a document from an absolute path; a missing or unreadable file is
  /// reported and dropped from the remembered list. Where the platform has no
  /// renderer, the path is refused with a precise sentence instead.
  Future<bool> openAt(String path) async {
    if (path.trim().isEmpty) return false;
    if (!_opener.isSupported) {
      setStatus(_opener.unsupportedMessage, error: true);
      notifyListeners();
      return false;
    }
    setStatus('Opening $path…');
    await _closeDocument();
    try {
      final document = await _opener.openFile(path);
      _document = document;
      pageCount = document.pageCount;
      openPath = path;
      openName = _baseName(path);
      openSize = 0;
      _pageCache.clear();
      _aspects.clear();
      renderZoom = controller.pdf.zoom;

      controller.pdf
        ..path = path
        ..name = openName
        ..documentId = document.id
        ..page = controller.pdf.page.clamp(1, pageCount)
        ..url = 'file://$path';
      controller.rememberPdfPath(path);
      controller.notifyChanged();

      setStatus('$openName · Page ${controller.pdf.page} of $pageCount');
      notifyListeners();
      await loadToc();
      return true;
    } catch (error) {
      controller.forgetPdfPath(path);
      setStatus('That file could not be opened as a PDF.', error: true);
      notifyListeners();
      return false;
    }
  }

  void closeDocument() {
    _closeDocument().then((_) {
      pageCount = 0;
      openPath = null;
      openName = '';
      _pageCache.clear();
      _aspects.clear();
      headings = const [];
      headingsMessage = 'Contents are extracted when a document opens.';
      controller.pdf.documentId = '';
      notifyListeners();
    });
  }

  Future<void> _closeDocument() async {
    _renderToken++;
    final document = _document;
    _document = null;
    if (document != null) {
      try {
        await document.close();
      } catch (_) {
        // The platform renderer may already have released it.
      }
    }
  }

  void navigateToPage(int page) {
    if (!isOpen) return;
    final target = page.clamp(1, pageCount);
    if (controller.pdf.page == target) return;
    controller.pdf.page = target;
    controller.touch();
    setStatus('$openName · Page $target of $pageCount');
    notifyListeners();
  }

  void changeZoom(double delta) {
    final next = (renderZoom + delta).clamp(0.6, 2.5);
    if (next == renderZoom) return;
    renderZoom = next;
    controller.pdf.zoom = next;
    _pageCache.clear();
    controller.touch();
    notifyListeners();
  }

  /// Renders one page at [pixelWidth] x [pixelHeight] to PNG bytes. Results
  /// are cached so scrolling back does not re-render, and the cache stays
  /// bounded.
  Future<Uint8List?> renderPage(
    int pageNumber, {
    required double pixelWidth,
    required double pixelHeight,
  }) {
    final cached = _pageCache[pageNumber];
    if (cached != null) return Future.value(cached);
    final document = _document;
    if (document == null) return Future.value(null);
    final token = _renderToken;
    return () async {
      try {
        final page = await document.getPage(pageNumber);
        if (page == null) return null;
        _aspects[pageNumber] = page.height / page.width;
        final data = await page.renderBytes(
          width: pixelWidth,
          height: pixelHeight,
        );
        await page.close();
        if (token != _renderToken) return null;
        if (data == null) return null;
        _rememberPage(pageNumber, data);
        notifyListeners();
        return data;
      } catch (_) {
        return null;
      }
    }();
  }

  static const int _maxCachedPages = 24;

  void _rememberPage(int pageNumber, Uint8List data) {
    _pageCache[pageNumber] = data;
    if (_pageCache.length > _maxCachedPages) {
      final oldest = _pageCache.keys.first;
      _pageCache.remove(oldest);
    }
  }

  /// Extracts the outline of the open document, preferring the host cache the
  /// original project kept under the data directory.
  Future<void> loadToc() async {
    final path = openPath;
    if (path == null) return;
    headingsLoading = true;
    headingsMessage = 'Reading contents…';
    notifyListeners();
    try {
      final file = await File(path).readAsBytes();
      final result = extractPdfOutline(file);
      headings = result.headings;
      headingsFromCache = false;
      if (result.headings.isEmpty) {
        headingsMessage = result.error ?? 'No contents found.';
      } else {
        headingsMessage =
            '${result.headings.length} heading${result.headings.length == 1 ? '' : 's'}';
      }
    } catch (_) {
      headings = const [];
      headingsMessage = 'The contents of this document could not be read.';
    } finally {
      headingsLoading = false;
      notifyListeners();
    }
  }

  void goToHeading(PdfOutlineEntry heading) {
    if (heading.page == null) return;
    navigateToPage(heading.page!);
  }

  String _baseName(String path) {
    final index = path.lastIndexOf(RegExp(r'[\\/]'));
    return index < 0 ? path : path.substring(index + 1);
  }
}
