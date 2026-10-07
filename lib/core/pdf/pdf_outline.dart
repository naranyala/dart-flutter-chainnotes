import 'dart:typed_data';
import 'dart:io';

class PdfOutlineEntry {
  const PdfOutlineEntry({
    required this.title,
    required this.level,
    required this.page,
  });

  final String title;
  final int level;
  final int? page;
}

class PdfOutlineResult {
  const PdfOutlineResult({required this.headings, this.error});

  final List<PdfOutlineEntry> headings;
  final String? error;

  bool get ok => error == null;
}

/// Best-effort reader for a PDF's `/Outlines` tree.
///
/// The desktop host in the original project walks the outline with a full PDF
/// parser; this port reads the objects it can reach directly: uncompressed
/// objects by scan, compressed ones through `/ObjStm` tables, and page numbers
/// by walking the page tree. Documents whose structure cannot be read report a
/// message instead of pretending the document has no contents.
PdfOutlineResult extractPdfOutline(Uint8List bytes) {
  try {
    final reader = _PdfObjectReader(bytes);
    final catalogNumber = reader.findCatalog();
    if (catalogNumber == null) {
      return const PdfOutlineResult(
        headings: [],
        error: 'This document has no readable structure.',
      );
    }
    final outlinesRef =
        reader.dictValue(reader.object(catalogNumber), '/Outlines');
    final outlineNumber = reader.indirectNumber(outlinesRef);
    if (outlineNumber == null) {
      return const PdfOutlineResult(
        headings: [],
        error: 'This document has no outline to show.',
      );
    }

    final pageNumbers = reader.pageNumbers(catalogNumber);
    final headings = <PdfOutlineEntry>[];
    _walk(reader, outlineNumber, 1, pageNumbers, headings, 0);
    if (headings.isEmpty) {
      return const PdfOutlineResult(
        headings: [],
        error: 'No headings were found in this document.',
      );
    }
    return PdfOutlineResult(headings: headings);
  } on _OutlineFailure catch (failure) {
    return PdfOutlineResult(headings: [], error: failure.message);
  } catch (_) {
    return const PdfOutlineResult(
      headings: [],
      error: 'The contents of this document could not be read.',
    );
  }
}

class _OutlineFailure implements Exception {
  const _OutlineFailure(this.message);

  final String message;
}

const int _maxOutlineEntries = 2000;

void _walk(
  _PdfObjectReader reader,
  int objectNumber,
  int level,
  Map<int, int> pageNumbers,
  List<PdfOutlineEntry> out,
  int depth,
) {
  if (out.length >= _maxOutlineEntries || depth > 32) return;
  final dict = reader.object(objectNumber);
  if (dict == null) return;

  final title = reader.titleValue(dict);
  if (title != null && title.trim().isNotEmpty) {
    out.add(
      PdfOutlineEntry(
        title: title.trim(),
        level: level < 1 ? 1 : (level > 3 ? 3 : level),
        page: reader.destinationPage(dict, pageNumbers),
      ),
    );
  }

  final first = reader.indirectNumber(reader.dictValue(dict, '/First'));
  if (first != null) {
    _walk(reader, first, level + 1, pageNumbers, out, depth + 1);
  }
  final next = reader.indirectNumber(reader.dictValue(dict, '/Next'));
  if (next != null) {
    _walk(reader, next, level, pageNumbers, out, depth + 1);
  }
}

class _PdfObjectReader {
  _PdfObjectReader(Uint8List bytes)
      : bytes = bytes,
        text = String.fromCharCodes(bytes);

  final Uint8List bytes;
  final String text;
  final Map<int, String> _cache = <int, String>{};
  bool _expandedStreams = false;

  /// Uncompressed objects found by scan, keyed by object number.
  Map<int, String>? _scanned;

  Map<int, String> get objects {
    if (_scanned != null) return _scanned!;
    final found = <int, String>{};
    final pattern = RegExp(r'(\d{1,10})\s+(\d{1,3})\s+obj\b');
    for (final match in pattern.allMatches(text)) {
      final number = int.tryParse(match.group(1)!);
      if (number == null) continue;
      final bodyStart = match.end;
      final endObj = text.indexOf('endobj', bodyStart);
      if (endObj < 0) continue;
      final body = text.substring(bodyStart, endObj);
      // Keep the dictionary head: everything past the stream is opaque data.
      final cut = body.indexOf('stream');
      found[number] = cut >= 0 ? body.substring(0, cut) : body;
      if (cut >= 0) {
        _streamOffsets[number] = bodyStart + cut;
      }
    }
    _scanned = found;
    return found;
  }

