import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app/workspace_controller.dart';

const Set<String> imageExtensions = {
  'avif', 'bmp', 'gif', 'heic', 'heif', 'ico', 'jpeg', 'jpg', 'png', 'svg',
  'tif', 'tiff', 'webp',
};

const int scanMaxDepth = 8;
const int scanMaxFiles = 500;
const int scanMaxFileSize = 16 * 1024 * 1024;
const int scanMaxTotalSize = 96 * 1024 * 1024;
const int thumbnailMaxEdge = 320;
const int maxBrowserImages = 500;

class ImageEntry {
  ImageEntry({
    required this.name,
    required this.relativePath,
    required this.path,
    required this.mime,
    required this.size,
  });

  final String name;
  final String relativePath;
  final String path;
  final String mime;
  final int size;
}

class ImageGroup {
  ImageGroup(this.name, this.images);

  final String name;
  final List<ImageEntry> images;
}

/// The Image Viewer session: the directory scan, the folder groups, the grid,
/// and the lightbox.
class ImageSession extends ChangeNotifier {
  ImageSession(this.controller);

  final WorkspaceController controller;

  final ToolStatus status = ToolStatus('Browse images grouped by folder.');
  bool sidebarOpen = true;

  List<ImageEntry> images = const [];
  List<ImageGroup> groups = const [];
  bool limited = false;
  int fallbacks = 0;
  String directoryName = '';
  String directoryPath = '';

  int lightboxIndex = -1;

  bool get hasImages => images.isNotEmpty;

  String get badge {
    if (hasImages) {
      final group = controller.images.selectedGroup;
      if (group != 'All Images') return '$group · ${visibleImages.length} images';
      return '$directoryName · ${images.length} images';
    }
    final remembered = controller.images.recentPaths.length;
    if (remembered > 0) {
      return '$remembered remembered director${remembered == 1 ? 'y' : 'ies'}';
    }
    return 'Browse images grouped by folder';
  }

  List<ImageEntry> get visibleImages {
    final group = controller.images.selectedGroup;
    if (group == 'All Images') return images;
    for (final entry in groups) {
      if (entry.name == group) return entry.images;
    }
    return images;
  }

  void setStatus(String message, {bool error = false}) {
    status.set(message, error: error);
    notifyListeners();
  }

  void toggleSidebar() {
    sidebarOpen = !sidebarOpen;
    notifyListeners();
  }

  void selectGroup(String group) {
    controller.images.selectedGroup = group;
    lightboxIndex = -1;
    controller.touch();
    notifyListeners();
  }

  /// Scans [path] with the same budget the desktop host used: bounded depth,
  /// file count, and total bytes, so a huge tree cannot stall the app.
  Future<bool> openAt(String path) async {
    if (path.trim().isEmpty) return false;
    setStatus('Scanning $path…');
    final directory = Directory(path);
    if (!directory.existsSync()) {
      setStatus('That folder could not be opened.', error: true);
      return false;
    }

    final found = <ImageEntry>[];
    var limited = false;
    var total = 0;

    void walk(Directory current, String prefix, int depth) {
      if (depth > scanMaxDepth || found.length >= scanMaxFiles) return;
      List<FileSystemEntity> entries;
      try {
        entries = current.listSync(followLinks: false);
      } on FileSystemException {
        return;
      }
      final sorted = entries.toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final entry in sorted) {
        if (found.length >= scanMaxFiles) {
          limited = true;
          return;
        }
        if (entry is Directory) {
          final name = _baseName(entry.path);
          if (name.startsWith('.')) continue;
          walk(entry, prefix.isEmpty ? name : '$prefix/$name', depth + 1);
          continue;
        }
        if (entry is! File) continue;
        final name = _baseName(entry.path);
        if (name.startsWith('.')) continue;
        final extension = _extensionOf(name);
        if (!imageExtensions.contains(extension)) continue;
        final size = _fileLength(entry);
        if (size < 0 || size > scanMaxFileSize) {
          limited = true;
          continue;
        }
        if (total + size > scanMaxTotalSize) {
          limited = true;
          continue;
        }
        total += size;
        found.add(
          ImageEntry(
            name: name,
            relativePath: prefix.isEmpty ? name : '$prefix/$name',
            path: entry.path,
            mime: _mimeFor(extension),
            size: size,
          ),
        );
      }
    }

    walk(directory, '', 0);

    if (found.isEmpty) {
      setStatus('That folder contains no supported images.', error: true);
      notifyListeners();
      return false;
    }

    images = found;
    this.limited = limited;
    directoryName = _baseName(path);
    directoryPath = path;
    controller.images
      ..directoryName = directoryName
      ..directoryPath = path
      ..selectedGroup = 'All Images';
    controller.rememberImageDirectory(path);
    groups = _groupImages(found);
    lightboxIndex = -1;
    controller.notifyChanged();
    setStatus(
      limited
          ? '$directoryName · ${found.length} images (the scan reached its limit)'
          : '$directoryName · ${found.length} images',
    );
    notifyListeners();
    return true;
  }

  void clear() {
    images = const [];
    groups = const [];
    limited = false;
    directoryName = '';
    directoryPath = '';
    lightboxIndex = -1;
    notifyListeners();
  }

  void openLightbox(int index) {
    if (index < 0 || index >= visibleImages.length) return;
    lightboxIndex = index;
    notifyListeners();
  }

  void closeLightbox() {
    lightboxIndex = -1;
    notifyListeners();
  }

  /// Wrapping step, exactly like the original lightbox.
  void stepLightbox(int offset) {
    final list = visibleImages;
    if (list.length < 2 || lightboxIndex < 0) return;
    lightboxIndex = (lightboxIndex + offset + list.length) % list.length;
    notifyListeners();
  }

  bool attachCurrentToSection() {
    final list = visibleImages;
    if (lightboxIndex < 0 || lightboxIndex >= list.length) return false;
    final saved = controller.attachImages([list[lightboxIndex].path]);
    if (saved) {
      setStatus('Image attached to “${controller.linkTarget?.title}”.');
      notifyListeners();
    }
    return saved;
  }

  List<ImageGroup> _groupImages(List<ImageEntry> source) {
    final byFolder = <String, List<ImageEntry>>{};
    for (final entry in source) {
      final index = entry.relativePath.lastIndexOf('/');
      final folder = index < 0 ? '' : entry.relativePath.substring(0, index);
      byFolder.putIfAbsent(folder, () => <ImageEntry>[]).add(entry);
    }
    final names = byFolder.keys.toList()..sort();
    final groups = <ImageGroup>[
      ImageGroup('All Images', source),
      for (final name in names)
        if (name.isNotEmpty) ImageGroup(name, byFolder[name]!),
    ];
    return groups;
  }

  static String _baseName(String path) {
    final index = path.lastIndexOf(RegExp(r'[\\/]'));
    return index < 0 ? path : path.substring(index + 1);
  }

  static String _extensionOf(String name) {
    final index = name.lastIndexOf('.');
    return index < 0 ? '' : name.substring(index + 1).toLowerCase();
  }

  static int _fileLength(File file) {
    try {
      return file.lengthSync();
    } on FileSystemException {
      return -1;
    }
  }

  static String _mimeFor(String extension) => switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'bmp' => 'image/bmp',
        'svg' => 'image/svg+xml',
        'tif' || 'tiff' => 'image/tiff',
        'ico' => 'image/x-icon',
        'avif' => 'image/avif',
        'heic' => 'image/heic',
        'heif' => 'image/heif',
        _ => 'application/octet-stream',
      };
}
