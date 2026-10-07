import 'package:chainnotes/core/metrics/metrics_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('metrics engine', () {
    test('error messages are never empty', () {
      for (final error in MetricsError.values) {
        expect(error.message, isNotEmpty);
      }
    });

    test('null safety is replaced by empty-state handling', () {
      final engine = MetricsEngine();
      expect(engine.summaryOrNull(), isNull);
      engine.reset();
      expect(engine.summaryOrNull(), isNull);
    });

    test('non-finite values are rejected', () {
      final engine = MetricsEngine();
      expect(engine.add(double.infinity), MetricsError.nonFinite);
      expect(engine.add(double.negativeInfinity), MetricsError.nonFinite);
      expect(engine.add(double.nan), MetricsError.nonFinite);
      expect(engine.summaryOrNull(), isNull);
    });

    test('2, 4, 6 produce count 3, sum 12, mean 4, variance 8/3', () {
      final engine = MetricsEngine();
      for (final value in [2.0, 4.0, 6.0]) {
        expect(engine.add(value), MetricsError.ok);
      }
      final summary = engine.summaryOrNull()!;
      expect(summary.count, 3);
      _close(summary.sum, 12, 1e-12);
      _close(summary.mean, 4, 1e-12);
      _close(summary.min, 2, 1e-12);
      _close(summary.max, 6, 1e-12);
      _close(summary.variance, 8 / 3, 1e-12);
    });

    test('reset clears, a single value has zero variance', () {
      final engine = MetricsEngine();
      engine
        ..add(2)
        ..add(4)
        ..reset();
      expect(engine.summaryOrNull(), isNull);
      expect(engine.add(-5), MetricsError.ok);
      final summary = engine.summaryOrNull()!;
      expect(summary.count, 1);
      _close(summary.sum, -5, 1e-12);
      _close(summary.mean, -5, 1e-12);
      _close(summary.min, -5, 1e-12);
      _close(summary.max, -5, 1e-12);
      _close(summary.variance, 0, 1e-12);
    });

    test('large values keep their precision', () {
      final engine = MetricsEngine();
      engine
        ..add(1e12)
        ..add(1e12 + 1)
        ..add(1e12 + 2);
      final summary = engine.summaryOrNull()!;
      _close(summary.mean, 1e12 + 1, 1e-6);
      _close(summary.variance, 2 / 3, 1e-9);
    });

    test('overflowing the sum leaves the state untouched', () {
      final engine = MetricsEngine();
      expect(engine.add(double.maxFinite), MetricsError.ok);
      expect(engine.add(double.maxFinite), MetricsError.overflow);
      final summary = engine.summaryOrNull()!;
      expect(summary.count, 1);
      _close(summary.sum, double.maxFinite, 0);

      final negative = MetricsEngine();
      expect(negative.add(-double.maxFinite), MetricsError.ok);
      expect(negative.add(-double.maxFinite), MetricsError.overflow);
      expect(negative.summaryOrNull()!.count, 1);
    });

    test('rejected values never disturb the aggregate', () {
      final engine = MetricsEngine();
      engine.add(3);
      engine.add(7);
      engine.add(double.nan);
      engine.add(double.infinity);
      final summary = engine.summaryOrNull()!;
      expect(summary.count, 2);
      _close(summary.sum, 10, 1e-12);
      _close(summary.mean, 5, 1e-12);
    });

    test('reset cycles and bulk adds', () {
      final engine = MetricsEngine();
      for (var cycle = 0; cycle < 5; cycle++) {
        engine.reset();
        engine.add(cycle.toDouble());
        expect(engine.summaryOrNull()!.count, 1);
      }
      engine.reset();
      for (var i = 0; i < 1000; i++) {
        engine.add(i.toDouble());
      }
      expect(engine.summaryOrNull()!.count, 1000);
      engine.reset();
      engine.add(42);
      expect(engine.summaryOrNull()!.mean, 42);
    });

    test('reference values 1..4', () {
      final summary = summarize([1, 2, 3, 4])!;
      expect(summary.count, 4);
      _close(summary.sum, 10, 1e-12);
      _close(summary.mean, 2.5, 1e-12);
      _close(summary.variance, 1.25, 1e-12);
      _close(summary.min, 1, 1e-12);
      _close(summary.max, 4, 1e-12);
    });

    test('summarize rejects empty input', () {
      expect(summarize([]), isNull);
      expect(summarize([double.nan]), isNull);
    });

    test('population variance of the documented example is 6.125', () {
      final summary = summarize([12.5, 15, 8.5, 14])!;
      expect(summary.count, 4);
      _close(summary.sum, 50, 1e-12);
      _close(summary.mean, 12.5, 1e-12);
      _close(summary.variance, 6.125, 1e-12);
    });
  });
}

void _close(double actual, double expected, double tolerance) {
  expect(
    (actual - expected).abs() <= tolerance,
    isTrue,
    reason: 'expected $expected ± $tolerance, got $actual',
  );
}
