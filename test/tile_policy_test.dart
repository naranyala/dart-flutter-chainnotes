import 'package:chainnotes/core/map/tile_policy.dart';
import 'package:chainnotes/core/map/tile_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TileRequestGate', () {
    test('allows up to the concurrency cap', () {
      final gate = TileRequestGate(minIntervalMs: 0);
      final now = DateTime(2026, 1, 1);
      for (var i = 0; i < 4; i++) {
        expect(gate.canFetch(now), isTrue);
        gate.onStart(now);
      }
      expect(gate.canFetch(now), isFalse);
    });

    test('enforces a minimum spacing between starts', () {
      final gate = TileRequestGate(minIntervalMs: 100);
      final t0 = DateTime(2026, 1, 1);
      expect(gate.canFetch(t0), isTrue);
      gate.onStart(t0);
      gate.onSuccess();
      expect(gate.canFetch(t0.add(const Duration(milliseconds: 50))), isFalse);
      expect(gate.canFetch(t0.add(const Duration(milliseconds: 100))), isTrue);
    });

    test('backs off on 429 and recovers after the wait', () {
      final gate = TileRequestGate(minIntervalMs: 0);
      final t0 = DateTime(2026, 1, 1);
      gate.onStart(t0);
      expect(gate.onResult(t0, 429), isTrue);
      expect(gate.canFetch(t0), isFalse);
      expect(
        gate.canFetch(t0.add(const Duration(milliseconds: 1000))),
        isTrue,
      );
    });

    test('backoff grows on consecutive 5xx and clears on success', () {
      final gate = TileRequestGate(minIntervalMs: 0);
      final t0 = DateTime(2026, 1, 1);
      gate.onStart(t0);
      gate.onResult(t0, 500);
      final firstWait =
          gate.backoffUntil!.difference(t0).inMilliseconds;
      gate.onStart(t0);
      gate.onResult(t0, 503);
      final secondWait =
          gate.backoffUntil!.difference(t0).inMilliseconds;
      expect(secondWait, greaterThan(firstWait));
      gate.onStart(t0);
      gate.onSuccess();
      expect(gate.canFetch(t0), isTrue);
    });

    test('a burst pan cannot exceed the configured request rate', () {
      final gate = TileRequestGate();
      final t0 = DateTime(2026, 1, 1);
      var allowed = 0;
      for (var i = 0; i < 20; i++) {
        if (gate.canFetch(t0)) {
          allowed++;
          gate.onStart(t0);
        }
      }
      expect(allowed, lessThanOrEqualTo(4));
    });
  });

  group('pickTileEvictions', () {
    DiskTileEntry entry(String name, int bytes, int day) => DiskTileEntry(
          path: name,
          bytes: bytes,
          modified: DateTime(2026, 1, day),
        );

    test('evicts nothing when under both caps', () {
      final entries = [entry('a', 10, 1), entry('b', 10, 2)];
      expect(
        pickTileEvictions(entries, maxFiles: 2000, maxBytes: 64),
        isEmpty,
      );
    });

    test('evicts oldest first until the file cap holds', () {
      final entries = [
        entry('old', 10, 1),
        entry('mid', 10, 2),
        entry('new', 10, 3),
      ];
      final evicted =
          pickTileEvictions(entries, maxFiles: 2, maxBytes: 1 << 30);
      expect(evicted.map((e) => e.path), ['old']);
    });

    test('evicts oldest first until the byte cap holds', () {
      final entries = [
        entry('old', 40, 1),
        entry('new', 40, 2),
      ];
      final evicted =
          pickTileEvictions(entries, maxFiles: 100, maxBytes: 50);
      expect(evicted.map((e) => e.path), ['old']);
    });
  });

  group('TileCache constants', () {
    test('hosts are an explicit constant and the disk cache is bounded', () {
      expect(TileCache.tileHosts, ['https://tile.openstreetmap.org']);
      expect(TileCache.maxDiskFiles, 2000);
      expect(TileCache.maxDiskBytes, 64 * 1024 * 1024);
      expect(TileCache.maxConcurrentRequests, 4);
    });
  });
}
