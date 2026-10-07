import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chainnotes/app/workspace_controller.dart';
import 'package:chainnotes/core/map/tile_source.dart';
import 'package:chainnotes/core/workspace/workspace_models.dart';
import 'package:chainnotes/sessions/image_session.dart';
import 'package:chainnotes/sessions/map_session.dart';
import 'package:chainnotes/sessions/pdf_session.dart';
import 'package:chainnotes/ui/editor_view.dart';
import 'package:chainnotes/ui/map_view.dart';
import 'package:chainnotes/ui/toc_view.dart';

WorkspaceController freshController() =>
    WorkspaceController(boot: normalizeWorkspace(null));

Widget tocHarness(WorkspaceController controller) {
  final pdf = PdfSession(controller);
  final images = ImageSession(controller);
  final map = MapSession(controller);
  return MaterialApp(
    home: Scaffold(
      body: TocView(controller: controller, pdf: pdf, images: images, map: map),
    ),
  );
}

void main() {
  group('TOC Manager interactions', () {
    testWidgets('declaring a section from the toolbar shows a row',
        (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(tocHarness(controller));
      await tester.enterText(
          find.byKey(const Key('toc-title-input')), 'First chapter');
      await tester.tap(find.text('Add section'));
      await tester.pump();
      expect(controller.tocItems.single.title, 'First chapter');
      expect(find.text('First chapter'), findsWidgets);
    });

    testWidgets('an empty title is refused with a status sentence',
        (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(tocHarness(controller));
      await tester.tap(find.text('Add section'));
      await tester.pump();
      expect(controller.tocItems, isEmpty);
      expect(controller.tocStatus.isError, isTrue);
      expect(controller.tocStatus.message, contains('heading title'));
    });

    testWidgets('moving a section down swaps the visible order',
        (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Alpha', level: 1);
      controller.addTocItem(title: 'Beta', level: 1);
      await tester.pumpWidget(tocHarness(controller));
      await tester.pump();
      await tester.tap(find.byTooltip('Move down').first);
      await tester.pump();
      expect(
          controller.tocItems.map((e) => e.title).toList(), ['Beta', 'Alpha']);
    });

    testWidgets('removing a section can be undone', (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Gone', level: 1);
      await tester.pumpWidget(tocHarness(controller));
      await tester.pump();
      controller.removeTocItem(controller.tocItems.single);
      await tester.pump();
      expect(controller.tocItems, isEmpty);
      expect(find.text('Undo remove'), findsOneWidget);
      await tester.tap(find.text('Undo remove'));
      await tester.pump();
      expect(controller.tocItems.single.title, 'Gone');
    });

    testWidgets('a filter narrows the visible rows', (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      for (var i = 0; i < 8; i++) {
        controller.addTocItem(title: 'Section $i', level: 1);
      }
      await tester.pumpWidget(tocHarness(controller));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).last, 'Section 1');
      await tester.pump();
      expect(find.text('Section 1'), findsWidgets);
      expect(find.text('Section 2'), findsNothing);
    });
  });

  group('Text Editor binding', () {
    testWidgets('selecting an item loads its draft and typing updates it',
        (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Draft', level: 1);
      controller.selectTocItem(controller.tocItems.single);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: EditorView(controller: controller)),
      ));
      await tester.pump();
      await tester.enterText(
          find.byKey(const Key('values')), 'hello world');
      await tester.pump();
      expect(controller.editorContent, 'hello world');
      expect(controller.activeTocItem!.content, 'hello world');
    });
  });

  group('Cross-tool links and transfers', () {
    test('attaching a PDF page binds it to the selected outline item', () {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Source', level: 1);
      controller.selectTocItem(controller.tocItems.single);
      // No persistence is attached in this test, so the write reports false
      // while still binding the link on the item.
      controller.attachPdfPage(7, 'doc.pdf');
      expect(controller.tocItems.single.links.pdfPage, 7);
    });

    test('a non-outline import reports a sentence, not an exception', () {
      final controller = freshController();
      addTearDown(controller.dispose);
      expect(controller.importTocJson('{"format":"nope"}'), -1);
      expect(controller.tocStatus.isError, isTrue);
      expect(controller.tocStatus.message,
          'That file is not an outline export.');
    });

    test('export then import round-trips the outline', () {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Keep', level: 2);
      final payload = controller.exportTocJson();
      final into = freshController();
      addTearDown(into.dispose);
      expect(into.importTocJson(payload), 1);
      expect(into.tocItems.single.title, 'Keep');
    });

    test('importing PDF headings appends sections', () {
      final controller = freshController();
      addTearDown(controller.dispose);
      final added = controller.importPdfHeadings([
        {'title': 'Intro', 'level': 1, 'page': 2},
        {'title': '', 'level': 1, 'page': 3},
      ], 'doc.pdf');
      expect(added, 1);
      expect(controller.tocItems.single.links.pdfPage, 2);
    });
  });

  group('Map Explorer places', () {
    testWidgets('saving, renaming, and removing a place updates the view',
        (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      final tiles = TileCache(
        cacheDirectory:
            Directory.systemTemp.createTempSync('chainnotes-tiles'),
        client: MockClient((_) async => http.Response('gone', 404)),
      );
      addTearDown(tiles.dispose);
      controller.addTocItem(title: 'Field trip', level: 1);
      final place =
          controller.addPlace(lat: 48.85, lon: 2.35, label: 'Paris');
      expect(place, isNotNull);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MapView(controller: controller, map: map, tiles: tiles)),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Paris'), findsWidgets);
      controller.renamePlace(place!, 'Paris centre');
      await tester.pump();
      expect(
          controller.map.places.single.label, 'Paris centre');
      controller.removePlace(place);
      await tester.pump();
      expect(controller.map.places, isEmpty);
    });
  });

  group('Image lightbox', () {
    test('stepping wraps around the image list', () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final session = ImageSession(controller);
      addTearDown(session.dispose);
      final dir =
          Directory.systemTemp.createTempSync('chainnotes-images');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (var i = 0; i < 3; i++) {
        File('${dir.path}${Platform.pathSeparator}img$i.png')
            .writeAsBytesSync([1, 2, 3]);
      }
      expect(await session.openAt(dir.path), isTrue);
      session.openLightbox(2);
      session.stepLightbox(1);
      expect(session.lightboxIndex, 0);
      session.stepLightbox(-1);
      expect(session.lightboxIndex, 2);
    });
  });
}
