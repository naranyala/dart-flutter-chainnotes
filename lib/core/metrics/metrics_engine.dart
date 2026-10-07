import 'dart:math';

enum MetricsError {
  ok('success'),
  nullEngine('metrics engine pointer is NULL'),
  nullOutput('output pointer is NULL'),
  nonFinite('value is not finite (NaN or infinity)'),
  overflow('arithmetic overflow during computation'),
  empty('no values have been added to the engine'),
  allocation('memory allocation failed');

  const MetricsError(this.message);

  final String message;
}

class MetricsSummary {
  const MetricsSummary({
    required this.count,
    required this.sum,
    required this.min,
    required this.max,
    required this.mean,
    required this.variance,
  });

  final int count;
  final double sum;
  final double min;
  final double max;
  final double mean;

  /// Population variance (m2 / count).
  final double variance;
}

/// Online batch metrics engine: count, sum, min, max, running mean and the
/// second moment used for population variance (Welford's update).
class MetricsEngine {
  int _count = 0;
  double _sum = 0;
  double _mean = 0;
  double _m2 = 0;
  double _min = 0;
  double _max = 0;

  int get count => _count;

  /// Adds one value. A rejected value never changes the engine state.
  MetricsError add(double value) {
    if (!value.isFinite) return MetricsError.nonFinite;
    if (_count == 0x7fffffffffffffff) return MetricsError.overflow;
    final nextCount = _count + 1;
    final nextSum = _sum + value;
    if (!nextSum.isFinite) return MetricsError.overflow;

    double nextMean;
    double nextM2;
    if (_count == 0) {
      nextMean = value;
      nextM2 = 0;
    } else {
      final delta = value - _mean;
      nextMean = _mean + delta / nextCount;
      nextM2 = _m2 + delta * (value - nextMean);
      if (!nextMean.isFinite || !nextM2.isFinite) {
        return MetricsError.overflow;
      }
      if (nextM2 < 0 && nextM2 > -1e-12) nextM2 = 0;
    }

    final nextMin = _count == 0 ? value : min(_min, value);
    final nextMax = _count == 0 ? value : max(_max, value);

    _count = nextCount;
    _sum = nextSum;
    _mean = nextMean;
    _m2 = nextM2;
    _min = nextMin;
    _max = nextMax;
    return MetricsError.ok;
  }

  /// Returns the summary, or null when no values have been added.
  MetricsSummary? summaryOrNull() {
    if (_count == 0) return null;
    return MetricsSummary(
      count: _count,
      sum: _sum,
      min: _min,
      max: _max,
      mean: _mean,
      variance: _m2 / _count,
    );
  }

  void reset() {
    _count = 0;
    _sum = 0;
    _mean = 0;
    _m2 = 0;
    _min = 0;
    _max = 0;
  }
}

/// One-shot convenience used by the bridge: feed every value, then read the
/// summary. Returns `null` when the input is empty or a value was rejected.
MetricsSummary? summarize(List<double> values) {
  final engine = MetricsEngine();
  for (final value in values) {
    if (engine.add(value) != MetricsError.ok) return null;
  }
  return engine.summaryOrNull();
}

/// Serializes a summary in the same field order as the C bridge writer.
String writeSummaryJson(MetricsSummary summary) {
  return '{"count":${summary.count},'
      '"sum":${formatBridgeDouble(summary.sum)},'
      '"min":${formatBridgeDouble(summary.min)},'
      '"max":${formatBridgeDouble(summary.max)},'
      '"mean":${formatBridgeDouble(summary.mean)},'
      '"variance":${formatBridgeDouble(summary.variance)}}';
}

/// Shortest faithful decimal form for bridge payloads.
String formatBridgeDouble(double value) {
  if (value.isNaN || value.isInfinite) return value.toString();
  if (value == value.roundToDouble() && value.abs() < 1e21) {
    return value.toInt().toString();
  }
  return value.toString();
}
