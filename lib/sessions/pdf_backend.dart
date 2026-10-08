import 'package:flutter/foundation.dart';
import 'package:pdfx/pdfx.dart';

/// The one seam between the PDF Reader and the native renderer.
///
/// `pdfx` ships native backends for Android, iOS, macOS, and Windows — but
/// not Linux — and its `PdfDocument.openFile` fires an unawaited platform
/// assert that escapes to the async zone on unsupported platforms, where no
/// caller-side `try/catch` can contain it. `PdfSession` therefore talks only
/// to this interface: production checks `isSupported` first and reports a
/// precise sentence instead of touching `pdfx` where it cannot work, and
/// tests inject a fake without any platform channel.
abstract class PdfOpener {
  /// Whether the current platform has a `pdfx` renderer.
  bool get isSupported;

  /// The sentence shown when [isSupported] is false.
  String get unsupportedMessage;

  Future<PdfDocument> openFile(String path);
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
  Future<PdfDocument> openFile(String path) =>
      PdfDocument.openFile(path);
}
