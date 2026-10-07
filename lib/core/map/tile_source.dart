import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;

/// Fetches and caches raster tiles: memory first, then disk, then the network.
///
/// The desktop host handed tiles to `<img>` elements and let the WebView cache
/// them; here the cache is explicit so a pan does not refetch what was already
/// seen.
class TileCache {
  TileCache({required this.cacheDirectory, http.Client? client})
      : _client = client ?? http.Client();

  final Directory cacheDirectory;
  final http.Client _client;

  static const String userAgent =
      'chainnotes/1.0 (desktop workspace; flutter tile client)';

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

    final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
    try {
      final response = await _client.get(
        Uri.parse(url),
        headers: {'User-Agent': userAgent},
      );
      if (response.statusCode != 200) return null;
      final bytes = response.bodyBytes;
      try {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      } on FileSystemException {
        // A read-only cache directory is not fatal.
      }
      return bytes;
    } catch (_) {
      return null;
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
