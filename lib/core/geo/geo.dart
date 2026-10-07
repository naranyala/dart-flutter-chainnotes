import 'dart:math' as math;

const double maxLatitude = 85.0511287798;

const double _earthRadiusM = 6371008.8;

class Location {
  const Location({required this.lat, required this.lon, this.label = ''});

  final double lat;
  final double lon;
  final String label;

  Map<String, Object?> toJson() => {'lat': lat, 'lon': lon, 'label': label};

  Location copyWith({double? lat, double? lon, String? label}) => Location(
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        label: label ?? this.label,
      );
}

double clampLatitude(num value) {
  final latitude = value.toDouble();
  if (!latitude.isFinite) return 0;
  return math.min(maxLatitude, math.max(-maxLatitude, latitude));
}

double wrapLongitude(num value) {
  final longitude = value.toDouble();
  if (!longitude.isFinite) return 0;
  return (((longitude + 180) % 360) + 360) % 360 - 180;
}

double? _coordinateNumber(Object? value) {
  if (value is num) {
    final v = value.toDouble();
    return v.isFinite ? v : null;
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }
  return null;
}

/// A coordinate pair, or null when the value is not a usable one.
///
/// Out-of-range values are rejected rather than clamped, because a latitude of
/// 400 is a broken record and silently turning it into the north pole would hide
/// the corruption.
Location? normalizeLocation(Object? value) {
  if (value is! Map) return null;
  final lat = _coordinateNumber(value['lat']);
  final lon = _coordinateNumber(value['lon']);
  if (lat == null || lon == null) return null;
  if (lat < -90 || lat > 90) return null;
  if (lon < -180 || lon > 180) return null;
  final rawLabel = value['label'];
  final label = (rawLabel is String ? rawLabel.trim() : '');
  final roundedLat = (lat * 1e6).round() / 1e6;
  final roundedLon = (wrapLongitude(lon) * 1e6).round() / 1e6;
  return Location(
    lat: roundedLat,
    lon: roundedLon,
    label: label.length > 120 ? label.substring(0, 120) : label,
  );
}

String formatCoordinates(Location? location) {
  final point = normalizeLocation(location?.toJson());
  if (point == null) return 'No location';
  return '${point.lat.toStringAsFixed(6)}, ${point.lon.toStringAsFixed(6)}';
}

double? distanceMeters(Location? from, Location? to) {
  final a = normalizeLocation(from?.toJson());
  final b = normalizeLocation(to?.toJson());
  if (a == null || b == null) return null;
  final lat1 = _toRadians(a.lat);
  final lat2 = _toRadians(b.lat);
  final deltaLat = _toRadians(b.lat - a.lat);
  final deltaLon = _toRadians(b.lon - a.lon);
  final h = math.pow(math.sin(deltaLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(deltaLon / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}

double? bearingDegrees(Location? from, Location? to) {
  final a = normalizeLocation(from?.toJson());
  final b = normalizeLocation(to?.toJson());
  if (a == null || b == null) return null;
  final lat1 = _toRadians(a.lat);
  final lat2 = _toRadians(b.lat);
  final deltaLon = _toRadians(b.lon - a.lon);
  final y = math.sin(deltaLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

String formatDistance(double? meters) {
  if (meters == null || !meters.isFinite || meters < 0) return '';
  if (meters < 1) return '${(meters * 100).round()} cm';
  if (meters < 1000) return '${meters.round()} m';
  if (meters < 10000) return '${(meters / 1000).toStringAsFixed(1)} km';
  return '${(meters / 1000).round()} km';
}

String formatDistanceImperial(double? meters) {
  if (meters == null || !meters.isFinite || meters < 0) return '';
  final miles = meters / 1609.344;
  if (miles < 0.1) return '${(meters * 3.28084).round()} ft';
  if (miles < 10) return '${miles.toStringAsFixed(1)} mi';
  return '${miles.round()} mi';
}

const List<String> _compassPoints = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

String compassPoint(double? degrees) {
  if (degrees == null || !degrees.isFinite) return '';
  final index = (((degrees % 360) + 360) % 360 / 45).round() % 8;
  return _compassPoints[index];
}

double _toRadians(double degrees) => degrees * math.pi / 180;
