import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../workspace/workspace_models.dart';

/// Layout constants ported from `src/outline_pdf.c`.
const double pageWidth = 595.28;
const double pageHeight = 841.89;
const double pageMargin = 56;
const double bodySize = 10.5;
const double spaceBeforeHeading = 16;
const double spaceAfterHeading = 6;
const double spaceBetweenItems = 12;
const double paragraphGap = 8;
const double minBodyLine = 14;
const List<double> headingSizes = [18, 15, 13.5];
const int maxOutlineItems = 10000;

class OutlinePdfResult {
  const OutlinePdfResult({
    required this.path,
    required this.name,
    required this.pages,
    required this.bytes,
  });

  final String path;
  final String name;
  final int pages;
  final int bytes;
}

/// The name sanitizer from `sanitize_pdf_name`: strip directories, forbidden
/// bytes, and an all-dots stem, then force a `.pdf` suffix within 120 chars.
String sanitizePdfName(String raw) {
  var name = raw;
  final slash = name.lastIndexOf(RegExp(r'[\\/]'));
  if (slash >= 0) name = name.substring(slash + 1);
  name = name.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '');
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed.replaceAll('.', '').isEmpty) {
    return 'outline.pdf';
  }
  var result = trimmed;
  if (result.length > 120) result = result.substring(0, 120);
  if (!result.toLowerCase().endsWith('.pdf')) result = '$result.pdf';
  return result;
}

/// Renders the outline into a PDF: headings at H1/H2/H3 sizes with the level
/// indent, paragraphs separated by blank-line runs.
Future<OutlinePdfResult> renderOutlinePdf({
  required String directory,
  required String suggestedName,
  required String? title,
  required List<TocItem> items,
}) async {
  final document = pw.Document(title: title ?? 'Outline');
  final children = <pw.Widget>[];

  if (title != null && title.trim().isNotEmpty) {
    children.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: spaceAfterHeading),
        child: pw.Text(
          title.trim(),
          style: pw.TextStyle(
            fontSize: headingSizes.first,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
  }

  final usable = items.take(maxOutlineItems).toList();
  if (usable.isEmpty) {
    children.add(
      pw.Text(
        'This outline has no items yet.',
        style: const pw.TextStyle(fontSize: bodySize),
      ),
    );
  }

  for (final item in usable) {
    final level = clampLevel(item.level);
    children.add(
      pw.Padding(
        padding: pw.EdgeInsets.only(
          top: spaceBeforeHeading,
          bottom: spaceAfterHeading,
          left: (level - 1) * 18,
        ),
        child: pw.Text(
          item.title,
          style: pw.TextStyle(
            fontSize: headingSizes[level - 1],
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
    );
    final paragraphs = item.content.split(RegExp(r'\n\s*\n'));
    var first = true;
    for (final paragraph in paragraphs) {
      final text = paragraph.trim();
      if (text.isEmpty) continue;
      children.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(
            bottom: paragraphGap,
            left: (level - 1) * 18,
          ),
          child: pw.Text(
            text,
            style: const pw.TextStyle(
              fontSize: bodySize,
              lineSpacing: minBodyLine - bodySize,
            ),
          ),
        ),
      );
      first = false;
    }
    if (first) {
      children.add(pw.SizedBox(height: spaceBetweenItems));
    }
  }

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat(pageWidth, pageHeight, marginAll: pageMargin),
      build: (context) => children,
    ),
  );

  final bytes = await document.save();
  final name = sanitizePdfName(suggestedName.isEmpty ? 'outline' : suggestedName);
  final path = '$directory${Platform.pathSeparator}$name';
  await File(path).writeAsBytes(bytes, flush: true);

  return OutlinePdfResult(
    path: path,
    name: name,
    pages: document.document.pdfPageList.pages.length,
    bytes: bytes.length,
  );
}

/// The envelope `renderOutlinePdf` consumed in the host.
Map<String, Object?> outlineEnvelope({
  String? title,
  required List<TocItem> items,
}) =>
    {
      'title': ?title,
      'items': [
        for (final item in items.take(maxOutlineItems))
          {
            'title': item.title,
            'level': item.level,
            'content': item.content,
          },
      ],
    };
