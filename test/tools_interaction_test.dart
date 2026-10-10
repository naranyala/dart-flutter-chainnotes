import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chainnotes/app/services.dart';
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
import 'package:chainnotes/ui/pdf_view.dart';
import 'package:chainnotes/ui/toc_view.dart';

import 'fakes.dart';

WorkspaceController freshController() =>
    WorkspaceController(boot: normalizeWorkspace(null));

/// Reads the keyboard action off a keyed `TextFormField` through its inner
/// `TextField` (the form widget itself exposes no getter).
TextInputAction fieldAction(WidgetTester tester, String key) {
  final field = find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(TextField),
  );
  return tester.widget<TextField>(field).textInputAction ??
      TextInputAction.done;
}

Widget tocHarness(WorkspaceController controller, {FileService? files}) {
  final pdf = PdfSession(controller);
  final images = ImageSession(controller);
  final map = MapSession(controller);
  return MaterialApp(
    home: Scaffold(
      body: TocView(
        controller: controller,
        pdf: pdf,
        images: images,
        map: map,
        files: files ?? const FileService(),
      ),
    ),
  );
}

void main() {
  group('TOC Manager interactions', () {
    testWidgets('declaring a section from the toolbar shows a row', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(tocHarness(controller));
      await tester.enterText(
        find.byKey(const Key('toc-title-input')),
        'First chapter',
      );
      await tester.tap(find.text('Add section'));
      await tester.pump();
      expect(controller.tocItems.single.title, 'First chapter');
      expect(find.text('First chapter'), findsWidgets);
    });

    testWidgets('an empty title is refused with a status sentence', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(tocHarness(controller));
      await tester.tap(find.text('Add section'));
      await tester.pump();
      expect(controller.tocItems, isEmpty);
      expect(controller.tocStatus.isError, isTrue);
      expect(controller.tocStatus.message, contains('heading title'));
    });

    testWidgets('moving a section down swaps the visible order', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Alpha', level: 1);
      controller.addTocItem(title: 'Beta', level: 1);
      await tester.pumpWidget(tocHarness(controller));
      await tester.pump();
      await tester.tap(find.byTooltip('Move down').first);
      await tester.pump();
      expect(controller.tocItems.map((e) => e.title).toList(), [
        'Beta',
        'Alpha',
      ]);
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
    testWidgets('selecting an item loads its draft and typing updates it', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Draft', level: 1);
      controller.selectTocItem(controller.tocItems.single);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EditorView(controller: controller)),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byKey(const Key('values')), 'hello world');
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
      expect(
        controller.tocStatus.message,
        'That file is not an outline export.',
      );
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

    testWidgets('cancelling the JSON import leaves the outline alone', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Keep', level: 1);
      await tester.pumpWidget(tocHarness(controller, files: FakeFileService()));
      await tester.pump();
      await tester.tap(find.text('Import…'));
      await tester.pump();
      expect(controller.tocItems.single.title, 'Keep');
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelling the JSON export writes nothing', (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Keep', level: 1);
      await tester.pumpWidget(tocHarness(controller, files: FakeFileService()));
      await tester.pump();
      final before = controller.tocStatus.message;
      await tester.tap(find.text('Export…'));
      await tester.pump();
      expect(controller.tocStatus.message, before);
      expect(find.text('Outline exported.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelling combine-to-PDF says no folder was chosen', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Keep', level: 1);
      await tester.pumpWidget(tocHarness(controller, files: FakeFileService()));
      await tester.pump();
      await tester.ensureVisible(find.text('Combine to PDF'));
      await tester.pump();
      await tester.tap(find.text('Combine to PDF'));
      await tester.pump();
      expect(controller.tocStatus.message, 'No folder chosen.');
      expect(tester.takeException(), isNull);
    });

    testWidgets('fields offer the right keyboard actions', (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      for (var i = 0; i < 8; i++) {
        controller.addTocItem(title: 'Section $i', level: 1);
      }
      await tester.pumpWidget(tocHarness(controller));
      await tester.pump();
      expect(fieldAction(tester, 'toc-title-input'), TextInputAction.done);
      expect(fieldAction(tester, 'toc-filter-input'), TextInputAction.search);
      expect(tester.takeException(), isNull);
    });
  });

  group('Map Explorer places', () {
    testWidgets('saving, renaming, and removing a place updates the view', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      final tiles = TileCache(
        cacheDirectory: Directory.systemTemp.createTempSync('chainnotes-tiles'),
        client: MockClient((_) async => http.Response('gone', 404)),
      );
      addTearDown(tiles.dispose);
      controller.addTocItem(title: 'Field trip', level: 1);
      final place = controller.addPlace(lat: 48.85, lon: 2.35, label: 'Paris');
      expect(place, isNotNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapView(controller: controller, map: map, tiles: tiles),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Paris'), findsWidgets);
      controller.renamePlace(place!, 'Paris centre');
      await tester.pump();
      expect(controller.map.places.single.label, 'Paris centre');
      controller.removePlace(place);
      await tester.pump();
      expect(controller.map.places, isEmpty);
    });

    test('stepping wraps around both ends and reports position', () {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      controller.addPlace(lat: 10, lon: 10, label: 'Alpha');
      controller.addPlace(lat: 20, lon: 20, label: 'Beta');
      // addPlace re-tops, so the order is [Beta, Alpha].
      map.stepPlace(1);
      expect(map.selectedPlaceId, controller.map.places[0].id);
      expect(map.status.message, 'Viewing “Beta” (1 of 2).');
      map.stepPlace(1);
      expect(map.selectedPlaceId, controller.map.places[1].id);
      expect(map.status.message, 'Viewing “Alpha” (2 of 2).');
      map.stepPlace(1);
      expect(map.selectedPlaceId, controller.map.places[0].id);
      map.stepPlace(-1);
      expect(map.selectedPlaceId, controller.map.places[1].id);
    });

    test('stepping with no places explains itself', () {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      map.stepPlace(1);
      expect(map.status.isError, isTrue);
      expect(map.selectedPlaceId, isNull);
    });

    test('typed coordinates fly the pin there or explain why not', () {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      expect(map.goToCoordinates('48.85', '2.35'), isTrue);
      expect(map.pin!.lat, closeTo(48.85, 1e-9));
      expect(map.pin!.lon, closeTo(2.35, 1e-9));
      expect(map.flyLat, closeTo(48.85, 1e-9));
      expect(map.flyLon, closeTo(2.35, 1e-9));
      expect(map.goToCoordinates('abc', '2.35'), isFalse);
      expect(map.status.isError, isTrue);
      expect(map.goToCoordinates('100', '0'), isFalse);
      expect(map.status.isError, isTrue);
      expect(map.goToCoordinates('', ''), isFalse);
      expect(map.status.isError, isTrue);
    });

    test('saving the centre stores the viewport and selects it', () {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      map.setCenter(11, 22);
      map.saveCenterAsPlace();
      expect(controller.map.places.single.lat, 11);
      expect(controller.map.places.single.lon, 22);
      expect(map.selectedPlaceId, controller.map.places.single.id);
    });

    testWidgets('the stepper walks saved places and wraps', (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      final tiles = TileCache(
        cacheDirectory: Directory.systemTemp.createTempSync(
          'chainnotes-tiles-step',
        ),
        client: MockClient((_) async => http.Response('gone', 404)),
      );
      addTearDown(tiles.dispose);
      controller.addPlace(lat: 10, lon: 10, label: 'Alpha');
      controller.addPlace(lat: 20, lon: 20, label: 'Beta');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapView(controller: controller, map: map, tiles: tiles),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('2 saved'), findsOneWidget);
      await tester.tap(find.byKey(const Key('place-next')));
      await tester.pump();
      expect(find.text('1 of 2'), findsOneWidget);
      expect(map.selectedPlaceId, controller.map.places[0].id);
      await tester.tap(find.byKey(const Key('place-next')));
      await tester.pump();
      expect(find.text('2 of 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('place-next')));
      await tester.pump();
      expect(find.text('1 of 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('place-prev')));
      await tester.pump();
      expect(find.text('2 of 2'), findsOneWidget);
    });

    testWidgets('going to typed coordinates drops a pin from the sidebar', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      final tiles = TileCache(
        cacheDirectory: Directory.systemTemp.createTempSync(
          'chainnotes-tiles-goto',
        ),
        client: MockClient((_) async => http.Response('gone', 404)),
      );
      addTearDown(tiles.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapView(controller: controller, map: map, tiles: tiles),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.byKey(const Key('goto-button')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('lat-input')), '48.85');
      await tester.enterText(find.byKey(const Key('lon-input')), '2.35');
      await tester.tap(find.byKey(const Key('goto-button')));
      await tester.pump();
      expect(map.pin, isNotNull);
      expect(map.pin!.lat, closeTo(48.85, 1e-9));
      expect(find.textContaining('48.85'), findsWidgets);
      await tester.enterText(find.byKey(const Key('lat-input')), 'abc');
      await tester.ensureVisible(find.byKey(const Key('goto-button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('goto-button')));
      await tester.pump();
      expect(map.status.isError, isTrue);
      expect(
        find.text('Enter coordinates as numbers, like 48.8566, 2.3522.'),
        findsWidgets,
      );
    });

    testWidgets('markers and place titles meet the 44 px touch target', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      final tiles = TileCache(
        cacheDirectory: Directory.systemTemp.createTempSync(
          'chainnotes-tiles-target',
        ),
        client: MockClient((_) async => http.Response('gone', 404)),
      );
      addTearDown(tiles.dispose);
      final place = controller.addPlace(lat: 10, lon: 10, label: 'Alpha')!;
      map.setCenter(10, 10);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapView(controller: controller, map: map, tiles: tiles),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final marker = tester.getSize(
        find.byKey(Key('place-marker-${place.id}')),
      );
      expect(marker.height, greaterThanOrEqualTo(44.0));
      final titleButton = tester.getSize(
        find.widgetWithText(TextButton, 'Alpha'),
      );
      expect(titleButton.height, greaterThanOrEqualTo(44.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('coordinate and rename fields offer keyboard actions', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      final tiles = TileCache(
        cacheDirectory: Directory.systemTemp.createTempSync(
          'chainnotes-tiles-keys',
        ),
        client: MockClient((_) async => http.Response('gone', 404)),
      );
      addTearDown(tiles.dispose);
      controller.addPlace(lat: 10, lon: 10, label: 'Alpha');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapView(controller: controller, map: map, tiles: tiles),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.byKey(const Key('lat-input')));
      await tester.pump();
      expect(fieldAction(tester, 'lat-input'), TextInputAction.next);
      expect(fieldAction(tester, 'lon-input'), TextInputAction.done);
      await tester.tap(find.byTooltip('Rename'));
      await tester.pump();
      expect(fieldAction(tester, 'place-rename-input'), TextInputAction.done);
      expect(tester.takeException(), isNull);
    });

    testWidgets('saving the centre stores the viewport as a place', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      final tiles = TileCache(
        cacheDirectory: Directory.systemTemp.createTempSync(
          'chainnotes-tiles-centre',
        ),
        client: MockClient((_) async => http.Response('gone', 404)),
      );
      addTearDown(tiles.dispose);
      map.setCenter(11, 22);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapView(controller: controller, map: map, tiles: tiles),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('save-centre')));
      await tester.pump();
      expect(controller.map.places.single.lat, 11);
      expect(controller.map.places.single.lon, 22);
    });

    test('saving without a pin explains itself', () {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      map.savePin();
      expect(map.status.isError, isTrue);
      expect(map.status.message, contains('Long-press'));
      expect(controller.map.places, isEmpty);
    });

    test('attaching without a target or a pin explains itself', () {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      // Attaching saves through the persistence engine, so wire a temp one:
      // without it every attach reports failure.
      final dir = Directory.systemTemp.createTempSync('chainnotes-attach');
      addTearDown(() => dir.deleteSync(recursive: true));
      final persistence = WorkspacePersistence(
        bridge: WorkspaceStoreBridge(
          cachePath: '${dir.path}/cache.json',
          durablePath: '${dir.path}/durable.json',
        ),
        snapshot: controller.snapshot,
        apply: controller.apply,
        onChanged: () {},
      );
      controller.persistence = persistence;
      addTearDown(persistence.dispose);
      controller.addTocItem(title: 'Field trip', level: 1);
      expect(map.attachPinToSection(), isFalse);
      expect(
        map.status.message,
        'Select an outline item to attach this location to.',
      );
      controller.setLinkTarget(controller.tocItems.single.id);
      expect(map.attachPinToSection(), isFalse);
      expect(map.status.message, contains('Long-press'));
      map.dropPin(1, 2);
      expect(map.attachPinToSection(), isTrue);
      expect(controller.tocItems.single.links.location, isNotNull);
    });

    test('importing the same coordinates twice keeps one place', () {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      final report = map.importPlaces(
        'places.csv',
        'name,lat,lon\nParis,48.85,2.35\nTwice,48.85,2.35\n',
      );
      expect(controller.map.places.length, 1);
      expect(report, contains('already saved'));
      expect(map.status.isError, isFalse);
    });

    test('importing garbage reports instead of throwing', () {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      expect(
        map.importPlaces('places.csv', 'not,a,header,at,all\n1,2\n'),
        isEmpty,
      );
      expect(map.status.isError, isTrue);
      expect(map.status.message, 'No places could be read from that file.');
      expect(controller.map.places, isEmpty);
    });

    testWidgets('clearing places asks first and only clears on confirm', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      final tiles = TileCache(
        cacheDirectory: Directory.systemTemp.createTempSync(
          'chainnotes-tiles-clear',
        ),
        client: MockClient((_) async => http.Response('gone', 404)),
      );
      addTearDown(tiles.dispose);
      controller.addPlace(lat: 10, lon: 10, label: 'Alpha');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapView(controller: controller, map: map, tiles: tiles),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const Key('clear-places')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Clear all places?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.map.places.length, 1);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const Key('clear-places')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Clear'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.map.places, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('clearing layers asks first and only clears on confirm', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      final tiles = TileCache(
        cacheDirectory: Directory.systemTemp.createTempSync(
          'chainnotes-tiles-layers',
        ),
        client: MockClient((_) async => http.Response('gone', 404)),
      );
      addTearDown(tiles.dispose);
      map.addLayerFromText(
        'L',
        '{"type":"Feature","geometry":{"type":"Point","coordinates":[1,2]},"properties":{}}',
      );
      expect(map.layers.length, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapView(controller: controller, map: map, tiles: tiles),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // The layers section starts below the fold: scroll the sidebar until
      // its Clear button is built, then drive the dialog both ways.
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('clear-layers')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('clear-layers')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Clear all layers?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(map.layers.length, 1);
      await tester.tap(find.byKey(const Key('clear-layers')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Clear'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(map.layers, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('PDF Reader picker', () {
    testWidgets('cancelling the open leaves the reader closed', (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final pdf = PdfSession(controller);
      addTearDown(pdf.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfView(
              controller: controller,
              pdf: pdf,
              files: FakeFileService(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Browse files'));
      await tester.pump();
      expect(pdf.isOpen, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('Image lightbox', () {
    test('stepping wraps around the image list', () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final session = ImageSession(controller);
      addTearDown(session.dispose);
      final dir = Directory.systemTemp.createTempSync('chainnotes-images');
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

    test('swipe steps left, right, or not at all', () {
      const left = Offset(-200, 5);
      const right = Offset(200, -5);
      expect(
        lightboxSwipeStep(dx: left.dx, zoomed: false, singlePointer: true),
        1,
      );
      expect(
        lightboxSwipeStep(dx: right.dx, zoomed: false, singlePointer: true),
        -1,
      );
      expect(lightboxSwipeStep(dx: -20, zoomed: false, singlePointer: true), 0);
      expect(lightboxSwipeStep(dx: -200, zoomed: true, singlePointer: true), 0);
      expect(
        lightboxSwipeStep(dx: -200, zoomed: false, singlePointer: false),
        0,
      );
    });

    testWidgets('flinging the lightbox steps to the next image', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final session = ImageSession(controller);
      addTearDown(session.dispose);
      final dir = Directory.systemTemp.createTempSync('chainnotes-swipe');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final name in ['a.png', 'b.png']) {
        File('${dir.path}${Platform.pathSeparator}$name')
            .writeAsBytesSync(kTinyPng);
      }
      expect(await session.openAt(dir.path), isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImagesView(controller: controller, images: session),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final thumbnails = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(InkWell),
      );
      expect(thumbnails, findsNWidgets(2));
      await tester.tap(thumbnails.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(session.lightboxIndex, 0);
      // The viewer must own a real surface: it once collapsed to zero
      // under the dialog's loose constraints, leaving an invisible image.
      expect(tester.getSize(find.byType(InteractiveViewer)).height,
          greaterThan(100));
      // Let the real PNG bytes decode so the image (not the error
      // placeholder) is what receives the fling.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.fling(
        find.byType(InteractiveViewer),
        const Offset(-400, 0),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(session.lightboxIndex, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
