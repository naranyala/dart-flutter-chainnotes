import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chainnotes/app/theme.dart';
import 'package:chainnotes/app/workspace_controller.dart';
import 'package:chainnotes/core/map/tile_source.dart';
import 'package:chainnotes/core/workspace/workspace_models.dart';
import 'package:chainnotes/core/workspace/workspace_persistence.dart';
import 'package:chainnotes/sessions/image_session.dart';
import 'package:chainnotes/sessions/map_session.dart';
import 'package:chainnotes/sessions/pdf_session.dart';
import 'package:chainnotes/ui/editor_view.dart';
import 'package:chainnotes/ui/images_view.dart';
import 'package:chainnotes/ui/map_view.dart';
import 'package:chainnotes/ui/menu_view.dart';
import 'package:chainnotes/ui/pdf_view.dart';
import 'package:chainnotes/ui/shell.dart';
import 'package:chainnotes/ui/toc_view.dart';
import 'package:chainnotes/ui/widgets.dart';

/// Boots the real shell with every tool mounted, then walks the view switch to
/// make sure each pane builds without throwing.
void main() {
  testWidgets('shell mounts all six views without errors', (tester) async {
    final controller = WorkspaceController(boot: normalizeWorkspace(null));
    final pdf = PdfSession(controller);
    final images = ImageSession(controller);
    final map = MapSession(controller);
    final tiles = TileCache(
      cacheDirectory: Directory.systemTemp.createTempSync('chainnotes-tiles'),
      client: MockClient((_) async => http.Response('gone', 404)),
    );
    // The real footer, not a stub: the status bar Row carries flex children
    // (Spacer/Expanded) and once shipped wrapped in another Row, which threw
    // an unbounded-width exception on the very first frame. This guards it.
    final scratch =
        Directory.systemTemp.createTempSync('chainnotes-shell persist');
    final persistence = WorkspacePersistence(
      bridge: WorkspaceStoreBridge(
        cachePath: '${scratch.path}/workspace.json',
        durablePath: '${scratch.path}/native-workspace/workspace.json',
      ),
      snapshot: controller.snapshot,
      apply: controller.apply,
      onChanged: () {},
    );
    controller.persistence = persistence;
    final signal = ChangeNotifier();
    addTearDown(() {
      persistence.dispose();
      signal.dispose();
      scratch.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkspaceTheme(),
        home: WorkspaceShell(
          controller: controller,
          footer: WorkspaceStatusBar(
            controller: controller,
            signal: signal,
            persistence: persistence,
            onDismissReport: () {},
          ),
          views: [
            MenuView(
              controller: controller,
              pdf: pdf,
              images: images,
              map: map,
            ),
            TocView(
              controller: controller,
              pdf: pdf,
              images: images,
              map: map,
            ),
            EditorView(controller: controller),
            PdfView(controller: controller, pdf: pdf),
            ImagesView(controller: controller, images: images),
            MapView(controller: controller, map: map, tiles: tiles),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(MenuView), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final view in ['toc', 'editor', 'pdf', 'images', 'map', 'menu']) {
      controller.selectView(view);
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull, reason: 'view $view threw');
    }

    expect(controller.view, 'menu');
    expect(tester.takeException(), isNull);

    // Flush the debounce timer that the last selectView scheduled, so no
    // Timer is still pending when the tree is disposed.
    persistence.flush();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    tiles.dispose();
    controller.dispose();
  });

  testWidgets('the menu navbar spans the full window width', (tester) async {
    // A centered 1180px cap once left wide windows with big margins; the
    // navbar must always stretch edge to edge.
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final controller = WorkspaceController(boot: normalizeWorkspace(null));
    addTearDown(controller.dispose);
    final pdf = PdfSession(controller);
    addTearDown(pdf.dispose);
    final images = ImageSession(controller);
    addTearDown(images.dispose);
    final map = MapSession(controller);
    addTearDown(map.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWorkspaceTheme(),
        home: Scaffold(
          body: MenuView(
            controller: controller,
            pdf: pdf,
            images: images,
            map: map,
          ),
        ),
      ),
    );
    await tester.pump();
    final bar = tester.getRect(find.byKey(const Key('menu-navbar')));
    expect(bar.left, 0.0);
    expect(bar.width, 1600.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the status bar menu button shows the menu grid again',
      (tester) async {
    final controller = WorkspaceController(boot: normalizeWorkspace(null));
    addTearDown(controller.dispose);
    controller.selectView('toc');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuGridButton(controller: controller),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('show-menu-grid')));
    await tester.pump();
    expect(controller.view, 'menu');
    expect(tester.takeException(), isNull);
  });
}