  final Map<int, int> _streamOffsets = <int, int>{};

  String? object(int number) {
    if (_cache.containsKey(number)) return _cache[number];
    _expandObjectStreams();
    final direct = objects[number];
    if (direct != null) {
      _cache[number] = direct;
      return direct;
    }
    return null;
  }

  /// Pulls the objects packed inside `/ObjStm` streams, which is how PDF 1.5+
  /// stores its page tree and outlines.
  void _expandObjectStreams() {
    if (_expandedStreams) return;
    _expandedStreams = true;
    objects;
    final containers = <int>[];
    for (final entry in _scanned!.entries) {
      if (entry.value.contains('/ObjStm')) containers.add(entry.key);
    }
    for (final number in containers) {
      final dict = _scanned![number];
      if (dict == null) continue;
      final count = int.tryParse(_token(dict, '/N') ?? '') ?? 0;
      final first = int.tryParse(_token(dict, '/First') ?? '') ?? -1;
      if (count <= 0 || first < 0) continue;
      final offset = _streamOffsets[number];
      if (offset == null) continue;
      final streamStart = text.indexOf('stream', offset);
      if (streamStart < 0) continue;
      var dataStart = streamStart + 'stream'.length;
      if (dataStart < text.length && text[dataStart] == '\r') dataStart++;
      if (dataStart < text.length && text[dataStart] == '\n') dataStart++;
      final dataEnd = text.indexOf('endstream', dataStart);
      if (dataEnd < 0) continue;
      final compressed = bytes.sublist(dataStart, dataEnd);
      List<int> raw;
      try {
        raw = ZLibDecoder().convert(compressed);
      } catch (_) {
        continue;
      }
      final decoded = String.fromCharCodes(raw);
      final header = decoded.substring(0, decoded.length.clamp(0, first));
      final numbers = <int>[];
      final offsets = <int>[];
      for (final part in header.trim().split(RegExp(r'\s+'))) {
        final value = int.tryParse(part);
        if (value == null) continue;
        if (numbers.length == offsets.length) {
          numbers.add(value);
        } else {
          offsets.add(value);
        }
      }
      for (var i = 0; i < numbers.length && i < offsets.length; i++) {
        final start = first + offsets[i];
        if (start < 0 || start >= decoded.length) continue;
        final end = i + 1 < offsets.length
            ? first + offsets[i + 1]
            : decoded.length;
        if (end <= start || end > decoded.length) continue;
        final body = decoded.substring(start, end);
        final cut = body.indexOf('stream');
        _scanned![numbers[i]] =
            cut >= 0 ? body.substring(0, cut) : body;
      }
    }
  }

  int? findCatalog() {
    for (final entry in objects.entries) {
      if (RegExp(r'/Type\s*/Catalog\b').hasMatch(entry.value)) {
        return entry.key;
      }
    }
    return null;
  }

  String? dictValue(String? dict, String key) {
    if (dict == null) return null;
    final index = dict.indexOf(key);
    if (index < 0) return null;
    var cursor = index + key.length;
    while (cursor < dict.length && _isSpace(dict.codeUnitAt(cursor))) {
      cursor++;
    }
    if (cursor >= dict.length) return null;
    final code = dict.codeUnitAt(cursor);
    if (code == 0x28) {
      // A literal string: not a value we need for indirect references.
      return null;
    }
    if (code == 0x5b) {
      final end = dict.indexOf(']', cursor);
      return dict.substring(cursor, end < 0 ? dict.length : end + 1);
    }
    if (code == 0x3c && cursor + 1 < dict.length && dict[cursor + 1] == '<') {
      final end = dict.indexOf('>>', cursor);
      return dict.substring(cursor, end < 0 ? dict.length : end + 2);
    }
    var end = cursor;
    while (end < dict.length && !_isSpace(dict.codeUnitAt(end)) &&
        dict.codeUnitAt(end) != 0x2f &&
        dict.codeUnitAt(end) != 0x3e &&
        dict.codeUnitAt(end) != 0x5d) {
      end++;
    }
    return dict.substring(cursor, end);
  }

