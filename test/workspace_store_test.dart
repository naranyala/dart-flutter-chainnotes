import 'dart:io';

import 'package:chainnotes/core/workspace/workspace_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late String path;
  const store = WorkspaceStore();

  setUp(() {
    temp = Directory.systemTemp.createTempSync('workspace-store-test');
    path = '${temp.path}${Platform.pathSeparator}workspace.json';
    _clean(path);
  });

  tearDown(() {
    _clean(path);
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('strerror-style messages cover every result', () {
    for (final result in WorkspaceStoreResult.values) {
      expect(result.message, isNotEmpty);
    }
    expect(WorkspaceStoreResult.ok.message, 'ok');
  });

  test('a missing file loads as an empty payload, not an error', () {
    final loaded = store.load(path);
    expect(loaded.ok, isTrue);
    expect(loaded.data, '');
  });

  test('save then load round-trips bytes, escapes, and UTF-8', () {
    const payload = '{"view":"editor","note":"line\\nbreak \\"quoted\\" caf\\u00e9 \\u2713"}';
    expect(store.save(path, payload), WorkspaceStoreResult.ok);
    final loaded = store.load(path);
    expect(loaded.ok, isTrue);
    expect(loaded.data, payload);
    expect(workspaceStoreIsObject(loaded.data), isTrue);
  });

  test('a second save replaces the first completely', () {
    store.save(path, '{"view":"editor","extra":true}');
    store.save(path, '{"view":"menu","tocItems":[]}');
    expect(store.load(path).data, '{"view":"menu","tocItems":[]}');
  });

  test('an oversized payload is rejected before writing', () {
    final oversized = 'a' * (workspaceStoreMaxBytes + 1);
    expect(store.save(path, oversized), WorkspaceStoreResult.tooLarge);
    expect(File(path).existsSync(), isFalse);
  });

  test('a payload at the cap exactly is accepted', () {
    final exact = 'a' * workspaceStoreMaxBytes;
    expect(store.save(path, exact), WorkspaceStoreResult.ok);
    final loaded = store.load(path);
    expect(loaded.ok, isTrue);
    expect(loaded.data!.length, workspaceStoreMaxBytes);
  });

  test('an on-disk file over the cap is rejected before allocating', () {
    File(path).writeAsStringSync('x' * (workspaceStoreMaxBytes + 1));
    final loaded = store.load(path);
    expect(loaded.ok, isFalse);
    expect(loaded.result, WorkspaceStoreResult.tooLarge);
    expect(loaded.data, isNull);
  });

  test('the temp file is gone after a successful save', () {
    store.save(path, '{"a":1}');
    expect(File('$path.tmp').existsSync(), isFalse);
    expect(File(path).readAsStringSync(), '{"a":1}');
  });

  test('saving into a missing directory fails', () {
    final missing = '${temp.path}${Platform.pathSeparator}absent'
        '${Platform.pathSeparator}workspace.json';
    expect(store.save(missing, '{}'), WorkspaceStoreResult.write);
  });

  test('loading a directory fails', () {
    final loaded = store.load(temp.path);
    expect(loaded.ok, isFalse);
    expect(loaded.result, WorkspaceStoreResult.read);
    expect(loaded.data, isNull);
  });

  group('is_object (shallow)', () {
    test('accepts braced payloads with surrounding whitespace', () {
      expect(workspaceStoreIsObject('{ }'), isTrue);
      expect(workspaceStoreIsObject('  {\n"a":1}\n '), isTrue);
      expect(workspaceStoreIsObject('{}'), isTrue);
    });

    test('rejects everything else', () {
      expect(workspaceStoreIsObject('[]'), isFalse);
      expect(workspaceStoreIsObject(''), isFalse);
      expect(workspaceStoreIsObject(null), isFalse);
      expect(workspaceStoreIsObject('{'), isFalse);
      expect(workspaceStoreIsObject('{} trailing'), isFalse);
      expect(workspaceStoreIsObject('{"a":'), isFalse);
    });
  });

  test('the size cap is checked before the content is read', () {
    // The oversized file above is rejected on stat alone: the reader reports
    // `tooLarge` without ever handing back the bytes.
    File(path).writeAsStringSync('x' * (workspaceStoreMaxBytes + 1));
    final loaded = store.load(path);
    expect(loaded.result, WorkspaceStoreResult.tooLarge);
    expect(loaded.data, isNull);
  });

  test('parentOf splits on either separator', () {
    expect(parentOf('/a/b/workspace.json'), '/a/b');
    expect(parentOf('C:\\data\\workspace.json'), 'C:\\data');
    expect(parentOf('workspace.json'), '.');
  });
}

void _clean(String path) {
  final file = File(path);
  if (file.existsSync()) file.deleteSync();
  final temp = File('$path.tmp');
  if (temp.existsSync()) temp.deleteSync();
}
