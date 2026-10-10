import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:chainnotes/app/location.dart';
import 'package:chainnotes/app/services.dart';
import 'package:chainnotes/app/workspace_controller.dart';
import 'package:chainnotes/core/pdf/outline_pdf_writer.dart';
import 'package:chainnotes/core/pdf/pdf_outline.dart';
import 'package:chainnotes/core/workspace/workspace_models.dart';
import 'package:chainnotes/sessions/image_session.dart';
import 'package:chainnotes/sessions/map_session.dart';
import 'package:chainnotes/sessions/pdf_backend.dart';
import 'package:chainnotes/sessions/pdf_session.dart';
import 'package:chainnotes/ui/editor_view.dart';
import 'package:chainnotes/ui/images_view.dart';
import 'package:chainnotes/ui/map_view.dart';
import 'package:chainnotes/ui/pdf_view.dart';
import 'package:chainnotes/ui/toc_view.dart';
import 'package:chainnotes/core/map/tile_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import 'fakes.dart';

class FakeLocations implements LocationQuery {
  FakeLocations({
    this.enabled = true,
    this.check = LocationPermission.whileInUse,
    this.request = LocationPermission.whileInUse,
    this.position,
  });

  bool enabled;
  LocationPermission check;
  LocationPermission request;
  Position? position;

  @override
  Future<bool> serviceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async => check;

  @override
  Future<LocationPermission> requestPermission() async => request;

  @override
  Future<Position> currentPosition() async => position!;
}

Position testPosition(double lat, double lon) => Position(
  latitude: lat,
  longitude: lon,
  timestamp: DateTime(2026, 1, 1),
  accuracy: 10,
  altitude: 0,
  altitudeAccuracy: 1,
  heading: 0,
  headingAccuracy: 1,
  speed: 0,
  speedAccuracy: 0,
);

WorkspaceController freshController() =>
    WorkspaceController(boot: normalizeWorkspace(null));

