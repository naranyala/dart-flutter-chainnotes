/// Pure-Dart policy for the tile network client: concurrency cap, minimum
/// request spacing, and exponential backoff on 429/5xx.
///
/// Extracted from `TileCache` so the rules are unit-testable without HTTP,
/// images, or the filesystem. The cache still serves memory/disk while the
/// gate is closed; a closed gate is a miss, not an error.
class TileRequestGate {
  TileRequestGate({
    this.maxConcurrentRequests = 4,
    this.minIntervalMs = 100,
    this.baseBackoffMs = 1000,
    this.maxBackoffMs = 30000,
  });

  final int maxConcurrentRequests;
  final int minIntervalMs;
  final int baseBackoffMs;
  final int maxBackoffMs;

  int active = 0;
  int consecutiveFailures = 0;
  DateTime? lastStart;
  DateTime? backoffUntil;

  bool canFetch(DateTime now) {
    if (active >= maxConcurrentRequests) return false;
    if (backoffUntil != null && now.isBefore(backoffUntil!)) return false;
    if (lastStart != null &&
        now.difference(lastStart!).inMilliseconds < minIntervalMs) {
      return false;
    }
    return true;
  }

  void onStart(DateTime now) {
    active++;
    lastStart = now;
  }

  void onSuccess() {
    if (active > 0) active--;
    consecutiveFailures = 0;
    backoffUntil = null;
  }

  /// A finished request. Returns true when the status triggers backoff.
  bool onResult(DateTime now, int statusCode) {
    if (active > 0) active--;
    if (statusCode == 429 || statusCode >= 500) {
      consecutiveFailures++;
      final shift = consecutiveFailures - 1;
      var wait = baseBackoffMs * (1 << (shift > 10 ? 10 : shift));
      if (wait > maxBackoffMs) wait = maxBackoffMs;
      backoffUntil = now.add(Duration(milliseconds: wait));
      return true;
    }
    if (statusCode == 200) {
      consecutiveFailures = 0;
      backoffUntil = null;
    }
    return false;
  }

  void onError() {
    if (active > 0) active--;
  }
}

/// One cached tile file, for eviction decisions.
class DiskTileEntry {
  const DiskTileEntry({
    required this.path,
    required this.bytes,
    required this.modified,
  });

  final String path;
  final int bytes;
  final DateTime modified;
}

/// Oldest-first eviction: returns the entries to delete so the remainder fits
/// within [maxFiles] and [maxBytes].
List<DiskTileEntry> pickTileEvictions(
  List<DiskTileEntry> entries, {
  required int maxFiles,
  required int maxBytes,
}) {
  if (entries.length <= maxFiles &&
      entries.fold<int>(0, (sum, e) => sum + e.bytes) <= maxBytes) {
    return const [];
  }
  final sorted = List<DiskTileEntry>.of(entries)
    ..sort((a, b) => a.modified.compareTo(b.modified));
  var files = entries.length;
  var bytes = entries.fold<int>(0, (sum, e) => sum + e.bytes);
  final evict = <DiskTileEntry>[];
  for (final entry in sorted) {
    if (files <= maxFiles && bytes <= maxBytes) break;
    evict.add(entry);
    files--;
    bytes -= entry.bytes;
  }
  return evict;
}
