import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:pdfx/pdfx.dart' as pdfx;

/// The one seam between the PDF Reader and the native renderers.
///
/// Two renderers hide behind it: `pdfx` on Android, iOS, macOS, and Windows,
/// and `pdfrx` (PDFium) on Linux, where `pdfx` ships no backend and its
/// `PdfDocument.openFile` fires an unawaited platform assert that no
/// caller-side `try/catch` can contain. `PdfSession` therefore talks only to
/// these engine-neutral handles: production picks one via
/// [platformPdfOpener], and tests inject a fake without any platform channel.
abstract class PdfEngineDocument {
  /// How many pages the document holds.
  int get pageCount;

  /// Identifies the open document for the record. The `pdfx` backend reports
  /// its native id; the `pdfrx` backend reports the path it opened.
  String get id;

  /// The 1-based page, or null when out of range. The caller closes it.
  Future<PdfEnginePage?> getPage(int pageNumber);

  /// Releases the document.
  Future<void> close();
}

/// One rendered page: its size in points and a byte renderer for the reader.
abstract class PdfEnginePage {
  /// Page width in points (pixels at 72 dpi).
  double get width;

  /// Page height in points (pixels at 72 dpi).
  double get height;

  /// Renders the page to PNG bytes at [width] x [height] pixels, or null
  /// when the page cannot be rendered.
  Future<Uint8List?> renderBytes({
    required double width,
    required double height,
  });

  /// Releases the page.
  Future<void> close();
}

/// Opens documents behind [PdfEngineDocument].
abstract class PdfOpener {
  /// Whether the current platform has a renderer behind this opener.
  bool get isSupported;

  /// The sentence shown when [isSupported] is false.
  String get unsupportedMessage;

  Future<PdfEngineDocument> openFile(String path);
}

/// Picks the renderer for the running platform: `pdfrx` (PDFium) on Linux,
/// where `pdfx` has no backend, `pdfx` everywhere else. This is what
/// production passes to `PdfSession`; tests inject fakes.
PdfOpener platformPdfOpener() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    return const PdfrxOpener();
  }
  return const PdfxOpener();
}

class PdfxOpener implements PdfOpener {
  const PdfxOpener();

  @override
  bool get isSupported {
    // Web reports a desktop platform via defaultTargetPlatform, but pdfx
    // has no web renderer behind this seam — refuse before touching it.
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  @override
  String get unsupportedMessage =>
      'PDF rendering is not available on this platform.';

  @override
  Future<PdfEngineDocument> openFile(String path) async =>
      _PdfxDocument(await pdfx.PdfDocument.openFile(path));
}

class _PdfxDocument implements PdfEngineDocument {
  _PdfxDocument(this._document);

  final pdfx.PdfDocument _document;

  @override
  int get pageCount => _document.pagesCount;

  @override
  String get id => _document.id;

  @override
  Future<PdfEnginePage?> getPage(int pageNumber) async =>
      _PdfxPage(await _document.getPage(pageNumber));

  @override
  Future<void> close() => _document.close();
}

class _PdfxPage implements PdfEnginePage {
  _PdfxPage(this._page);

  final pdfx.PdfPage _page;

  @override
  double get width => _page.width;

  @override
  double get height => _page.height;

  @override
  Future<Uint8List?> renderBytes({
    required double width,
    required double height,
  }) async {
    final image = await _page.render(
      width: width.clamp(1, 8192),
      height: height.clamp(1, 8192),
      format: pdfx.PdfPageImageFormat.jpeg,
      backgroundColor: '#FFFFFF',
      quality: 85,
    );
    return image?.bytes;
  }

  @override
  Future<void> close() => _page.close();
}

/// The Linux renderer: `pdfrx` bundles PDFium for Linux (even Raspberry Pi)
/// through native assets, so pages render where `pdfx` cannot.
class PdfrxOpener implements PdfOpener {
  const PdfrxOpener();

  @override
  bool get isSupported {
    if (kIsWeb) return false;
    // `pdfrx` covers every native platform, but only Linux needs it here;
    // keeping `pdfx` elsewhere preserves the tested mobile behaviour.
    return defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  String get unsupportedMessage =>
      'PDF rendering is not available on this platform.';

  @override
  Future<PdfEngineDocument> openFile(String path) async =>
      _PdfrxDocument(await pdfrx.PdfDocument.openFile(path), path);
}

class _PdfrxDocument implements PdfEngineDocument {
  _PdfrxDocument(this._document, this._path);

  final pdfrx.PdfDocument _document;
  final String _path;

  @override
  int get pageCount => _document.pages.length;

  @override
  String get id => _path;

  @override
  Future<PdfEnginePage?> getPage(int pageNumber) async {
    if (pageNumber < 1 || pageNumber > _document.pages.length) return null;
    return _PdfrxPage(_document.pages[pageNumber - 1]);
  }

  @override
  Future<void> close() => _document.dispose();
}

class _PdfrxPage implements PdfEnginePage {
  _PdfrxPage(this._page);

  final pdfrx.PdfPage _page;

  @override
  double get width => _page.width;

  @override
  double get height => _page.height;

  @override
  Future<Uint8List?> renderBytes({
    required double width,
    required double height,
  }) async {
    final rendered = await _page.render(
      fullWidth: width.roundToDouble().clamp(1, 8192),
      fullHeight: height.roundToDouble().clamp(1, 8192),
    );
    if (rendered == null) return null;
    try {
      final uiImage = await rendered.createImage();
      try {
        final data =
            await uiImage.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        uiImage.dispose();
      }
    } finally {
      rendered.dispose();
    }
  }

  @override
  Future<void> close() async {}
}
