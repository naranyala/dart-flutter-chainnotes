import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// The host pickers the desktop build provided as bindings: open a file, save a
/// file, choose a directory.
class FileService {
  const FileService();

  static const int maxTextBytes = 8 * 1024 * 1024;

  Future<String?> chooseDirectory({String? confirmButtonText}) async {
    return getDirectoryPath(confirmButtonText: confirmButtonText);
  }

  Future<String?> choosePath({
    required String suggestedName,
    List<String> extensions = const [],
    String label = 'File',
  }) async {
    try {
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: [
          if (extensions.isEmpty)
            const XTypeGroup(label: 'All files')
          else
            XTypeGroup(label: label, extensions: extensions),
        ],
      );
      return location?.path;
    } on Exception {
      return null;
    }
  }

  /// Opens a file picker and returns its absolute path, or null when the user
  /// cancels.
  Future<String?> chooseFile({
    List<String> extensions = const [],
    String label = 'File',
  }) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          if (extensions.isEmpty)
            const XTypeGroup(label: 'All files')
          else
            XTypeGroup(label: label, extensions: extensions),
        ],
      );
      return file?.path;
    } on Exception {
      return null;
    }
  }

  /// Reads a text file, refusing anything past the host's 8 MiB limit.
  Future<ReadTextFile> readTextFile(String path) async {
    final file = File(path);
    try {
      final size = await file.length();
      if (size > maxTextBytes) {
        return const ReadTextFile.error('That file is too large to open.');
      }
      final content = await file.readAsString();
      return ReadTextFile(_baseName(path), path, content);
    } on FileSystemException {
      return const ReadTextFile.error('That file could not be read.');
    } on FormatException {
      return const ReadTextFile.error('That file is not UTF-8 text.');
    }
  }

  Future<bool> writeTextFile(String path, String content) async {
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  static String _baseName(String path) {
    final index = path.lastIndexOf(RegExp(r'[\\/]'));
    return index < 0 ? path : path.substring(index + 1);
  }
}

class ReadTextFile {
  const ReadTextFile(this.name, this.path, this.content)
      : error = null;

  const ReadTextFile.error(this.error)
      : name = '',
        path = '',
        content = '';

  final String name;
  final String path;
  final String content;
  final String? error;

  bool get ok => error == null;
}

/// The `suggestFileName` helper: a filesystem-safe stem for an export.
/// An empty or all-dots title falls back to `outline`, like the PDF writer.
String suggestFileName(String title, String extension) {
  final cleaned = title
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  final stem = cleaned.isEmpty || cleaned.replaceAll('.', '').isEmpty
      ? 'outline'
      : (cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned);
  final withExtension =
      stem.toLowerCase().endsWith('.$extension') ? stem : '$stem.$extension';
  return withExtension;
}
