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
  });

  bool supported;
  int pages;
  bool throwOnOpen;

  @override
  bool get isSupported => supported;

  @override
  String get unsupportedMessage => 'PDF rendering is not available here.';

  @override
  Future<PdfEngineDocument> openFile(String path) async {
    if (throwOnOpen) throw const FileSystemException('unreadable');
    return FakeEngineDocument(pageCount: pages);
  }
}

class FakeEngineDocument implements PdfEngineDocument {
  FakeEngineDocument({required this.pageCount});

  @override
  final int pageCount;

  @override
  String get id => 'fake-id';

  @override
  Future<PdfEnginePage?> getPage(int pageNumber) async => FakeEnginePage();

  @override
  Future<void> close() async {}
}

class FakeEnginePage implements PdfEnginePage {
  @override
  double get width => 100;

  @override
  double get height => 141.42;

  @override
  Future<Uint8List?> renderBytes({
    required double width,
    required double height,
  }) async => null;

  @override
  Future<void> close() async {}
}
