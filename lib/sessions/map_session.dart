import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../app/location.dart';
import '../app/workspace_controller.dart';
import '../core/geo/geo.dart';
import '../core/map/projection.dart';
import '../core/workspace/workspace_models.dart';

const int maxImportRows = 5000;

class GeoLayer {
  GeoLayer({required this.name, required this.shapes, this.visible = true});

  final String name;
  final List<GeoShape> shapes;
  bool visible;

  int get featureCount => shapes.length;
}

/// The Map Explorer session: viewport, pin, saved places glue, GeoJSON layers,
/// and the locate/attach actions. The persisted half (places, sidebar, filter,
/// renderer, grid, cursor) lives on the shared record.
class MapSession extends ChangeNotifier {
  MapSession(this.controller, {LocationQuery? locations})
      : _locations = locations ?? const GeolocatorQuery();

  final WorkspaceController controller;
  final LocationQuery _locations;

  final ToolStatus status = ToolStatus('Long-press the map to drop a pin.');

  double centerLat = 20;
  double centerLon = 0;
  double zoom = 2;
  Location? pin;
  String? selectedPlaceId;
  bool locateBusy = false;

  final List<GeoLayer> layers = <GeoLayer>[];

  int flyRequest = 0;
  double flyLat = 0;
  double flyLon = 0;
  double flyZoom = 2;

  String get badge => pin != null
      ? 'Pin at ${pin!.lat.toStringAsFixed(4)}, ${pin!.lon.toStringAsFixed(4)}'
      : 'Pick a location on the map';

  String get centerLabel =>
      pin != null ? formatCoordinates(pin) : 'No location';

  void setStatus(String message, {bool error = false}) {
    status.set(message, error: error);
    notifyListeners();
  }

  /* --- viewport ------------------------------------------------------------ */

  void setCenter(double lat, double lon, {bool announce = false}) {
    centerLat = clampLatitude(lat);
    centerLon = wrapLongitude(lon);
    if (announce) {
      setStatus('Centre ${formatCoordinates(Location(lat: centerLat, lon: centerLon))}.');
    }
    notifyListeners();
  }

  void setZoom(double value) {
    final next = clampZoom(value);
    if (next == zoom) return;
    zoom = next;
    notifyListeners();
  }

  void zoomBy(double delta) => setZoom(zoom + delta);

  void panByPixels(double dx, double dy) {
    final safeZoom = committedZoom(zoom);
    final scale = math.pow(2, zoom - safeZoom).toDouble();
    final world = projectToPixel(centerLon, centerLat, safeZoom);
    final next = unprojectFromPixel(
      world.x - dx / scale,
      world.y - dy / scale,
      safeZoom,
    );
    setCenter(next.lat, next.lon);
  }

  /// Flies to a location over 560 ms, zooming in to 13 when further out and
  /// never zooming out below the current level.
  void flyTo(double lat, double lon, {double? zoomTo}) {
    final targetZoom = math.max(
      zoom,
      zoomTo ?? (zoom > 13 ? zoom : 13),
    );
    flyLat = clampLatitude(lat);
    flyLon = wrapLongitude(lon);
    flyZoom = clampZoom(targetZoom);
    flyRequest++;
    setStatus(
      'Flying to ${formatCoordinates(Location(lat: flyLat, lon: flyLon))}.',
    );
    notifyListeners();
  }

  /* --- pin ----------------------------------------------------------------- */

  void dropPin(double lat, double lon) {
    final location = normalizeLocation({'lat': lat, 'lon': lon, 'label': ''});
    if (location == null) {
      setStatus('That point is not a usable coordinate.', error: true);
      return;
    }
    pin = location;
    selectedPlaceId = null;
    setStatus('Pin dropped at ${formatCoordinates(location)}.');
    notifyListeners();
  }

  void clearPin() {
    pin = null;
    setStatus('Pin cleared.');
    notifyListeners();
  }

  /// Saves the current pin as a place; re-saving a coordinate re-tops it.
  void savePin({String? label}) {
    final current = pin;
    if (current == null) {
      setStatus('Long-press the map to drop a pin before saving it.',
          error: true);
      notifyListeners();
      return;
    }
    final text = (label ?? current.label).trim();
    final place = controller.addPlace(
      lat: current.lat,
      lon: current.lon,
      label: text.isEmpty ? formatCoordinates(current) : text,
    );
    if (place == null) {
      if (controller.map.places.length >= maxSavedPlaces) {
        setStatus('The saved places list is full ($maxSavedPlaces places).',
            error: true);
      } else {
        setStatus('That place could not be saved.', error: true);
      }
      notifyListeners();
      return;
    }
    selectedPlaceId = place.id;
    setStatus('Saved “${place.label}”.');
    notifyListeners();
  }

