import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the documentation in step with the tree.
///
/// Three things are guarded, because each is a way a document silently stops
/// being true: the README repository map (both directions), the documentation
/// index links, and the commands the README quotes.
void main() {
  final readme = File('README.md');
  final docsIndex = File('docs/README.md');
  final development = File('docs/development.md');

  late String readmeText;
  late String mapBlock;

  setUpAll(() {
    readmeText = readme.readAsStringSync();
    mapBlock = _repositoryMapBlock(readmeText);
  });

  group('repository map', () {
    test('is present in the README', () {
      expect(mapBlock, isNotEmpty,
          reason: 'The README must contain a ```text repository map block '
              'under "## Repository map".');
    });

    test('every path it names exists', () {
      final missing = <String>[];
      for (final path in _pathsIn(mapBlock)) {
        if (!File(path).existsSync() && !Directory(path).existsSync()) {
          missing.add(path);
        }
      }
      expect(missing, isEmpty,
          reason: 'The repository map names files that are not in the tree: '
              '$missing');
    });

    test('every Dart source file appears in it', () {
      final unlisted = <String>[];
      for (final file in _dartFiles('lib')) {
        if (!mapBlock.contains(file.path)) unlisted.add(file.path);
      }
      for (final file in _dartFiles('test')) {
        if (!mapBlock.contains(file.path)) unlisted.add(file.path);
      }
      expect(unlisted, isEmpty,
          reason: 'These source files exist but are missing from the README '
              'repository map: $unlisted');
    });

    test('names no Dart file that has been deleted', () {
      final dead = <String>[];
      for (final path in _pathsIn(mapBlock)) {
        if (!path.endsWith('.dart')) continue;
        if (!File(path).existsSync()) dead.add(path);
      }
      expect(dead, isEmpty,
          reason: 'The repository map lists deleted files: $dead');
    });
  });

  group('documentation index', () {
    test('every link in docs/README.md resolves', () {
      final broken = <String>[];
      final base = Directory('docs').absolute.path;
      for (final target in _markdownLinks(docsIndex.readAsStringSync())) {
        if (target.startsWith('http') || target.startsWith('#')) continue;
        final clean = target.split('#').first;
        if (clean.isEmpty) continue;
        final path = '$base${Platform.pathSeparator}$clean';
        if (!File(path).existsSync() && !Directory(path).existsSync()) {
          broken.add(target);
        }
      }
      expect(broken, isEmpty,
          reason: 'docs/README.md links to documents that do not exist: '
              '$broken');
    });

    test('every guide in docs/ is listed in the index', () {
      final index = docsIndex.readAsStringSync();
      final unlisted = Directory('docs')
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.md'))
          .where((p) => p != 'docs${Platform.pathSeparator}README.md')
          .where((p) => !index.contains(p.split(Platform.pathSeparator).last))
          .toList();
      expect(unlisted, isEmpty,
          reason: 'These guides exist in docs/ but are not linked from '
              'docs/README.md: $unlisted');
    });
  });

  group('commands', () {
    test('every flutter command quoted in the README is documented', () {
      final doc = development.readAsStringSync();
      final undocumented = <String>[];
      for (final line in readmeText.split('\n')) {
        final trimmed = line.trimRight();
        if (!trimmed.trim().startsWith('flutter ')) continue;
        if (!doc.contains(trimmed.trim())) {
          undocumented.add(trimmed.trim());
        }
      }
      expect(undocumented, isEmpty,
          reason: 'The README quotes commands that docs/development.md does '
              'not document: $undocumented');
    });

    test('every guide link in the README resolves', () {
      final broken = <String>[];
      for (final target in _markdownLinks(readmeText)) {
        if (target.startsWith('http') || target.startsWith('#')) continue;
        final clean = target.split('#').first;
        if (clean.isEmpty) continue;
        final path = clean.startsWith('./')
            ? clean.substring(2)
            : clean;
        if (!File(path).existsSync() && !Directory(path).existsSync()) {
          broken.add(target);
        }
      }
      expect(broken, isEmpty,
          reason: 'The README links to paths that do not exist: $broken');
    });
  });
}

/// The fenced ```text block that follows the "## Repository map" heading.
String _repositoryMapBlock(String text) {
  final heading = text.indexOf('## Repository map');
  if (heading < 0) return '';
  final start = text.indexOf('```text', heading);
  if (start < 0) return '';
  final end = text.indexOf('```', start + 7);
  if (end < 0) return '';
  return text.substring(start + 7, end);
}

/// The first whitespace-separated token of each line, when it looks like a
/// repository path rather than a section rule (`--- core ---`).
List<String> _pathsIn(String block) {
  final paths = <String>[];
  for (final raw in block.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;
    final token = line.split(RegExp(r'\s+')).first;
    if (token.startsWith('---')) continue;
    if (token.startsWith('lib/') ||
        token.startsWith('test/') ||
        token.startsWith('docs/') ||
        token == 'PYRAMID-OF-INTENTS.md' ||
        token == 'TODOS.md') {
      paths.add(token);
    }
  }
  return paths;
}

List<File> _dartFiles(String dir) {
  final root = Directory(dir);
  if (!root.existsSync()) return const [];
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

List<String> _markdownLinks(String text) {
  final pattern = RegExp(r'\[[^\]]*\]\(([^)]+)\)');
  return pattern
      .allMatches(text)
      .map((m) => m.group(1)!.trim())
      .toList();
}
