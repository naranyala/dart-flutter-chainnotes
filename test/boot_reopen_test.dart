import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chainnotes/app/workspace_controller.dart';
import 'package:chainnotes/core/workspace/workspace_models.dart';
import 'package:chainnotes/main.dart' show reopenRemembered;
import 'package:chainnotes/sessions/image_session.dart';
import 'package:chainnotes/sessions/pdf_session.dart';

import 'fakes.dart';

/// A restart restores the open document and folder, not just the record.
void main() {
  group('reopenRemembered', () {
    test('reopens the remembered PDF with its recorded page', () async {
      final controller =
          WorkspaceController(boot: normalizeWorkspace(null));
      addTearDown(controller.dispose);
      final dir = Directory.systemTemp.createTempSync('reopen-pdf');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/doc.pdf')
        ..writeAsBytesSync([37, 80, 68, 70, 45]);
      controller.pdf
        ..path = file.path
        ..page = 2;
      controller.rememberPdfPath(file.path);
      final pdf =
          PdfSession(controller, opener: FakePdfOpener(pages: 3));
      addTearDown(pdf.dispose);
      final images = ImageSession(controller);
      addTearDown(images.dispose);

      await reopenRemembered(
          pdf: pdf, images: images, controller: controller);

      expect(pdf.isOpen, isTrue);
      expect(controller.pdf.page, 2);
    });

    test('a gone PDF is forgotten with a sentence', () async {
      final controller =
          WorkspaceController(boot: normalizeWorkspace(null));
      addTearDown(controller.dispose);
      const gone = '/tmp/chainnotes-gone-doc.pdf';
      controller.pdf.path = gone;
      controller.rememberPdfPath(gone);
      final pdf =
          PdfSession(controller, opener: FakePdfOpener(pages: 3));
      addTearDown(pdf.dispose);
      final images = ImageSession(controller);
      addTearDown(images.dispose);

      await reopenRemembered(
          pdf: pdf, images: images, controller: controller);

      expect(pdf.isOpen, isFalse);
      expect(controller.pdf.recentPaths, isNot(contains(gone)));
      expect(pdf.status.isError, isTrue);
      expect(pdf.status.message, contains('gone'));
    });

    test('reopens the remembered folder with its recorded group', () async {
      final controller =
          WorkspaceController(boot: normalizeWorkspace(null));
      addTearDown(controller.dispose);
      final dir = Directory.systemTemp.createTempSync('reopen-images');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final entry in ['a/x.png', 'b/y.png']) {
        final file = File('${dir.path}/$entry')
          ..createSync(recursive: true);
        file.writeAsBytesSync(List.filled(16, 1));
      }
      controller.images
        ..directoryPath = dir.path
        ..selectedGroup = 'b';
      controller.rememberImageDirectory(dir.path);
      final pdf =
          PdfSession(controller, opener: FakePdfOpener(pages: 3));
      addTearDown(pdf.dispose);
      final images = ImageSession(controller);
      addTearDown(images.dispose);

      await reopenRemembered(
          pdf: pdf, images: images, controller: controller);

      expect(images.hasImages, isTrue);
      expect(controller.images.selectedGroup, 'b');
      expect(images.visibleImages.length, 1);
    });

    test('a gone folder reports without crashing', () async {
      final controller =
          WorkspaceController(boot: normalizeWorkspace(null));
      addTearDown(controller.dispose);
      const gone = '/tmp/chainnotes-gone-folder';
      controller.images.directoryPath = gone;
      controller.rememberImageDirectory(gone);
      final pdf =
          PdfSession(controller, opener: FakePdfOpener(pages: 3));
      addTearDown(pdf.dispose);
      final images = ImageSession(controller);
      addTearDown(images.dispose);

      await reopenRemembered(
          pdf: pdf, images: images, controller: controller);

      expect(images.hasImages, isFalse);
      expect(images.status.isError, isTrue);
      expect(images.status.message, contains('gone'));
    });

    test('nothing remembered means nothing happens', () async {
      final controller =
          WorkspaceController(boot: normalizeWorkspace(null));
      addTearDown(controller.dispose);
      final pdf =
          PdfSession(controller, opener: FakePdfOpener(pages: 3));
      addTearDown(pdf.dispose);
      final images = ImageSession(controller);
      addTearDown(images.dispose);

      await reopenRemembered(
          pdf: pdf, images: images, controller: controller);

      expect(pdf.isOpen, isFalse);
      expect(images.hasImages, isFalse);
      expect(pdf.status.isError, isFalse);
      expect(images.status.isError, isFalse);
    });
  });
}