  int? indirectNumber(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^\s*(\d{1,10})\s+\d{1,3}\s+R').firstMatch(value);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  String? titleValue(String dict) {
    final index = dict.indexOf('/Title');
    if (index < 0) return null;
    var cursor = index + '/Title'.length;
    while (cursor < dict.length && _isSpace(dict.codeUnitAt(cursor))) {
      cursor++;
    }
    if (cursor >= dict.length) return null;
    if (dict.codeUnitAt(cursor) == 0x3c) {
      final end = dict.indexOf('>', cursor);
      if (end < 0) return null;
      final hex = dict.substring(cursor + 1, end);
      final digits = <int>[];
      for (var i = 0; i + 1 < hex.length; i += 2) {
        final value = int.tryParse(hex.substring(i, i + 2), radix: 16);
        if (value == null) break;
        digits.add(value);
      }
      return _decodePdfText(digits);
    }
    if (dict.codeUnitAt(cursor) != 0x28) return null;
    var depth = 0;
    final buffer = StringBuffer();
    for (var i = cursor; i < dict.length; i++) {
      final code = dict.codeUnitAt(i);
      if (code == 0x5c && i + 1 < dict.length) {
        final next = dict[i + 1];
        switch (next) {
          case 'n':
            buffer.write('\n');
          case 'r':
            buffer.write('\r');
          case 't':
            buffer.write('\t');
          case 'b':
            buffer.write('\b');
          case 'f':
            buffer.write('\f');
          case '(':
            buffer.write('(');
          case ')':
            buffer.write(')');
          case '\\':
            buffer.write('\\');
          default:
            buffer.write(next);
        }
        i++;
        continue;
      }
      if (code == 0x28) depth++;
      if (code == 0x29) {
        depth--;
        if (depth == 0) return buffer.toString();
      }
      buffer.writeCharCode(code);
    }
    return buffer.toString();
  }

  Map<int, int> pageNumbers(int catalogNumber) {
    final mapping = <int, int>{};
    final catalog = object(catalogNumber);
    if (catalog == null) return mapping;
    final rootsRef = indirectNumber(dictValue(catalog, '/Pages'));
    if (rootsRef == null) return mapping;
    var counter = 1;
    void visit(int number, int depth) {
      if (depth > 64) return;
      final dict = object(number);
      if (dict == null) return;
      if (RegExp(r'/Type\s*/Page\b').hasMatch(dict)) {
        mapping[number] = counter++;
        return;
      }
      final kids = dictValue(dict, '/Kids');
      if (kids == null) return;
      for (final ref in RegExp(r'(\d{1,10})\s+\d{1,3}\s+R')
          .allMatches(kids)) {
        final kid = int.tryParse(ref.group(1)!);
        if (kid != null) visit(kid, depth + 1);
      }
    }

    visit(rootsRef, 0);
    return mapping;
  }

  int? destinationPage(String dict, Map<int, int> pageNumbers) {
    var dest = dictValue(dict, '/Dest');
    if (dest == null) {
      final action = dictValue(dict, '/A');
      if (action != null) dest = dictValue(action, '/D');
    }
    if (dest == null) return null;
    final ref = indirectNumber(dest);
    if (ref != null) return pageNumbers[ref];
    return null;
  }

  String? _token(String dict, String key) {
    final value = dictValue(dict, key);
    if (value == null) return null;
    final match = RegExp(r'-?\d+').firstMatch(value);
    return match?.group(0);
  }

  static String _decodePdfText(List<int> codeUnits) {
    if (codeUnits.length >= 2 && codeUnits[0] == 0xFE && codeUnits[1] == 0xFF) {
      final units = <int>[];
      for (var i = 2; i + 1 < codeUnits.length; i += 2) {
        units.add((codeUnits[i] << 8) | codeUnits[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    if (codeUnits.length >= 3 &&
        codeUnits[0] == 0xEF &&
        codeUnits[1] == 0xBB &&
        codeUnits[2] == 0xBF) {
      return String.fromCharCodes(codeUnits.sublist(3));
    }
    return String.fromCharCodes(codeUnits);
  }

  static bool _isSpace(int code) =>
      code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d || code == 0x0c;
}
