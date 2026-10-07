import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:pdfx/pdfx.dart' hide PdfView;

/// A scripted `file_selector` stand-in: pickers return canned paths, reads
/// serve canned content, writes are captured. No platform channel involved.
class FakeFileService extends FileService {
  FakeFileService({
    this.pickedFile,
    this.pickedPath,
    this.pickedDirectory,
    Map<String, String>? files,
  }) : files = files ?? {};

  String? pickedFile;
  String? pickedPath;
  String? pickedDirectory;
  final Map<String, String> files;
  final Map<String, String> written = {};

  @override
  Future<String?> chooseFile({
    List<String> extensions = const [],
    String label = 'File',
  }) async =>
      pickedFile;

  @override
  Future<String?> choosePath({
    required String suggestedName,
    List<String> extensions = const [],
    String label = 'File',
  }) async =>
      pickedPath;

  @override
  Future<String?> chooseDirectory({String? confirmButtonText}) async =>
      pickedDirectory;

  @override
  Future<ReadTextFile> readTextFile(String path) async {
    final content = files[path];
    if (content != null) {
      final slash = path.lastIndexOf(RegExp(r'[\\/]'));
      final name = slash < 0 ? path : path.substring(slash + 1);
      return ReadTextFile(name, path, content);
    }
    return super.readTextFile(path);
  }

  @override
  Future<bool> writeTextFile(String path, String content) async {
    written[path] = content;
    return true;
  }
}

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

