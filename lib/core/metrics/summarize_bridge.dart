import 'metrics_engine.dart';

/// Bridge error vocabulary, mirroring `include/webview_bridge.h`.
enum BridgeError {
  ok('success'),
  nullResponse('Response buffer is null.'),
  bufferTooSmall('Response buffer is too small to hold the result.'),
  nullRequest('Request must be null.'),
  outOfMemory('Could not allocate a metrics engine.'),
  malformedRequest('Request must be a JSON array: [[number, ...]].'),
  emptyInput('The inner array must contain at least one finite number.'),
  invalidValue(
      'Every value must be finite (not NaN or infinity) and within the numeric range.'),
  trailingData('Unexpected trailing data after the array.'),
  engineFailed('The metrics engine rejected one or more values.');

  const BridgeError(this.message);

  final String message;
}

/// Canonical bridge code for an error, as the C parser reports it.
String bridgeErrorCode(BridgeError error) {
  switch (error) {
    case BridgeError.ok:
      return 'OK';
    case BridgeError.nullResponse:
      return 'NULL_RESPONSE';
    case BridgeError.bufferTooSmall:
      return 'BUFFER_TOO_SMALL';
    case BridgeError.nullRequest:
    case BridgeError.malformedRequest:
    case BridgeError.trailingData:
      return 'INVALID_REQUEST';
    case BridgeError.emptyInput:
      return 'EMPTY_INPUT';
    case BridgeError.invalidValue:
      return 'INVALID_VALUE';
    case BridgeError.engineFailed:
      return 'ENGINE_FAILED';
    case BridgeError.outOfMemory:
      return 'OUT_OF_MEMORY';
  }
}

/// The canonical error envelope produced by `json_append_error` in C.
String errorEnvelope(String code, String message) =>
    '{"error":{"code":${jsonString(code)},"message":${jsonString(message)}}}';

String jsonString(String value) {
  final buffer = StringBuffer('"');
  for (final rune in value.runes) {
    switch (rune) {
      case 0x22:
        buffer.write('\\"');
      case 0x5c:
        buffer.write('\\\\');
      case 0x08:
        buffer.write('\\b');
      case 0x0c:
        buffer.write('\\f');
      case 0x0a:
        buffer.write('\\n');
      case 0x0d:
        buffer.write('\\r');
      case 0x09:
        buffer.write('\\t');
      default:
        if (rune < 0x20) {
          buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
        } else {
          buffer.writeCharCode(rune);
        }
    }
  }
  buffer.write('"');
  return buffer.toString();
}

class BridgeResult {
  BridgeResult.success(this.body)
      : code = null,
        message = null;

  BridgeResult.failure(BridgeError error, {String? message})
      : body = null,
        code = bridgeErrorCode(error),
        message = message ?? error.message;

  final String? body;
  final String? code;
  final String? message;

  bool get ok => code == null;

  /// The full error envelope handed back to the caller, or null on success.
  String? get error =>
      code == null ? null : errorEnvelope(code!, message ?? '');
}

class _ParseCursor {
  _ParseCursor(this.text);

  final String text;
  int index = 0;

  bool get atEnd => index >= text.length;

  void skipSpace() {
    while (!atEnd && _isSpace(text.codeUnitAt(index))) {
      index++;
    }
  }

  /// Skips whitespace and reports whether a line break was crossed, which the
  /// C parser treats as an implicit value separator.
  bool skipSpaceNotingNewline() {
    var sawNewline = false;
    while (!atEnd && _isSpace(text.codeUnitAt(index))) {
      final code = text.codeUnitAt(index);
      if (code == 0x0a || code == 0x0d) sawNewline = true;
      index++;
    }
    return sawNewline;
  }

  bool take(String token) {
    skipSpace();
    if (text.startsWith(token, index)) {
      index += token.length;
      return true;
    }
    return false;
  }
}

bool _isSpace(int code) =>
    code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d || code == 0x0c;

bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

const String _commaListMessage = 'Expected a comma-separated list of finite numbers.';
const String _closeInnerMessage = 'Expected closing bracket for inner array.';
const String _closeOuterMessage = 'Expected closing bracket for outer array.';

