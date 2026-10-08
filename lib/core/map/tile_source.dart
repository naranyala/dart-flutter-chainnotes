import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

import 'tile_policy.dart';

/// Fetches and caches raster tiles: memory first, then disk, then the network.
///
/// The desktop host handed tiles to `<img>` elements and let the WebView cache
/// them; here the cache is explicit so a pan does not refetch what was already
/// seen.
///
/// Bounds (TODO-008): at most [maxConcurrentRequests] network fetches in
/// flight, at least [minRequestIntervalMs] between starts, exponential backoff
/// after 429/5xx (serving cache while backing off), and a disk cache capped at
/// [maxDiskFiles] files / [maxDiskBytes] bytes with oldest-first eviction.
/// Switching providers is a one-line change to [tileHosts].
class TileCache {
  TileCache({required this.cacheDirectory, http.Client? client})
      : _client = client ?? http.Client();

  final Directory cacheDirectory;
  final http.Client _client;

  static const String userAgent =
      'chainnotes/1.0 (desktop workspace; flutter tile client)';

  /// The only tile hosts the app may contact. Adding a provider is a
  /// deliberate edit here; nothing else in the tree constructs a tile URL.
  static const List<String> tileHosts = <String>[
    'https://tile.openstreetmap.org',
  ];

  static const int maxConcurrentRequests = 4;
  static const int minRequestIntervalMs = 100;

  /// Disk bounds: ~2k tiles at typical OSM sizes fits comfortably under 64 MiB.
  static const int maxDiskFiles = 2000;
  static const int maxDiskBytes = 64 * 1024 * 1024;

  final TileRequestGate gate = TileRequestGate();

  final Map<String, ui.Image> _images = <String, ui.Image>{};
  final Map<String, Future<ui.Image?>> _inflight = <String, Future<ui.Image?>>{};
  final List<String> _order = <String>[];
  static const int _maxMemoryTiles = 512;

  Future<ui.Image?> tile(int z, int x, int y) {
    final key = '$z/$x/$y';
    final cached = _images[key];
    if (cached != null) return Future.value(cached);
    final pending = _inflight[key];
    if (pending != null) return pending;

    final future = _load(key, z, x, y).then((image) {
      _inflight.remove(key);
      if (image != null) _remember(key, image);
      return image;
    });
    _inflight[key] = future;
    return future;
  }

  bool contains(int z, int x, int y) => _images.containsKey('$z/$x/$y');

  ui.Image? peek(int z, int x, int y) => _images['$z/$x/$y'];

  void _remember(String key, ui.Image image) {
    if (_images.length >= _maxMemoryTiles) {
      final oldest = _order.removeAt(0);
      _images.remove(oldest)?.dispose();
    }
    _images[key] = image;
    _order.add(key);
  }

  Future<ui.Image?> _load(String key, int z, int x, int y) async {
    final bytes = await _readBytes(key, z, x, y);
    if (bytes == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 256,
        targetHeight: 256,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _readBytes(String key, int z, int x, int y) async {
    final file = File(
      '${cacheDirectory.path}${Platform.pathSeparator}tiles'
      '${Platform.pathSeparator}$key.png',
    );
    try {
      if (file.existsSync()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) return bytes;
      }
    } on FileSystemException {
      // Fall through to the network.
    }

    final url = '${tileHosts.first}/$z/$x/$y.png';
    final now = DateTime.now();
    if (!gate.canFetch(now)) return null;
    gate.onStart(now);
    try {
      final response = await _client
          .get(
            Uri.parse(url),
            headers: {'User-Agent': userAgent},
          )
          // Mobile networks stall: never wait forever on one tile.
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        gate.onResult(DateTime.now(), response.statusCode);
        return null;
      }
      gate.onSuccess();
      final bytes = response.bodyBytes;
      try {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
        unawaited(_enforceDiskBounds());
      } on FileSystemException {
        // A read-only cache directory is not fatal.
      }
      return bytes;
    } catch (_) {
      gate.onError();
      return null;
    }
  }

  /// Deletes the oldest tile files until the disk cache fits within
  /// [maxDiskFiles] / [maxDiskBytes]. Best-effort: failures are ignored.
  Future<void> _enforceDiskBounds() async {
    final root = Directory(
      '${cacheDirectory.path}${Platform.pathSeparator}tiles',
    );
    List<FileSystemEntity> entities;
    try {
      if (!root.existsSync()) return;
      entities = root.listSync(recursive: true, followLinks: false);
    } on FileSystemException {
      return;
    }
    final entries = <DiskTileEntry>[];
    for (final entity in entities) {
      if (entity is! File || !entity.path.endsWith('.png')) continue;
      try {
        entries.add(DiskTileEntry(
          path: entity.path,
          bytes: entity.lengthSync(),
          modified: entity.lastModifiedSync(),
        ));
      } on FileSystemException {
        continue;
      }
    }
    final evict = pickTileEvictions(
      entries,
      maxFiles: maxDiskFiles,
      maxBytes: maxDiskBytes,
    );
    for (final victim in evict) {
      try {
        File(victim.path).deleteSync();
      } on FileSystemException {
        continue;
      }
    }
  }

  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _order.clear();
    _inflight.clear();
    _client.close();
  }
}
