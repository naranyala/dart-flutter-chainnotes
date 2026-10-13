import 'dart:io';
import 'dart:typed_data';

import 'package:chainnotes/app/services.dart';
import 'package:chainnotes/sessions/pdf_backend.dart';

/// A 1x1 transparent PNG: small enough to inline, valid enough to decode —
/// for tests that need a real image file on disk.
const List<int> kTinyPng = [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, //
  0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, //
  0, 0, 0, 10, 73, 68, 65, 84, 120, 156, 99, 0, 1, 0, 0, 5, 0, 1, //
  13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
];

/// A scripted `file_selector` stand-in shared by widget tests: pickers return
/// canned paths (or null for a dismissed dialog), reads serve canned content,
/// writes are captured. No platform channel involved.
class FakeFileService extends FileService {
  FakeFileService({
    this.pickedFile,
    this.pickedPath,
    this.pickedDirectory,
    Map<String, String>? files,
  }) : files = files ?? {};

  String? pickedFile;
  String? pickedPath;
  String? pickedDirectory;
  final Map<String, String> files;
  final Map<String, String> written = {};

  @override
  Future<String?> chooseFile({
    List<String> extensions = const [],
    String label = 'File',
  }) async => pickedFile;

  @override
  Future<String?> choosePath({
    required String suggestedName,
    List<String> extensions = const [],
    String label = 'File',
  }) async => pickedPath;

  @override
  Future<String?> chooseDirectory({String? confirmButtonText}) async =>
      pickedDirectory;

  @override
  Future<ReadTextFile> readTextFile(String path) async {
    final content = files[path];
    if (content != null) {
      final slash = path.lastIndexOf(RegExp(r'[\\/]'));
      final name = slash < 0 ? path : path.substring(slash + 1);
      return ReadTextFile(name, path, content);
    }
    return super.readTextFile(path);
  }

  @override
  Future<bool> writeTextFile(String path, String content) async {
    written[path] = content;
    return true;
  }
}

/// A scripted renderer stand-in: no platform channel, no native renderer.
class FakePdfOpener implements PdfOpener {
  FakePdfOpener({
    this.supported = true,
    this.pages = 2,
    this.throwOnOpen = false,
    this.docId = 'fake-id',
    this.pageBytes,
  });

  bool supported;
  int pages;
  bool throwOnOpen;
  String docId;

  /// Fixed render bytes for every page (null keeps the failure path).
  Uint8List? pageBytes;

  /// The most recently opened document, for call-count assertions.
  FakeEngineDocument? lastDocument;

  @override
  bool get isSupported => supported;

  @override
  String get unsupportedMessage => 'PDF rendering is not available here.';

  @override
  Future<PdfEngineDocument> openFile(String path) async {
    if (throwOnOpen) throw const FileSystemException('unreadable');
    return lastDocument = FakeEngineDocument(
      pageCount: pages,
      docId: docId,
      pageBytes: pageBytes,
    );
  }
}

class FakeEngineDocument implements PdfEngineDocument {
  FakeEngineDocument({
    required this.pageCount,
    this.docId = 'fake-id',
    this.pageBytes,
  });

  @override
  final int pageCount;

  @override
  String get id => docId;

  final String docId;

  /// Fixed render bytes handed to every page (null keeps the failure path).
  final Uint8List? pageBytes;

  /// Counts `getPage` calls so tests can tell a re-render from a cache hit.
  int getPageCalls = 0;

  @override
  Future<PdfEnginePage?> getPage(int pageNumber) async {
    getPageCalls++;
    return FakeEnginePage(bytes: pageBytes);
  }

  @override
  Future<void> close() async {}
}
class FakeEnginePage implements PdfEnginePage {
  FakeEnginePage({this.bytes});

  /// Render result (null keeps the render-failure path).
  final Uint8List? bytes;

  @override
  double get width => 100;

  @override
  double get height => 141.42;

  @override
  Future<Uint8List?> renderBytes({
    required double width,
    required double height,
  }) async =>
      bytes;

  @override
  Future<void> close() async {}
}
