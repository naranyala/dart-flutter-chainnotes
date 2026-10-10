import 'dart:io';

import 'package:chainnotes/app/workspace_controller.dart';
import 'package:chainnotes/core/workspace/workspace_models.dart';
import 'package:chainnotes/core/workspace/workspace_persistence.dart';
import 'package:chainnotes/main.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks the composition root's boot wiring: `main` reads the boot cache,
/// builds the controller from that record, and hydrates against the *same*
/// record — so the merge compares two on-disk timestamps instead of a durable
/// copy against a freshly stamped snapshot (which would always lose).
void main() {
  late Directory root;
  late WorkspaceStoreBridge bridge;

  setUp(() {
    root = Directory.systemTemp.createTempSync('chainnotes-boot');
    bridge = WorkspaceStoreBridge(
      cachePath: '${root.path}/cache/workspace.json',
      durablePath: '${root.path}/support/native-workspace/workspace.json',
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  WorkspaceRecord record(int savedAt, String view) => WorkspaceRecord(
        savedAt: savedAt,
        view: view,
        editorContent: 'draft from $view',
      );

  test('a newer durable copy is applied through the boot wiring', () {
    expect(bridge.saveCache(serializeWorkspace(record(1000, 'menu'))), isTrue);
    expect(bridge.saveDurable(serializeWorkspace(record(2000, 'pdf'))), isTrue);

    final boot = readBootCache(bridge);
    expect(boot.view, 'menu');
    expect(boot.savedAt, 1000);

    final controller = WorkspaceController(boot: boot);
    final persistence = startPersistence(
      boot: boot,
      controller: controller,
      bridge: bridge,
    );

    expect(controller.view, 'pdf');
    expect(controller.editorContent, 'draft from pdf');
    expect(persistence.report, isNull);

    persistence.dispose();
    controller.dispose();
  });

  test('an older durable copy leaves the boot state in place', () {
    expect(bridge.saveCache(serializeWorkspace(record(2000, 'editor'))), isTrue);
    expect(bridge.saveDurable(serializeWorkspace(record(1000, 'map'))), isTrue);

    final boot = readBootCache(bridge);
    final controller = WorkspaceController(boot: boot);
    final persistence = startPersistence(
      boot: boot,
      controller: controller,
      bridge: bridge,
    );

    expect(controller.view, 'editor');
    expect(controller.editorContent, 'draft from editor');

    persistence.dispose();
    controller.dispose();
  });

  test('a damaged boot cache degrades to an empty workspace', () {
    File(bridge.cachePath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{ this is not json');

    final boot = readBootCache(bridge);
    expect(boot.tocItems, isEmpty);
    expect(boot.editorContent, isEmpty);

    final controller = WorkspaceController(boot: boot);
    final persistence = startPersistence(
      boot: boot,
      controller: controller,
      bridge: bridge,
    );

    expect(persistence.report, isNull);
    expect(controller.tocItems, isEmpty);

    persistence.dispose();
    controller.dispose();
  });

  test('hydration is a no-op without a native store', () {
    expect(bridge.saveCache(serializeWorkspace(record(1000, 'menu'))), isTrue);

    final boot = readBootCache(bridge);
    final controller = WorkspaceController(boot: boot);
    final memoryless = WorkspaceStoreBridge(
      cachePath: '${root.path}/cache/workspace.json',
      durablePath: '${root.path}/support/native-workspace/workspace.json',
      hasNativeStore: false,
    );
    final persistence = startPersistence(
      boot: boot,
      controller: controller,
      bridge: memoryless,
    );

    expect(controller.view, 'menu');
    expect(persistence.report, isNull);

    persistence.dispose();
    controller.dispose();
  });
}