  void selectPlace(Place place) {
    selectedPlaceId = place.id;
    pin = Location(lat: place.lat, lon: place.lon, label: place.label);
    flyTo(place.lat, place.lon);
    notifyListeners();
  }

  /// Steps through the saved places, wrapping around both ends, flying to
  /// each one. This is how you hop between locations without hunting the
  /// list or the canvas.
  void stepPlace(int delta) {
    final places = controller.map.places;
    if (places.isEmpty) {
      setStatus('No saved places yet — save a pin first.', error: true);
      notifyListeners();
      return;
    }
    final current = places.indexWhere((place) => place.id == selectedPlaceId);
    final next = current < 0
        ? (delta >= 0 ? 0 : places.length - 1)
        : (current + delta) % places.length;
    selectPlace(places[next]);
    setStatus(
        'Viewing “${places[next].label}” (${next + 1} of ${places.length}).');
    notifyListeners();
  }

  /// Flies to typed coordinates, dropping the pin there so it can be saved
  /// or attached like any dropped pin. Returns false (with a status
  /// sentence) when the text is not a usable latitude/longitude pair.
  bool goToCoordinates(String latText, String lonText) {
    double? parse(String raw) {
      final cleaned = raw.trim().replaceAll(',', '.');
      if (cleaned.isEmpty) return null;
      final value = double.tryParse(cleaned);
      if (value == null || value.isNaN || value.isInfinite) return null;
      return value;
    }

    final lat = parse(latText);
    final lon = parse(lonText);
    if (lat == null || lon == null) {
      setStatus('Enter coordinates as numbers, like 48.8566, 2.3522.',
          error: true);
      notifyListeners();
      return false;
    }
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      setStatus('Latitude is −90…90 and longitude is −180…180.',
          error: true);
      notifyListeners();
      return false;
    }
    dropPin(lat, lon);
    flyTo(lat, lon);
    return true;
  }

  /// Saves what the canvas is showing right now as a place and selects it.
  void saveCenterAsPlace() {
    final label =
        formatCoordinates(Location(lat: centerLat, lon: centerLon));
    final place =
        controller.addPlace(lat: centerLat, lon: centerLon, label: label);
    if (place == null) {
      if (controller.map.places.length >= maxSavedPlaces) {
        setStatus(
            'The saved places list is full ($maxSavedPlaces places).',
            error: true);
      } else {
        setStatus('The map centre could not be saved.', error: true);
      }
      notifyListeners();
      return;
    }
    selectPlace(place);
    setStatus('Saved “${place.label}”.');
    notifyListeners();
  }

  bool attachPinToSection() {
    final current = pin;
    if (controller.linkTarget == null) {
      setStatus('Select an outline item to attach this location to.',
          error: true);
      notifyListeners();
      return false;
    }
    if (current == null) {
      setStatus('Long-press the map to drop a pin before attaching it.',
          error: true);
      notifyListeners();
      return false;
    }
    final saved = controller.attachLocation(current);
    if (saved) {
      setStatus('Location attached to “${controller.linkTarget!.title}”.');
    }
    notifyListeners();
    return saved;
  }

  bool attachPlaceToSection(Place place) {
    if (controller.linkTarget == null) {
      setStatus('Select an outline item to attach this place to.', error: true);
      notifyListeners();
      return false;
    }
    final saved = controller.attachLocation(
      Location(lat: place.lat, lon: place.lon, label: place.label),
    );
    if (saved) {
      setStatus('“${place.label}” attached to “${controller.linkTarget!.title}”.');
    }
    notifyListeners();
    return saved;
  }

  /* --- locate -------------------------------------------------------------- */

  Future<void> locate() async {
    if (locateBusy) return;
    locateBusy = true;
    setStatus('Locating…');
    notifyListeners();
    try {
      final serviceEnabled = await _locations.serviceEnabled();
      if (!serviceEnabled) {
        setStatus('Location services are turned off on this device.',
            error: true);
        return;
      }
      var permission = await _locations.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _locations.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setStatus('Location permission was denied.', error: true);
        return;
      }
      final position = await _locations.currentPosition();
      setCenter(position.latitude, position.longitude);
      flyTo(position.latitude, position.longitude);
      setStatus(
          'Centre ${formatCoordinates(Location(lat: position.latitude, lon: position.longitude))}.');
    } catch (_) {
      setStatus('Your location could not be determined.', error: true);
    } finally {
      locateBusy = false;
      notifyListeners();
    }
  }

  /* --- GeoJSON layers ------------------------------------------------------ */

  void addLayerFromText(String name, String text) {
    try {
      final decoded = jsonDecode(text);
      final shapes = <GeoShape>[];
      var count = 0;
      void consume(Object? feature) {
        if (count >= maxImportRows) return;
        if (feature is! Map) return;
        final geometry = feature['geometry'];
        if (geometry is! Map) return;
        final parsed = _shapesFromGeometry(geometry);
        if (parsed.isEmpty) return;
        count += parsed.length;
        shapes.addAll(parsed);
      }

      if (decoded is Map && decoded['type'] == 'FeatureCollection') {
        final features = decoded['features'];
        if (features is List) features.forEach(consume);
      } else if (decoded is Map && decoded['type'] == 'Feature') {
        consume(decoded);
      } else if (decoded is Map) {
        consume({'geometry': decoded});
      } else {
        setStatus('That file is not GeoJSON.', error: true);
        notifyListeners();
        return;
      }

      if (shapes.isEmpty) {
        setStatus('That GeoJSON file has no drawable features.', error: true);
        notifyListeners();
        return;
      }
      layers.add(GeoLayer(name: name, shapes: shapes));
      setStatus('Loaded $name · ${shapes.length} features.');
      notifyListeners();
    } catch (_) {
      setStatus('That file could not be read as GeoJSON.', error: true);
      notifyListeners();
    }
  }

  void removeLayer(GeoLayer layer) {
    layers.remove(layer);
    notifyListeners();
  }

  void toggleLayer(GeoLayer layer) {
    layer.visible = !layer.visible;
    notifyListeners();
  }

  void clearLayers() {
    layers.clear();
    notifyListeners();
  }

  /* --- places import (GeoJSON / CSV) --------------------------------------- */

  /// Parses a user file of places and folds them through the same rules a
  /// single save uses. Returns a report sentence.
  String importPlaces(String fileName, String text) {
    final candidates = parsePlacesFile(fileName, text);
    if (candidates.isEmpty) {
      setStatus('No places could be read from that file.', error: true);
      notifyListeners();
      return '';
    }
    var alreadyThere = 0;
    var refused = 0;
    var imported = 0;
    for (final candidate in candidates) {
      final exists = controller.map.places.any(
        (place) => place.lat == candidate.lat && place.lon == candidate.lon,
      );
      final place = controller.addPlace(
        lat: candidate.lat,
        lon: candidate.lon,
        label: candidate.label,
      );
      if (place == null) {
        refused++;
      } else if (exists) {
        alreadyThere++;
      } else {
        imported++;
      }
      if (controller.map.places.length >= maxSavedPlaces) break;
    }
    final buffer = StringBuffer('Imported $imported place${imported == 1 ? '' : 's'}');
    if (alreadyThere > 0) buffer.write(', $alreadyThere already saved');
    if (refused > 0) buffer.write(', $refused refused');
    if (controller.map.places.length >= maxSavedPlaces) {
      buffer.write(' (the list is full)');
    }
    setStatus(buffer.toString());
    notifyListeners();
    return buffer.toString();
  }

  /* --- preferences --------------------------------------------------------- */

  void setFilter(String filter) {
    controller.map.filter = filter;
    controller.touch();
    notifyListeners();
  }

  void setRenderer(String renderer) {
    controller.map.renderer = renderer;
    controller.touch();
    notifyListeners();
  }

  void toggleGrid() {
    controller.map.showGrid = !controller.map.showGrid;
    controller.touch();
    notifyListeners();
  }

  void toggleCursor() {
    controller.map.showCursor = !controller.map.showCursor;
    controller.touch();
    notifyListeners();
  }

  void toggleSidebar() {
    controller.map.sidebarOpen = !controller.map.sidebarOpen;
    controller.touch();
    notifyListeners();
  }
}

