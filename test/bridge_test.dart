import 'package:chainnotes/core/metrics/summarize_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('summarize bridge', () {
    test('error vocabulary is present', () {
      expect(bridgeErrorCode(BridgeError.malformedRequest), 'INVALID_REQUEST');
      expect(bridgeErrorCode(BridgeError.emptyInput), 'EMPTY_INPUT');
      expect(bridgeErrorCode(BridgeError.invalidValue), 'INVALID_VALUE');
      expect(bridgeErrorCode(BridgeError.engineFailed), 'ENGINE_FAILED');
      expect(bridgeErrorCode(BridgeError.bufferTooSmall), 'BUFFER_TOO_SMALL');
      expect(bridgeErrorCode(BridgeError.outOfMemory), 'OUT_OF_MEMORY');
      for (final error in BridgeError.values) {
        expect(error.message, isNotNull);
      }
    });

    test('whitespace and signed exponents parse', () {
      final result = runSummarizeBridge(' [[2, 4, 6]] ');
      expect(result.ok, isTrue);
      expect(result.body, contains('"count":3'));
      expect(result.body, contains('"mean":4'));
      expect(result.body, contains('"variance":2.6666666666666665'));

      final signed = runSummarizeBridge('[ [ +1.5, -2.5, 3e2 ] ]');
      expect(signed.ok, isTrue);
      expect(signed.body, contains('"count":3'));
      expect(signed.body, contains('"sum":299'));
      expect(signed.body, contains('"min":-2.5'));
      expect(signed.body, contains('"max":300'));

      expect(runSummarizeBridge('[\t[1e-3, 2E+2]\n]').ok, isTrue);
    });

    test('newlines are implicit separators', () {
      final result = runSummarizeBridge('[[1\n2\n3]]');
      expect(result.ok, isTrue);
      expect(result.body, contains('"count":3'));
      expect(result.body, contains('"mean":2'));

      final mixed = runSummarizeBridge('[[1, 2\n3, 4\n5]]');
      expect(mixed.ok, isTrue);
      expect(mixed.body, contains('"count":5'));
    });

    test('single and negative arrays', () {
      final single = runSummarizeBridge('[[42]]');
      expect(single.ok, isTrue);
      expect(single.body, contains('"count":1'));
      expect(single.body, contains('"mean":42'));

      final negative = runSummarizeBridge('[[-1, -2, -3]]');
      expect(negative.ok, isTrue);
      expect(negative.body, contains('"min":-3'));
      expect(negative.body, contains('"max":-1'));
    });

    test('empty inner array reports EMPTY_INPUT', () {
      for (final request in ['[ [ ] ]', '[[]]']) {
        final result = runSummarizeBridge(request);
        expect(result.ok, isFalse);
        expect(result.error, contains('"code":"EMPTY_INPUT"'));
        expect(result.error, contains('at least one'));
      }
    });

    test('success payload carries every field', () {
      final result = runSummarizeBridge('[[1]]');
      expect(result.ok, isTrue);
      expect(result.body, startsWith('{'));
      expect(result.body, endsWith('}'));
      for (final field in ['"count":', '"sum":', '"min":', '"max":', '"mean":', '"variance":']) {
        expect(result.body, contains(field));
      }
    });

    test('malformed requests report INVALID_REQUEST', () {
      final malformed = [
        '',
        '[]',
        '[1, 2]',
        '[[1, nope]]',
        '[[1, 2], [3]]',
        '[[1, 2,]]',
        '[[1 2]]',
        '[[null]]',
        '[[true]]',
      ];
      for (final request in malformed) {
        final result = runSummarizeBridge(request);
        expect(result.ok, isFalse, reason: request);
        expect(result.error, contains('"code":"INVALID_REQUEST"'),
            reason: request);
      }
    });

    test('trailing data is rejected', () {
      final result = runSummarizeBridge('[[1, 2]] trailing');
      expect(result.ok, isFalse);
      expect(result.error, contains('"code":"INVALID_REQUEST"'));
    });

    test('non-finite values report INVALID_VALUE', () {
      for (final request in ['[[nan]]', '[[inf]]', '[[1e309]]', '[[-infinity]]']) {
        final result = runSummarizeBridge(request);
        expect(result.ok, isFalse, reason: request);
        expect(result.error, contains('"code":"INVALID_VALUE"'),
            reason: request);
      }
    });

    test('null request is rejected', () {
      final result = runSummarizeBridge(null);
      expect(result.ok, isFalse);
      expect(result.error, contains('"code":"INVALID_REQUEST"'));
    });

    test('error envelope shape', () {
      final envelope = errorEnvelope('EMPTY_INPUT', 'The inner array must contain at least one finite number.');
      expect(
        envelope,
        '{"error":{"code":"EMPTY_INPUT","message":"The inner array must contain at least one finite number."}}',
      );
    });
  });
}