Position testPosition(double lat, double lon) => Position(      latitude: lat,
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

/// A scripted `pdfx` stand-in: no platform channel, no native renderer.
class FakePdfOpener implements PdfOpener {
  FakePdfOpener({
    this.supported = true,
    this.pages = 2,
    this.throwOnOpen = false,
  });

  bool supported;
  int pages;
  bool throwOnOpen;

  @override
  bool get isSupported => supported;

  @override
  String get unsupportedMessage => 'PDF rendering is not available here.';

  @override
  Future<PdfDocument> openFile(String path) async {
    if (throwOnOpen) throw const FileSystemException('unreadable');
    return FakePdfDocument(pagesCount: pages);
  }
}

class FakePdfDocument extends PdfDocument {
  FakePdfDocument({required super.pagesCount})
      : super(sourceName: 'fake.pdf', id: 'fake-id');

  @override
  Future<void> close() async {}

  @override
  Future<PdfPage> getPage(int pageNumber, {bool autoCloseAndroid = false}) =>
      throw UnimplementedError('no renderer in tests');

  @override
  bool operator ==(Object other) =>
      other is FakePdfDocument && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

void main() {
  group('file_selector flows via FakeFileService', () {
    testWidgets('TOC Export writes the envelope through the picker',
        (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Keep', level: 1);
      final dir =
          Directory.systemTemp.createTempSync('chainnotes-export');
      addTearDown(() => dir.deleteSync(recursive: true));
      final target = '${dir.path}${Platform.pathSeparator}out.json';
      final files = FakeFileService(pickedPath: target);
      final pdf = PdfSession(controller);
      final images = ImageSession(controller);
      final map = MapSession(controller);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TocView(
              controller: controller,
              pdf: pdf,
              images: images,
              map: map,
              files: files),
        ),
      ));
      await tester.tap(find.text('Export…'));
      await tester.pump();
      final payload = files.written[target]!;
      expect(payload, contains('metrics-toc'));
      expect(payload, contains('Keep'));
      expect(controller.tocStatus.message, 'Outline exported.');
    });

    testWidgets('TOC Import reads the picked file into the outline',
        (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final envelope =
          '{"format":"metrics-toc","version":1,"items":[{"title":"Arrived","level":2,"content":"","links":{},"updatedAt":1}]}';
      final files =
          FakeFileService(pickedFile: '/tmp/in.json', files: {
        '/tmp/in.json': envelope,
      });
      final pdf = PdfSession(controller);
      final images = ImageSession(controller);
      final map = MapSession(controller);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TocView(
              controller: controller,
              pdf: pdf,
              images: images,
              map: map,
              files: files),
        ),
      ));
      await tester.tap(find.text('Import…'));
      await tester.pump();
      expect(controller.tocItems.single.title, 'Arrived');
    });

    testWidgets('editor import/export move the draft through files',
        (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Draft', level: 1);
      controller.selectTocItem(controller.tocItems.single);
      final files = FakeFileService(
        pickedFile: '/tmp/draft.md',
        pickedPath: '/tmp/draft-out.md',
        files: {'/tmp/draft.md': 'imported words here'},
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EditorView(controller: controller, files: files)),
      ));
      await tester.pump();
      await tester.tap(find.text('Import…'));
      await tester.pump();
      expect(controller.editorContent, 'imported words here');
      await tester.tap(find.text('Export…'));
      await tester.pump();
      expect(files.written['/tmp/draft-out.md'], 'imported words here');
    });

    testWidgets('image directory pick scans real files on disk',
        (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final images = ImageSession(controller);
      addTearDown(images.dispose);
      final dir =
          Directory.systemTemp.createTempSync('chainnotes-imgdir');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (var i = 0; i < 2; i++) {
        File('${dir.path}${Platform.pathSeparator}pic$i.png')
            .writeAsBytesSync([1, 2, 3]);
      }
      final files = FakeFileService(pickedDirectory: dir.path);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ImagesView(
                controller: controller, images: images, files: files)),
      ));
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
        cacheDirectory:
            Directory.systemTemp.createTempSync('chainnotes-tiles'),
        client: MockClient((_) async => http.Response('gone', 404)),
      );
      addTearDown(tiles.dispose);
      final files = FakeFileService(pickedFile: '/tmp/places.csv', files: {
        '/tmp/places.csv': 'label,lat,lon\nHome,48.85,2.35\n',
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MapView(
                controller: controller,
                map: map,
                tiles: tiles,
                files: files)),
      ));
      await tester.tap(find.text('Import'));
      await tester.pump();
      expect(controller.map.places.single.label, 'Home');
    });
  });

  group('geolocator flows via FakeLocations', () {
    test('a denied permission is a status sentence, never a throw',
        () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller,
          locations: FakeLocations(
            check: LocationPermission.denied,
            request: LocationPermission.denied,
          ));
      addTearDown(map.dispose);
      await map.locate();
      expect(map.status.isError, isTrue);
      expect(map.status.message, 'Location permission was denied.');
      expect(map.locateBusy, isFalse);
    });

    test('disabled services are reported before permission is asked',
        () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller,
          locations: FakeLocations(enabled: false));
      addTearDown(map.dispose);
      await map.locate();
      expect(map.status.message,
          'Location services are turned off on this device.');
    });

    test('a fix flies the viewport to the position', () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final map = MapSession(controller,
          locations: FakeLocations(position: testPosition(48.85, 2.35)));
      addTearDown(map.dispose);
      await map.locate();
      expect(map.centerLat, closeTo(48.85, 0.001));
      expect(map.centerLon, closeTo(2.35, 0.001));
      expect(map.status.isError, isFalse);
    });
  });

  group('pdf / pdfx seams', () {
    test('the pdf package renders an outline PDF with a valid header',
        () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      controller.addTocItem(title: 'Chapter', level: 1);
      final dir =
          Directory.systemTemp.createTempSync('chainnotes-pdf');
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
    });

    test('a headline PDF built by the pdf package parses without crashing',
        () async {
      final doc = pw.Document();
      doc.addPage(pw.Page(
          build: (context) => pw.Center(child: pw.Text('hello'))));
      final bytes = await doc.save();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final parsed = extractPdfOutline(bytes);
      expect(parsed.headings, isEmpty);
    });

    test('openAt succeeds through the backend seam and remembers the path',
        () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final pdf = PdfSession(controller,
          opener: FakePdfOpener(pages: 3));
      addTearDown(pdf.dispose);
      final dir =
          Directory.systemTemp.createTempSync('chainnotes-pdfok');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file =
          File('${dir.path}${Platform.pathSeparator}doc.pdf')
            ..writeAsBytesSync([37, 80, 68, 70, 45]);
      expect(await pdf.openAt(file.path), isTrue);
      expect(pdf.isOpen, isTrue);
      expect(pdf.pageCount, 3);
      expect(controller.pdf.recentPaths, contains(file.path));
    });

    test('an unreadable file reports a sentence and forgets the path',
        () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final pdf = PdfSession(controller,
          opener: FakePdfOpener(throwOnOpen: true));
      addTearDown(pdf.dispose);
      controller.rememberPdfPath('/tmp/gone.pdf');
      expect(await pdf.openAt('/tmp/gone.pdf'), isFalse);
      expect(pdf.isOpen, isFalse);
      expect(pdf.status.isError, isTrue);
      expect(pdf.status.message, 'That file could not be opened as a PDF.');
      expect(controller.pdf.recentPaths, isNot(contains('/tmp/gone.pdf')));
    });

    test('an unsupported platform is refused before touching pdfx',
        () async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final pdf = PdfSession(controller,
          opener: FakePdfOpener(supported: false));
      addTearDown(pdf.dispose);
      expect(await pdf.openAt('/tmp/any.pdf'), isFalse);
      expect(pdf.status.isError, isTrue);
      expect(pdf.status.message, contains('not available'));
    });

    testWidgets('opening a bad PDF through the UI reports the sentence',
        (tester) async {
      final controller = freshController();
      addTearDown(controller.dispose);
      final pdf = PdfSession(controller,
          opener: FakePdfOpener(throwOnOpen: true));
      addTearDown(pdf.dispose);
      final files = FakeFileService(pickedFile: '/tmp/bad.pdf');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PdfView(
                controller: controller, pdf: pdf, files: files)),
      ));
      await tester.tap(find.text('Browse files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(pdf.isOpen, isFalse);
      expect(pdf.status.isError, isTrue);
      expect(pdf.status.message, 'That file could not be opened as a PDF.');
    });
  });
}