List<Place> parsePlacesFile(String fileName, String text) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.csv')) return _parsePlacesCsv(text);
  return _parsePlacesGeoJson(text);
}

List<Place> _parsePlacesGeoJson(String text) {
  final out = <Place>[];
  try {
    final decoded = jsonDecode(text);
    final features = <Object?>[];
    if (decoded is Map && decoded['type'] == 'FeatureCollection') {
      final list = decoded['features'];
      if (list is List) features.addAll(list);
    } else if (decoded is Map) {
      features.add(decoded);
    }
    for (final feature in features) {
      if (out.length >= maxImportRows) break;
      if (feature is! Map) continue;
      final geometry = feature['geometry'];
      if (geometry is! Map) continue;
      final coordinates = geometry['coordinates'];
      double? lat;
      double? lon;
      if (geometry['type'] == 'Point' && coordinates is List && coordinates.length >= 2) {
        lon = (coordinates[0] as num?)?.toDouble();
        lat = (coordinates[1] as num?)?.toDouble();
      }
      if (lat == null || lon == null) continue;
      final properties = feature['properties'];
      final label = properties is Map
          ? (properties['name'] ??
              properties['Name'] ??
              properties['title'] ??
              properties['label'])
          : null;
      final place = normalizePlace({
        'label': label is String ? label : '',
        'lat': lat,
        'lon': lon,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      if (place != null) out.add(place);
    }
  } catch (_) {
    return const [];
  }
  return out;
}

List<Place> _parsePlacesCsv(String text) {
  final out = <Place>[];
  final lines = const LineSplitter().convert(text);
  if (lines.isEmpty) return out;

  int nameColumn = 0;
  int latColumn = 1;
  int lonColumn = 2;
  final header = _splitCsvLine(lines.first);
  final lowered = header.map((cell) => cell.trim().toLowerCase()).toList();
  final latIndex = lowered.indexOf('lat');
  final lonIndex = lowered.indexWhere((cell) => cell == 'lon' || cell == 'lng');
  if (latIndex >= 0 && lonIndex >= 0) {
    latColumn = latIndex;
    lonColumn = lonIndex;
    nameColumn = lowered.indexWhere(
      (cell) => cell == 'name' || cell == 'label' || cell == 'title',
    );
    if (nameColumn < 0) nameColumn = -1;
    for (var i = 1; i < lines.length && out.length < maxImportRows; i++) {
      final cells = _splitCsvLine(lines[i]);
      final lat = double.tryParse(cells.elementAtOrNull(latColumn)?.trim() ?? '');
      final lon = double.tryParse(cells.elementAtOrNull(lonColumn)?.trim() ?? '');
      if (lat == null || lon == null) continue;
      final label = nameColumn >= 0
          ? (cells.elementAtOrNull(nameColumn)?.trim() ?? '')
          : '';
      final place = normalizePlace({
        'label': label,
        'lat': lat,
        'lon': lon,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      if (place != null) out.add(place);
    }
    return out;
  }

  // Headerless file: name, lat, lon.
  final start = _looksNumeric(lines.first) ? 0 : 1;
  for (var i = start; i < lines.length && out.length < maxImportRows; i++) {
    final cells = _splitCsvLine(lines[i]);
    if (cells.length < 3) continue;
    final lat = double.tryParse(cells[1].trim());
    final lon = double.tryParse(cells[2].trim());
    if (lat == null || lon == null) continue;
    final place = normalizePlace({
      'label': cells[0].trim(),
      'lat': lat,
      'lon': lon,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    if (place != null) out.add(place);
  }
  return out;
}

bool _looksNumeric(String line) {
  final cells = _splitCsvLine(line);
  if (cells.length < 3) return false;
  return double.tryParse(cells[1].trim()) != null &&
      double.tryParse(cells[2].trim()) != null;
}

List<String> _splitCsvLine(String line) {
  final cells = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (inQuotes) {
      if (char == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buffer.write(char);
      }
      continue;
    }
    if (char == '"') {
      inQuotes = true;
    } else if (char == ',') {
      cells.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  cells.add(buffer.toString());
  return cells;
}

List<GeoShape> _shapesFromGeometry(Map geometry) {
  final type = geometry['type'];
  final coordinates = geometry['coordinates'];
  if (type == null || coordinates == null) return const [];

  List<LatLon> ring(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final point in raw)
        if (point is List && point.length >= 2)
          LatLon(
            (point[1] as num).toDouble(),
            (point[0] as num).toDouble(),
          ),
    ];
  }

  switch (type) {
    case 'Point':
      final points = ring([coordinates]);
      return points.isEmpty
          ? const []
          : [GeoShape(rings: [points], kind: GeoShapeKind.point)];
    case 'MultiPoint':
      final points = ring(coordinates);
      return points.isEmpty
          ? const []
          : [GeoShape(rings: [points], kind: GeoShapeKind.point)];
    case 'LineString':
      final points = ring(coordinates);
      return points.isEmpty
          ? const []
          : [GeoShape(rings: [points], kind: GeoShapeKind.line)];
    case 'MultiLineString':
      if (coordinates is! List) return const [];
      final rings = [for (final line in coordinates) ring(line)];
      rings.removeWhere((r) => r.isEmpty);
      return rings.isEmpty ? const [] : [GeoShape(rings: rings, kind: GeoShapeKind.line)];
    case 'Polygon':
      final rings = [ring(coordinates)];
      rings.removeWhere((r) => r.isEmpty);
      return rings.isEmpty ? const [] : [GeoShape(rings: rings, kind: GeoShapeKind.polygon)];
    case 'MultiPolygon':
      if (coordinates is! List) return const [];
      final rings = <List<LatLon>>[];
      for (final polygon in coordinates) {
        if (polygon is! List) continue;
        for (final r in polygon) {
          final parsed = ring(r);
          if (parsed.isNotEmpty) rings.add(parsed);
        }
      }
      return rings.isEmpty ? const [] : [GeoShape(rings: rings, kind: GeoShapeKind.polygon)];
    default:
      return const [];
  }
}

extension<T> on List<T> {
  T? elementAtOrNull(int index) =>
      index >= 0 && index < length ? this[index] : null;
}
