import 'dart:convert';
import 'dart:io';

import 'package:chainnotes/core/workspace/workspace_models.dart';
import 'package:chainnotes/core/workspace/workspace_persistence.dart';
import 'package:chainnotes/core/workspace/workspace_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hydrateWorkspace merge rules', () {
    final boot = normalizeWorkspace({'savedAt': 200, 'view': 'editor'});

    test('a newer durable copy wins', () {
      final native = normalizeWorkspace({'savedAt': 300, 'view': 'pdf'});
      final chosen = hydrateWorkspace(
        boot: boot,
        native: native,
        hasNativeStore: true,
        userInteracted: false,
      );
      expect(chosen, isNotNull);
      expect(chosen!.view, 'pdf');
    });

    test('an older durable copy is ignored', () {
      final native = normalizeWorkspace({'savedAt': 100, 'view': 'pdf'});
      expect(
        hydrateWorkspace(
          boot: boot,
          native: native,
          hasNativeStore: true,
          userInteracted: false,
        ),
        isNull,
      );
    });

    test('a tie keeps the durable copy', () {
      final native = normalizeWorkspace({'savedAt': 200, 'view': 'images'});
      final chosen = hydrateWorkspace(
        boot: boot,
        native: native,
        hasNativeStore: true,
        userInteracted: false,
      );
      expect(chosen, isNotNull);
      expect(chosen!.view, 'images');
    });

    test('an empty durable store keeps the boot state', () {
      expect(
        hydrateWorkspace(
          boot: boot,
          native: null,
          hasNativeStore: true,
          userInteracted: false,
        ),
        isNull,
      );
    });

    test('user interaction short-circuits the load', () {
      final native = normalizeWorkspace({'savedAt': 300, 'view': 'map'});
      expect(
        hydrateWorkspace(
          boot: boot,
          native: native,
          hasNativeStore: true,
          userInteracted: true,
        ),
        isNull,
      );
    });

    test('no durable store means no hydration at all', () {
      final native = normalizeWorkspace({'savedAt': 300, 'view': 'map'});
      expect(
        hydrateWorkspace(
          boot: boot,
          native: native,
          hasNativeStore: false,
          userInteracted: false,
        ),
        isNull,
      );
    });
  });

  group('WorkspacePersistence', () {
    late Directory temp;
    late String cachePath;
    late String durablePath;
    late WorkspaceControllerStub controller;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('workspace-persist-test');
      cachePath =
          '${temp.path}${Platform.pathSeparator}cache${Platform.pathSeparator}workspace.json';
      durablePath = workspaceFilePath(temp.path);
      controller = WorkspaceControllerStub();
    });

    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    WorkspacePersistence build({bool hasNativeStore = true}) {
      final persistence = WorkspacePersistence(
        bridge: WorkspaceStoreBridge(
          cachePath: cachePath,
          durablePath: durablePath,
          hasNativeStore: hasNativeStore,
        ),
        snapshot: controller.snapshot,
        apply: controller.apply,
      );
      controller.attach(persistence);
      return persistence;
    }

    test('a flush writes the cache and the durable file', () {
      final persistence = build();
      controller.view = 'toc';
      expect(persistence.flush(), isTrue);
      expect(persistence.mode, PersistenceMode.native);

      final cache = jsonDecode(File(cachePath).readAsStringSync()) as Map;
      final durable = jsonDecode(File(durablePath).readAsStringSync()) as Map;
      expect(cache['view'], 'toc');
      expect(durable['view'], 'toc');
      expect(durable['savedAt'], greaterThan(0));
      persistence.dispose();
    });

    test('without a durable store the mode falls back to local', () {
      final persistence = build(hasNativeStore: false);
      controller.view = 'editor';
      expect(persistence.flush(), isTrue);
      expect(persistence.mode, PersistenceMode.local);
      expect(File(durablePath).existsSync(), isFalse);
      persistence.dispose();
    });

    test('a broken durable path falls back to the cache', () {
      final persistence = build();
      // A directory in the way makes the durable rename fail.
      Directory(durablePath).createSync(recursive: true);
      controller.view = 'editor';
      expect(persistence.flush(), isTrue);
      expect(persistence.mode, PersistenceMode.local);
      expect(File(cachePath).existsSync(), isTrue);
      persistence.dispose();
    });

    test('schedule debounces into a single write', () async {
      final persistence = build();
      controller.view = 'editor';
      persistence.schedule();
      persistence.schedule();
      persistence.schedule();
      expect(persistence.pendingSaves, 3);
      expect(persistence.hasPendingSave, isTrue);
      expect(File(durablePath).existsSync(), isFalse);

      await Future<void>.delayed(
        const Duration(milliseconds: saveDebounceMs + 80),
      );
      expect(persistence.hasPendingSave, isFalse);
      expect(persistence.pendingSaves, 0);
      expect(File(durablePath).existsSync(), isTrue);
      persistence.dispose();
    });

    test('hydrate applies the durable copy over an older boot snapshot', () {
      final persistence = build();
      controller.view = 'editor';
      persistence.flush();

      final boot = normalizeWorkspace({
        'savedAt': 1,
        'view': 'menu',
      });
      final applied = <WorkspaceRecord>[];
      final hydrating = WorkspacePersistence(
        bridge: WorkspaceStoreBridge(
          cachePath: cachePath,
          durablePath: durablePath,
        ),
        snapshot: controller.snapshot,
        apply: applied.add,
      );
      expect(hydrating.hydrate(boot), isTrue);
      expect(applied.single.view, 'editor');
      hydrating.dispose();
      persistence.dispose();
    });

    test('a damaged durable file reports INVALID_CONTENT', () {
      Directory(durablePath).parent.createSync(recursive: true);
      File(durablePath).writeAsStringSync('{ this is not json }');
      final persistence = build();
      expect(persistence.hydrate(normalizeWorkspace(null)), isFalse);
      expect(persistence.report?.code, 'INVALID_CONTENT');
      expect(
        formatWorkspaceReport(persistence.report),
        startsWith('Saved workspace not restored:'),
      );
      persistence.dispose();
    });

    test('save labels match the three modes', () {
      expect(saveLabelFor(PersistenceMode.native), 'saved to disk');
      expect(saveLabelFor(PersistenceMode.local), 'auto-saved');
      expect(saveLabelFor(PersistenceMode.none), 'not saved');
    });
  });
}

/// Minimal stand-in for the Flutter controller: the engine only ever calls
/// `snapshot()` and `apply()`.
class WorkspaceControllerStub {
  String view = 'menu';
  List<TocItem> tocItems = [];
  String? activeTocId;
  String editorContent = '';
  PdfSessionData pdf = PdfSessionData();
  ImageSessionData images = ImageSessionData();
  MapSessionData map = MapSessionData();
  GoogleMapSessionData googleMap = GoogleMapSessionData();

  WorkspacePersistence? persistence;

  void attach(WorkspacePersistence value) => persistence = value;

  WorkspaceRecord snapshot() => WorkspaceRecord(
        savedAt: DateTime.now().millisecondsSinceEpoch,
        view: view,
        tocItems: tocItems,
        activeTocId: activeTocId,
        editorContent: editorContent,
        pdf: pdf,
        images: images,
        map: map,
        googleMap: googleMap,
      );

  void apply(WorkspaceRecord record) {
    view = record.view;
    tocItems = record.tocItems;
    activeTocId = record.activeTocId;
    editorContent = record.editorContent;
    pdf = record.pdf;
    images = record.images;
    map = record.map;
    googleMap = record.googleMap;
  }
}