void main() {
  group('file_selector flows via FakeFileService', () {
    testWidgets('TOC Export writes the envelope through the picker', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Keep', level: 1);
      final dir = Directory.systemTemp.createTempSync('chainnotes-export');
      addTearDown(() => dir.deleteSync(recursive: true));
      final target = '${dir.path}${Platform.pathSeparator}out.json';
      final files = FakeFileService(pickedPath: target);
      final pdf = PdfSession(controller);
      final images = ImageSession(controller);
      final map = MapSession(controller);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TocView(
              controller: controller,
              pdf: pdf,
              images: images,
              map: map,
              files: files,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Export…'));
      await tester.pump();
      final payload = files.written[target]!;
      expect(payload, contains('metrics-toc'));
      expect(payload, contains('Keep'));
      expect(controller.tocStatus.message, 'Outline exported.');
    });

    testWidgets('TOC Import reads the picked file into the outline', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final envelope =
          '{"format":"metrics-toc","version":1,"items":[{"title":"Arrived","level":2,"content":"","links":{},"updatedAt":1}]}';
      final files = FakeFileService(
        pickedFile: '/tmp/in.json',
        files: {'/tmp/in.json': envelope},
      );
      final pdf = PdfSession(controller);
      final images = ImageSession(controller);
      final map = MapSession(controller);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TocView(
              controller: controller,
              pdf: pdf,
              images: images,
              map: map,
              files: files,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Import…'));
      await tester.pump();
      expect(controller.tocItems.single.title, 'Arrived');
    });

    testWidgets('editor import/export move the draft through files', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Draft', level: 1);
      controller.selectTocItem(controller.tocItems.single);
      final files = FakeFileService(
        pickedFile: '/tmp/draft.md',
        pickedPath: '/tmp/draft-out.md',
        files: {'/tmp/draft.md': 'imported words here'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorView(controller: controller, files: files),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Import…'));
      await tester.pump();
      expect(controller.editorContent, 'imported words here');
      await tester.tap(find.text('Export…'));
      await tester.pump();
      expect(files.written['/tmp/draft-out.md'], 'imported words here');
    });

    testWidgets('image directory pick scans real files on disk', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final images = ImageSession(controller);
      addTearDown(images.dispose);
      final dir = Directory.systemTemp.createTempSync('chainnotes-imgdir');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (var i = 0; i < 2; i++) {
        File('${dir.path}${Platform.pathSeparator}pic$i.png')
            .writeAsBytesSync([1, 2, 3]);
      }
      final files = FakeFileService(pickedDirectory: dir.path);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImagesView(
              controller: controller,
              images: images,
              files: files,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose directory').first);
      await tester.pump();
      expect(images.hasImages, isTrue);
      expect(images.groups.single.images, hasLength(2));
    });

    testWidgets('map places import reads the picked CSV', (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller);
      addTearDown(map.dispose);
      final tiles = TileCache(
        cacheDirectory: Directory.systemTemp.createTempSync('chainnotes-tiles'),
        client: MockClient((_) async => http.Response('gone', 404)),
      );
      addTearDown(tiles.dispose);
      final files = FakeFileService(
        pickedFile: '/tmp/places.csv',
        files: {'/tmp/places.csv': 'label,lat,lon\nHome,48.85,2.35\n'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapView(
              controller: controller,
              map: map,
              tiles: tiles,
              files: files,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Import'));
      await tester.pump();
      expect(controller.map.places.single.label, 'Home');
    });
  });

  group('geolocator flows via FakeLocations', () {
    test('a denied permission is a status sentence, never a throw', () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(
        controller,
        locations: FakeLocations(
          check: LocationPermission.denied,
          request: LocationPermission.denied,
        ),
      );
      addTearDown(map.dispose);
      await map.locate();
      expect(map.status.isError, isTrue);
      expect(map.status.message, 'Location permission was denied.');
      expect(map.locateBusy, isFalse);
    });

    test('disabled services are reported before permission is asked', () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(
        controller,
        locations: FakeLocations(enabled: false),
      );
      addTearDown(map.dispose);
      await map.locate();
      expect(
        map.status.message,
        'Location services are turned off on this device.',
      );
    });

    test('a fix flies the viewport to the position', () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(
        controller,
        locations: FakeLocations(position: testPosition(48.85, 2.35)),
      );
      addTearDown(map.dispose);
      await map.locate();
      expect(map.centerLat, closeTo(48.85, 0.001));
      expect(map.centerLon, closeTo(2.35, 0.001));
      expect(map.status.isError, isFalse);
    });
  });

  group('pdf renderer seams', () {
    test(
      'the pdf package renders an outline PDF with a valid header',
      () async {
        final controller = freshController();
        addTearDown(controller.dispose);
        controller.addTocItem(title: 'Chapter', level: 1);
        final dir = Directory.systemTemp.createTempSync('chainnotes-pdf');
        addTearDown(() => dir.deleteSync(recursive: true));
        final result = await renderOutlinePdf(
          directory: dir.path,
          suggestedName: 'outline',
          title: null,
          items: controller.tocItems,
        );
        expect(result.pages, greaterThan(0));
        final bytes = File(result.path).readAsBytesSync();
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      },
    );

    test(
      'a headline PDF built by the pdf package parses without crashing',
      () async {
        final doc = pw.Document();
        doc.addPage(
          pw.Page(build: (context) => pw.Center(child: pw.Text('hello'))),
        );
        final bytes = await doc.save();
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        final parsed = extractPdfOutline(bytes);
        expect(parsed.headings, isEmpty);
      },
    );

    test('pdfrx opens and renders a real PDF on Linux', () async {
      // `flutter test` pretends to be Android; run this one as Linux so the
      // production Linux renderer is what gets exercised.
      final original = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        const opener = PdfrxOpener();
        expect(opener.isSupported, isTrue);
        final doc = pw.Document();
        doc.addPage(
          pw.Page(
            build: (context) => pw.Center(child: pw.Text('renderer proof')),
          ),
        );
        final bytes = await doc.save();
        final dir = Directory.systemTemp.createTempSync('chainnotes-pdfrx');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}${Platform.pathSeparator}real.pdf')
          ..writeAsBytesSync(bytes);

        // The PDFium native asset is bundled by `flutter build`; under
        // `flutter test` it may be missing on some setups. Skip there —
        // on-device runs prove the renderer instead of failing the suite.
        pdfrx.PdfDocument? probe;
        try {
          probe = await pdfrx.PdfDocument.openFile(file.path);
        } catch (e) {
          if ('$e'.contains('PDFium')) {
            markTestSkipped('PDFium native asset unavailable in test env');
            return;
          }
          rethrow;
        } finally {
          await probe?.dispose();
        }

        final controller = freshController();
        addTearDown(controller.dispose);
        final pdf = PdfSession(controller, opener: opener);
        addTearDown(pdf.dispose);
        expect(await pdf.openAt(file.path), isTrue);
        expect(pdf.isOpen, isTrue);
        expect(pdf.pageCount, 1);
        expect(pdf.aspectOf(1), greaterThan(0));

        final rendered = await pdf.renderPage(
          1,
          pixelWidth: 200,
          pixelHeight: 280,
        );
        expect(rendered, isNotNull);
        // PNG signature: 137 'P' 'N' 'G' 13 10 26 10.
        expect(rendered!.take(4).toList(), [137, 80, 78, 71]);
      } finally {
        debugDefaultTargetPlatformOverride = original;
      }
    });

    test(
      'openAt succeeds through the backend seam and remembers the path',
      () async {
        final controller = freshController();
        addTearDown(controller.dispose);
        final pdf = PdfSession(controller, opener: FakePdfOpener(pages: 3));
        addTearDown(pdf.dispose);
        final dir = Directory.systemTemp.createTempSync('chainnotes-pdfok');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}${Platform.pathSeparator}doc.pdf')
          ..writeAsBytesSync([37, 80, 68, 70, 45]);
        expect(await pdf.openAt(file.path), isTrue);
        expect(pdf.isOpen, isTrue);
        expect(pdf.pageCount, 3);
        expect(controller.pdf.recentPaths, contains(file.path));
      },
    );

    test(
      'an unreadable file reports a sentence and forgets the path',
      () async {
        final controller = freshController();
        addTearDown(controller.dispose);
        final pdf = PdfSession(
          controller,
          opener: FakePdfOpener(throwOnOpen: true),
        );
        addTearDown(pdf.dispose);
        controller.rememberPdfPath('/tmp/gone.pdf');
        expect(await pdf.openAt('/tmp/gone.pdf'), isFalse);
        expect(pdf.isOpen, isFalse);
        expect(pdf.status.isError, isTrue);
        expect(pdf.status.message, 'That file could not be opened as a PDF.');
        expect(controller.pdf.recentPaths, isNot(contains('/tmp/gone.pdf')));
      },
    );

    test(
      'an unsupported platform is refused before touching a renderer',
      () async {
        final controller = freshController();
        addTearDown(controller.dispose);
        final pdf = PdfSession(
          controller,
          opener: FakePdfOpener(supported: false),
        );
        addTearDown(pdf.dispose);
        expect(await pdf.openAt('/tmp/any.pdf'), isFalse);
        expect(pdf.status.isError, isTrue);
        expect(pdf.status.message, contains('not available'));
      },
    );

    testWidgets('opening a bad PDF through the UI reports the sentence', (
      tester,
    ) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final pdf = PdfSession(
        controller,
        opener: FakePdfOpener(throwOnOpen: true),
      );
      addTearDown(pdf.dispose);
      final files = FakeFileService(pickedFile: '/tmp/bad.pdf');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfView(controller: controller, pdf: pdf, files: files),
          ),
        ),
      );
      await tester.tap(find.text('Browse files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(pdf.isOpen, isFalse);
      expect(pdf.status.isError, isTrue);
      expect(pdf.status.message, 'That file could not be opened as a PDF.');
    });

    test('renderers report support per platform', () {
      final original = debugDefaultTargetPlatformOverride;
      try {
        for (final platform in [
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
          TargetPlatform.windows,
        ]) {
          debugDefaultTargetPlatformOverride = platform;
          expect(const PdfxOpener().isSupported, isTrue, reason: '$platform');
          expect(const PdfrxOpener().isSupported, isFalse, reason: '$platform');
          expect(platformPdfOpener(), isA<PdfxOpener>());
        }
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        expect(const PdfxOpener().isSupported, isFalse);
        expect(const PdfrxOpener().isSupported, isTrue);
        expect(platformPdfOpener(), isA<PdfrxOpener>());
        debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
        expect(const PdfxOpener().isSupported, isFalse);
        expect(const PdfrxOpener().isSupported, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = original;
      }
    });
  });

  group('geolocator edge flows via FakeLocations', () {
    test('a permanently denied permission is reported, never thrown', () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(
        controller,
        locations: FakeLocations(
          check: LocationPermission.denied,
          request: LocationPermission.deniedForever,
        ),
      );
      addTearDown(map.dispose);
      await map.locate();
      expect(map.status.isError, isTrue);
      expect(map.status.message, 'Location permission was denied.');
      expect(map.locateBusy, isFalse);
    });

    test('a failing position reports instead of throwing', () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(
        controller,
        locations: FakeLocations(position: null),
      );
      addTearDown(map.dispose);
      await map.locate();
      expect(map.status.isError, isTrue);
      expect(map.status.message, 'Your location could not be determined.');
      expect(map.locateBusy, isFalse);
    });
  });

  group('file limits and naming', () {
    test('reads refuse files past the 8 MiB limit', () async {
      final dir = Directory.systemTemp.createTempSync('chainnotes-bigread');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}big.txt')
        ..writeAsBytesSync(List.filled(FileService.maxTextBytes + 1, 65));
      final result = await const FileService().readTextFile(file.path);
      expect(result.ok, isFalse);
      expect(result.error, 'That file is too large to open.');
    });

    test('reads report a missing file instead of throwing', () async {
      final result = await const FileService().readTextFile(
        '/tmp/chainnotes-no-such-file.txt',
      );
      expect(result.ok, isFalse);
      expect(result.error, 'That file could not be read.');
    });

    test('suggestFileName stays safe, short, and suffixed', () {
      expect(suggestFileName('', 'md'), 'outline.md');
      expect(suggestFileName('a/b:c', 'md'), 'a b c.md');
      expect(suggestFileName('notes.md', 'md'), 'notes.md');
      expect(suggestFileName('x' * 100, 'md').length, 83);
      expect(suggestFileName('...', 'md'), 'outline.md');
    });

    test('sanitizePdfName strips paths and stays bounded', () {
      expect(sanitizePdfName('/tmp/x/y.pdf'), 'y.pdf');
      expect(sanitizePdfName('...'), 'outline.pdf');
      expect(sanitizePdfName('  '), 'outline.pdf');
      expect(sanitizePdfName('a' * 200).length, lessThanOrEqualTo(124));
      expect(sanitizePdfName('report'), 'report.pdf');
    });
  });

  group('image scan limits', () {
    test('hidden files are skipped by the scan', () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final images = ImageSession(controller);
      addTearDown(images.dispose);
      final dir = Directory.systemTemp.createTempSync('chainnotes-hidden');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/.hidden.png').writeAsBytesSync(List.filled(16, 1));
      File('${dir.path}/real.png').writeAsBytesSync(List.filled(16, 1));
      expect(await images.openAt(dir.path), isTrue);
      expect(images.images.length, 1);
      expect(images.images.single.name, 'real.png');
    });

    test('an empty folder reports no supported images', () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final images = ImageSession(controller);
      addTearDown(images.dispose);
      final dir = Directory.systemTemp.createTempSync('chainnotes-emptyimg');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(await images.openAt(dir.path), isFalse);
      expect(images.hasImages, isFalse);
      expect(images.status.isError, isTrue);
      expect(
        images.status.message,
        'That folder contains no supported images.',
      );
    });

    test('subfolders become named groups', () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final images = ImageSession(controller);
      addTearDown(images.dispose);
      final dir = Directory.systemTemp.createTempSync('chainnotes-groups');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final entry in ['sub/a.png', 'top.png']) {
        final file = File('${dir.path}/$entry')..createSync(recursive: true);
        file.writeAsBytesSync(List.filled(16, 1));
      }
      expect(await images.openAt(dir.path), isTrue);
      expect(images.groups.map((group) => group.name), contains('sub'));
      images.selectGroup('sub');
      expect(images.visibleImages.length, 1);
    });
  });
}
