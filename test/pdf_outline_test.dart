import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chainnotes/core/pdf/pdf_outline.dart';

/// Builds a minimal unscanned-PDF text the object scanner accepts: catalog,
/// pages root, outlines root, and the given item bodies.
Uint8List outlinePdf(List<String> items, {String catalogExtra = ''}) {
  final buffer = StringBuffer()
    ..writeln('%PDF-1.4')
    ..writeln(
      '1 0 obj << /Type /Catalog /Outlines 2 0 R /Pages 100 0 R$catalogExtra >> endobj',
    )
    ..writeln('100 0 obj << /Type /Pages /Kids [] /Count 0 >> endobj')
    ..writeln('2 0 obj << /First 3 0 R >> endobj');
  for (var i = 0; i < items.length; i++) {
    buffer.writeln('${i + 3} 0 obj << ${items[i]} >> endobj');
  }
  buffer.writeln('trailer << /Root 1 0 R >>');
  return Uint8List.fromList(buffer.toString().codeUnits);
}

String chain(int count, {int first = 3}) {
  final bodies = <String>[];
  for (var i = 0; i < count; i++) {
    final next = i + 1 < count ? ' /Next ${first + i + 1} 0 R' : '';
    bodies.add('/Title (Item ${i + 1})$next');
  }
  return bodies.join('\n');
}

void main() {
  group('outline sibling walk', () {
    test('a flat list of 40 siblings all parse', () {
      final result = extractPdfOutline(
        outlinePdf(chain(40).split('\n')),
      );
      expect(result.error, isNull);
      expect(result.headings.map((h) => h.title).toList(), [
        for (var i = 1; i <= 40; i++) 'Item $i',
      ]);
    });

    test('a self-referential outline terminates with one heading', () {
      final result = extractPdfOutline(
        outlinePdf(['/Title (Loop) /First 3 0 R /Next 3 0 R']),
      );
      // A cycle used to fan out exponentially; the visited set ends it.
      expect(result.error, isNull);
      expect(result.headings.map((h) => h.title).toList(), ['Loop']);
    });
  });

  group('page resolution', () {
    test('explicit destinations resolve to page numbers', () {
      final text = StringBuffer()
        ..writeln('%PDF-1.4')
        ..writeln(
          '1 0 obj << /Type /Catalog /Outlines 2 0 R /Pages 100 0 R >> endobj',
        )
        ..writeln(
          '100 0 obj << /Type /Pages /Kids [101 0 R 102 0 R] /Count 2 >> endobj',
        )
        ..writeln('101 0 obj << /Type /Page /Parent 100 0 R >> endobj')
        ..writeln('102 0 obj << /Type /Page /Parent 100 0 R >> endobj')
        ..writeln('2 0 obj << /First 3 0 R >> endobj')
        ..writeln(
          '3 0 obj << /Title (One) /Dest [101 0 R /Fit] /Next 4 0 R >> endobj',
        )
        ..writeln('4 0 obj << /Title (Two) /Dest [102 0 R /Fit] >> endobj')
        ..writeln('trailer << /Root 1 0 R >>');
      final result = extractPdfOutline(
        Uint8List.fromList(text.toString().codeUnits),
      );
      expect(result.error, isNull);
      expect(
        result.headings
            .map((h) => '${h.title}@${h.page}')
            .toList(),
        ['One@1', 'Two@2'],
      );
    });
  });

  group('key matching ignores literal strings', () {
    test('a /Next lookalike inside a literal does not shadow the key', () {
      final result = extractPdfOutline(
        outlinePdf([
          '/Title (A) /Contents (x /Next 9 0 R) /Next 4 0 R',
          '/Title (B)',
        ]),
      );
      expect(result.error, isNull);
      expect(result.headings.map((h) => h.title).toList(), ['A', 'B']);
    });

    test('a /Title lookalike inside a literal does not shadow the key', () {
      final result = extractPdfOutline(
        outlinePdf([
          '/Contents (see /Title B) /Title (A) /Next 4 0 R',
          '/Title (B)',
        ]),
      );
      expect(result.error, isNull);
      expect(result.headings.map((h) => h.title).toList(), ['A', 'B']);
    });

    test('compact dicts without spaces still parse', () {      final text = (StringBuffer()
            ..writeln('%PDF-1.4')
            ..writeln(
              '1 0 obj <</Type/Catalog/Outlines 2 0 R/Pages 100 0 R>> endobj',
            )
            ..writeln('100 0 obj <</Type/Pages/Kids[]/Count 0>> endobj')
            ..writeln('2 0 obj <</First 3 0 R>> endobj')
            ..writeln('3 0 obj <</Title (Solo)>> endobj')
            ..writeln('trailer <</Root 1 0 R>>'))
          .toString();
      final result = extractPdfOutline(Uint8List.fromList(text.codeUnits));
      expect(result.error, isNull);
      expect(result.headings.map((h) => h.title).toList(), ['Solo']);
    });
  });
}