/// Parses `[[number, ...]]` and produces the summary JSON, replicating
/// `summarize_request` from `src/webview_bridge.c`.
BridgeResult runSummarizeBridge(String? request) {
  if (request == null) {
    return BridgeResult.failure(BridgeError.nullRequest);
  }
  final cursor = _ParseCursor(request);

  if (!cursor.take('[')) {
    return BridgeResult.failure(
      BridgeError.malformedRequest,
      message: 'Request must be a JSON array: [[number, ...]].',
    );
  }
  if (!cursor.take('[')) {
    return BridgeResult.failure(
      BridgeError.malformedRequest,
      message: 'Request must contain an inner array of numbers: [[number, ...]].',
    );
  }

  final engine = MetricsEngine();
  var count = 0;
  var afterComma = false;

  BridgeResult? readValue() {
    final value = _readNumber(cursor);
    if (value == null) {
      return BridgeResult.failure(BridgeError.malformedRequest,
          message: _commaListMessage);
    }
    if (!value.isFinite) {
      return BridgeResult.failure(BridgeError.invalidValue);
    }
    if (engine.add(value) != MetricsError.ok) {
      return BridgeResult.failure(BridgeError.engineFailed);
    }
    count++;
    return null;
  }

  while (true) {
    final sawNewline = cursor.skipSpaceNotingNewline();
    if (cursor.atEnd) {
      return BridgeResult.failure(BridgeError.malformedRequest,
          message: _closeInnerMessage);
    }
    final char = cursor.text[cursor.index];
    if (char == ']') {
      if (afterComma) {
        return BridgeResult.failure(BridgeError.malformedRequest,
            message: _commaListMessage);
      }
      cursor.index++;
      break;
    }
    if (afterComma || count == 0) {
      final failure = readValue();
      if (failure != null) return failure;
      afterComma = false;
      continue;
    }
    if (char == ',') {
      cursor.index++;
      afterComma = true;
      continue;
    }
    if (sawNewline) {
      final failure = readValue();
      if (failure != null) return failure;
      continue;
    }
    return BridgeResult.failure(BridgeError.malformedRequest,
        message: _commaListMessage);
  }

  if (count == 0) {
    return BridgeResult.failure(BridgeError.emptyInput);
  }
  if (!cursor.take(']')) {
    return BridgeResult.failure(BridgeError.malformedRequest,
        message: _closeOuterMessage);
  }
  cursor.skipSpace();
  if (!cursor.atEnd) {
    return BridgeResult.failure(BridgeError.trailingData);
  }

  final summary = engine.summaryOrNull();
  if (summary == null) {
    return BridgeResult.failure(BridgeError.engineFailed);
  }
  return BridgeResult.success(writeSummaryJson(summary));
}

double? _readNumber(_ParseCursor cursor) {
  cursor.skipSpace();
  final start = cursor.index;
  if (!cursor.atEnd &&
      (cursor.text[cursor.index] == '+' || cursor.text[cursor.index] == '-')) {
    cursor.index++;
  }

  // strtod accepts the non-finite literals too; they parse, then fail the
  // finite check in the caller exactly as the C bridge does.
  final rest = cursor.text.substring(cursor.index).toLowerCase();
  if (rest.startsWith('infinity')) {
    cursor.index += 'infinity'.length;
    return cursor.text[start] == '-' ? double.negativeInfinity : double.infinity;
  }
  if (rest.startsWith('inf')) {
    cursor.index += 'inf'.length;
    return cursor.text[start] == '-' ? double.negativeInfinity : double.infinity;
  }
  if (rest.startsWith('nan')) {
    cursor.index += 'nan'.length;
    return double.nan;
  }

  var digits = 0;
  while (!cursor.atEnd && _isDigit(cursor.text.codeUnitAt(cursor.index))) {
    cursor.index++;
    digits++;
  }
  if (!cursor.atEnd && cursor.text[cursor.index] == '.') {
    cursor.index++;
    while (!cursor.atEnd && _isDigit(cursor.text.codeUnitAt(cursor.index))) {
      cursor.index++;
      digits++;
    }
  }
  if (digits == 0) {
    cursor.index = start;
    return null;
  }
  if (!cursor.atEnd &&
      (cursor.text[cursor.index] == 'e' || cursor.text[cursor.index] == 'E')) {
    cursor.index++;
    if (!cursor.atEnd &&
        (cursor.text[cursor.index] == '+' || cursor.text[cursor.index] == '-')) {
      cursor.index++;
    }
    var expDigits = 0;
    while (!cursor.atEnd && _isDigit(cursor.text.codeUnitAt(cursor.index))) {
      cursor.index++;
      expDigits++;
    }
    if (expDigits == 0) {
      cursor.index = start;
      return null;
    }
  }
  final parsed = double.tryParse(cursor.text.substring(start, cursor.index));
  if (parsed == null) {
    cursor.index = start;
    return null;
  }
  return parsed;
}
