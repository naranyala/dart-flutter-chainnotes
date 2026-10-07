import 'dart:math' as math;

import '../geo/geo.dart';

/// One OSM raster tile is 256 CSS pixels square.
const double tileSize = 256;

const double minZoom = 1;

/// The public OSM tile server has no tiles past 19.
const double maxZoom = 19;

/// One ring beyond each edge of the viewport: the cheapest setting that hides
/// a normal pan.
const int tileBuffer = 1;

double clampZoom(num value) {
  final zoom = value.toDouble();
  if (!zoom.isFinite) return minZoom;
  return math.min(maxZoom, math.max(minZoom, zoom));
}

double worldSize(double zoom) => tileSize * math.pow(2, clampZoom(zoom));

class PixelPoint {
  const PixelPoint(this.x, this.y);

  final double x;
  final double y;
}

class LatLon {
  const LatLon(this.lat, this.lon);

  final double lat;
  final double lon;
}

/// Geographic position to global pixel coordinates, the standard slippy-map
/// projection. Deliberately not floored to a tile index so a sub-tile cursor
/// reading stays possible.
PixelPoint projectToPixel(double longitude, double latitude, double zoom) {
  final scale = worldSize(zoom);
  final safeLatitude = clampLatitude(latitude);
  final safeLongitude = wrapLongitude(longitude);
  final sine = math.sin(safeLatitude * math.pi / 180);
  return PixelPoint(
    ((safeLongitude + 180) / 360) * scale,
    (0.5 - math.log((1 + sine) / (1 - sine)) / (4 * math.pi)) * scale,
  );
}

/// The exact inverse of [projectToPixel].
LatLon unprojectFromPixel(double x, double y, double zoom) {
  final scale = worldSize(zoom);
  final normalized = 0.5 - y / scale;
  final latitude =
      90 - (360 * math.atan(math.exp(-2 * math.pi * normalized))) / math.pi;
  return LatLon(
    clampLatitude(latitude),
    wrapLongitude((x / scale) * 360 - 180),
  );
}

double lonToTileX(double longitude, double zoom) =>
    ((wrapLongitude(longitude) + 180) / 360) * math.pow(2, clampZoom(zoom));

double latToTileY(double latitude, double zoom) {
  final safeLatitude = clampLatitude(latitude);
  final sine = math.sin(safeLatitude * math.pi / 180);
  return (0.5 - math.log((1 + sine) / (1 - sine)) / (4 * math.pi)) *
      math.pow(2, clampZoom(zoom));
}

/// Rounds a fractional zoom to the whole level a tile server serves.
double committedZoom(double zoom) => clampZoom(zoom).roundToDouble();

/// The lowest zoom that still covers a viewport with tiles.
double minimumZoomFor(double width, double height, [double size = tileSize]) {
  final largest = math.max(width, height);
  if (!(largest > 0)) return minZoom;
  return math.min(
    maxZoom,
    math.max(minZoom, (math.log(largest / size) / math.ln2).ceilToDouble()),
  );
}

class VisibleTile {
  const VisibleTile({
    required this.key,
    required this.x,
    required this.y,
    required this.z,
    required this.left,
    required this.top,
  });

  final String key;
  final int x;
  final int y;
  final int z;
  final double left;
  final double top;
}

/// Every tile needed to cover a viewport, plus [buffer] rings beyond each edge.
List<VisibleTile> visibleTiles({
  required double centerLat,
  required double centerLon,
  required double zoom,
  required double width,
  required double height,
  double size = tileSize,
  int buffer = tileBuffer,
}) {
  final safeZoom = committedZoom(zoom);
  final span = math.pow(2, safeZoom).round();
  if (!(width > 0) || !(height > 0)) return [];

  final center = projectToPixel(centerLon, centerLat, safeZoom);
  final originX = center.x - width / 2;
  final originY = center.y - height / 2;
  final padX = buffer * size;
  final padY = buffer * size;

  final firstX = ((originX - padX) / size).floor();
  final firstY = ((originY - padY) / size).floor();
  final lastX = ((originX + width + padX) / size).floor();
  final lastY = ((originY + height + padY) / size).floor();

  final tiles = <VisibleTile>[];
  for (var x = firstX; x <= lastX; x++) {
    final wrappedX = ((x % span) + span) % span;
    for (var y = firstY; y <= lastY; y++) {
      if (y < 0 || y >= span) continue;
      tiles.add(
        VisibleTile(
          key: '$safeZoom/$x/$y',
          x: wrappedX,
          y: y,
          z: safeZoom.round(),
          left: x * size,
          top: y * size,
        ),
      );
    }
  }
  return tiles;
}

double easeInOutCubic(double t) =>
    t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;

/// A drawn GeoJSON shape, already reduced to coordinate rings.
class GeoShape {
  GeoShape({required this.rings, required this.kind, this.pointRadius = 6});

  final List<List<LatLon>> rings;
  final GeoShapeKind kind;
  final double pointRadius;
}

enum GeoShapeKind { polygon, line, point }
