import 'dart:convert';

import '../geo/geo.dart';

const int workspaceVersion = 1;
const int maxRecentPaths = 8;
const int maxPathLength = 4096;
const int maxSavedPlaces = 200;
const int maxPlaceLabel = 80;
const int maxImagesPerItem = 64;
const int maxTocTitleLength = 120;
const int maxPdfNameLength = 200;
const double minZoom = 0.6;
const double maxZoom = 2.5;

const List<String> workspaceViews = [
  'menu',
  'editor',
  'toc',
  'pdf',
  'images',
  'map',
  'googlemap',
];

const List<String> mapFilters = [
  'none',
  'grayscale',
  'dark',
  'sepia',
  'vivid',
  'faded',
];

const List<String> googleMapLayers = ['m', 's', 'y', 't'];

int _idSequence = 0;

String nextTocId() {
  _idSequence += 1;
  return 'toc-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
      '-${_idSequence.toRadixString(36)}';
}

String nextPlaceId() {
  _idSequence += 1;
  return 'place-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
      '-${_idSequence.toRadixString(36)}';
}

String asString(Object? value, [int limit = 0]) {
  if (value is! String) return '';
  final trimmed = value.trim();
  if (limit > 0 && trimmed.length > limit) {
    return trimmed.substring(0, limit);
  }
  return trimmed;
}

int? asPage(Object? value) {
  if (value is! num) return null;
  final page = value.toDouble().truncate();
  if (!page.isFinite || page <= 0) return null;
  return page;
}

double asZoom(Object? value) {
  final zoom = value is num ? value.toDouble() : double.nan;
  if (!zoom.isFinite) return 1.1;
  return zoom.clamp(minZoom, maxZoom);
}

int clampLevel(Object? value) {
  num parsed;
  if (value is num) {
    parsed = value;
  } else if (value is String) {
    parsed = double.tryParse(value) ?? double.nan;
  } else {
    parsed = double.nan;
  }
  if (!parsed.isFinite || parsed == 0) return 1;
  final truncated = parsed.truncate();
  if (truncated < 1) return 1;
  if (truncated > 3) return 3;
  return truncated;
}

int countWords(String? text) {
  final trimmed = (text ?? '').trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).length;
}

List<String> normalizeRecentPaths(Object? raw) {
  if (raw is! List) return [];
  final seen = <String>{};
  final paths = <String>[];
  for (final entry in raw) {
    final path = asString(entry, maxPathLength);
    if (path.isEmpty || seen.contains(path)) continue;
    seen.add(path);
    paths.add(path);
    if (paths.length >= maxRecentPaths) break;
  }
  return paths;
}

int asNonNegativeInt(Object? value) {
  num parsed;
  if (value is num) {
    parsed = value;
  } else if (value is String) {
    parsed = double.tryParse(value) ?? 0;
  } else {
    parsed = 0;
  }
  if (!parsed.isFinite || parsed <= 0) return 0;
  return parsed.truncate();
}

class ItemLinks {
  ItemLinks({
    this.pdfPage,
    this.pdfName = '',
    List<String>? images,
    this.location,
  }) : images = images ?? <String>[];

  int? pdfPage;
  String pdfName;
  final List<String> images;
  Location? location;

  ItemLinks copy() => ItemLinks(
        pdfPage: pdfPage,
        pdfName: pdfName,
        images: List<String>.of(images),
        location: location,
      );

  Map<String, Object?> toJson() => {
        'pdfPage': pdfPage,
        'pdfName': pdfName,
        'images': images,
        'location': location?.toJson(),
      };
}

ItemLinks normalizeLinks(Object? raw) {
  final links = raw is Map ? raw : const {};
  final rawImages = links['images'];
  final images = <String>[];
  if (rawImages is List) {
    for (final path in rawImages) {
      if (path is! String || path.trim().isEmpty) continue;
      images.add(path);
      if (images.length >= maxImagesPerItem) break;
    }
  }
  return ItemLinks(
    pdfPage: asPage(links['pdfPage']),
    pdfName: asString(links['pdfName'], maxPdfNameLength),
    images: images,
    location: normalizeLocation(links['location']),
  );
}

class TocItem {
  TocItem({
    required this.id,
    required this.title,
    required this.level,
    this.content = '',
    ItemLinks? links,
    this.updatedAt = 0,
  }) : links = links ?? ItemLinks();

  String id;
  String title;
  int level;
  String content;
  ItemLinks links;
  int updatedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'level': level,
        'content': content,
        'links': links.toJson(),
        'updatedAt': updatedAt,
      };
}

TocItem? normalizeTocItem(Object? raw) {
  if (raw is! Map) return null;
  final title = asString(raw['title'], maxTocTitleLength);
  if (title.isEmpty) return null;
  final id = asString(raw['id'], 64);
  final updatedAt = raw['updatedAt'];
  return TocItem(
    id: id.isEmpty ? nextTocId() : id,
    title: title,
    level: clampLevel(raw['level']),
    content: raw['content'] is String ? raw['content'] as String : '',
    links: normalizeLinks(raw['links']),
    updatedAt: updatedAt is num ? updatedAt.toInt() : 0,
  );
}

List<TocItem> normalizeTocItems(Object? raw) {
  if (raw is! List) return [];
  final items = <TocItem>[];
  for (final entry in raw) {
    final item = normalizeTocItem(entry);
    if (item != null) items.add(item);
  }
  return items;
}

class PdfSessionData {
  PdfSessionData({
    this.name = '',
    this.path = '',
    List<String>? recentPaths,
    this.size = 0,
    this.url = '',
    this.documentId = '',
    this.page = 1,
    double? zoom,
    this.workspaceDirectory = '',
  })  : recentPaths = recentPaths ?? <String>[],
        zoom = zoom ?? 1.1;

  String name;
  String path;
  List<String> recentPaths;
  int size;
  String url;
  String documentId;
  int page;
  double zoom;
  String workspaceDirectory;

  Map<String, Object?> toJson() => {
        'name': name,
        'path': path,
        'recentPaths': recentPaths,
        'size': size,
        'url': url,
        'documentId': documentId,
        'page': page,
        'zoom': zoom,
        'workspaceDirectory': workspaceDirectory,
      };
}

PdfSessionData normalizePdfSession(Object? raw) {
  final pdf = raw is Map ? raw : const {};
  return PdfSessionData(
    name: asString(pdf['name'], maxPdfNameLength),
    path: asString(pdf['path'], maxPathLength),
    recentPaths: normalizeRecentPaths(pdf['recentPaths']),
    size: asNonNegativeInt(pdf['size']),
    url: asString(pdf['url'], 4096),
    documentId: asString(pdf['documentId'], 128),
    page: asPage(pdf['page']) ?? 1,
    zoom: asZoom(pdf['zoom']),
    workspaceDirectory: asString(pdf['workspaceDirectory'], maxPathLength),
  );
}

class ImageSessionData {
  ImageSessionData({
    this.directoryName = '',
    this.directoryPath = '',
    List<String>? recentPaths,
    this.selectedGroup = 'All Images',
  }) : recentPaths = recentPaths ?? <String>[];

  String directoryName;
  String directoryPath;
  List<String> recentPaths;
  String selectedGroup;

  Map<String, Object?> toJson() => {
        'directoryName': directoryName,
        'directoryPath': directoryPath,
        'recentPaths': recentPaths,
        'selectedGroup': selectedGroup,
      };
}

ImageSessionData normalizeImageSession(Object? raw) {
  final images = raw is Map ? raw : const {};
  return ImageSessionData(
    directoryName: asString(images['directoryName'], maxPdfNameLength),
    directoryPath: asString(images['directoryPath'], maxPathLength),
    recentPaths: normalizeRecentPaths(images['recentPaths']),
    selectedGroup:
        asString(images['selectedGroup'], maxPdfNameLength) == ''
            ? 'All Images'
            : asString(images['selectedGroup'], maxPdfNameLength),
  );
}

class Place {
  Place({
    required this.id,
    required this.label,
    required this.lat,
    required this.lon,
    this.createdAt = 0,
  });

  String id;
  String label;
  double lat;
  double lon;
  int createdAt;

  Location get location => Location(lat: lat, lon: lon, label: label);

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'lat': lat,
        'lon': lon,
        'createdAt': createdAt,
      };
}

Place? normalizePlace(Object? raw) {
  if (raw is! Map) return null;
  final coordinates = normalizeLocation(raw);
  final label = asString(raw['label'], maxPlaceLabel);
  if (coordinates == null || label.isEmpty) return null;
  final id = asString(raw['id'], 64);
  final createdAt = raw['createdAt'];
  return Place(
    id: id.isEmpty ? nextPlaceId() : id,
    label: label,
    lat: coordinates.lat,
    lon: coordinates.lon,
    createdAt: createdAt is num ? createdAt.toInt() : 0,
  );
}

List<Place> normalizePlaces(Object? raw) {
  if (raw is! List) return [];
  final seen = <String>{};
  final places = <Place>[];
  for (final entry in raw) {
    final place = normalizePlace(entry);
    if (place == null) continue;
    if (seen.contains(place.id)) continue;
    seen.add(place.id);
    places.add(place);
    if (places.length >= maxSavedPlaces) break;
  }
  return places;
}

class MapSessionData {
  MapSessionData({
    List<Place>? places,
    this.sidebarOpen = true,
    this.filter = 'none',
    this.renderer = 'dom',
    this.showGrid = false,
    this.showCursor = true,
  }) : places = places ?? <Place>[];

  List<Place> places;
  bool sidebarOpen;
  String filter;
  String renderer;
  bool showGrid;
  bool showCursor;

  Map<String, Object?> toJson() => {
        'places': places.map((place) => place.toJson()).toList(),
        'sidebarOpen': sidebarOpen,
        'filter': filter,
        'renderer': renderer,
        'showGrid': showGrid,
        'showCursor': showCursor,
      };
}

MapSessionData normalizeMapSession(Object? raw) {
  final map = raw is Map ? raw : const {};
  final renderer = map['renderer'];
  final showCursor = map['showCursor'];
  final sidebarOpen = map['sidebarOpen'];
  final filter = map['filter'];
  return MapSessionData(
    places: normalizePlaces(map['places']),
    sidebarOpen: sidebarOpen != false,
    filter: mapFilters.contains(filter) ? filter! as String : 'none',
    renderer: renderer == 'canvas' ? 'canvas' : 'dom',
    showGrid: map['showGrid'] == true,
    showCursor: showCursor != false,
  );
}

class GoogleMapSessionData {
  GoogleMapSessionData({
    this.layer = 'm',
    this.renderer = 'dom',
    this.showGrid = false,
    this.showCursor = true,
  });

  String layer;
  String renderer;
  bool showGrid;
  bool showCursor;

  Map<String, Object?> toJson() => {
        'layer': layer,
        'renderer': renderer,
        'showGrid': showGrid,
        'showCursor': showCursor,
      };
}

GoogleMapSessionData normalizeGoogleMapSession(Object? raw) {
  final gm = raw is Map ? raw : const {};
  final layer = gm['layer'];
  final renderer = gm['renderer'];
  final showCursor = gm['showCursor'];
  return GoogleMapSessionData(
    layer: googleMapLayers.contains(layer) ? layer! as String : 'm',
    renderer: renderer == 'canvas' ? 'canvas' : 'dom',
    showGrid: gm['showGrid'] == true,
    showCursor: showCursor != false,
  );
}

/// The one persisted record shared by every tool.
class WorkspaceRecord {
  WorkspaceRecord({
    this.version = workspaceVersion,
    this.savedAt = 0,
    this.view = 'menu',
    List<TocItem>? tocItems,
    this.activeTocId,
    this.editorContent = '',
    PdfSessionData? pdf,
    ImageSessionData? images,
    MapSessionData? map,
    GoogleMapSessionData? googleMap,
  })  : tocItems = tocItems ?? <TocItem>[],
        pdf = pdf ?? PdfSessionData(),
        images = images ?? ImageSessionData(),
        map = map ?? MapSessionData(),
        googleMap = googleMap ?? GoogleMapSessionData();

  int version;
  int savedAt;
  String view;
  List<TocItem> tocItems;
  String? activeTocId;
  String editorContent;
  PdfSessionData pdf;
  ImageSessionData images;
  MapSessionData map;
  GoogleMapSessionData googleMap;

  WorkspaceRecord copyWith({
    int? savedAt,
    String? view,
    List<TocItem>? tocItems,
    String? activeTocId,
    bool clearActiveTocId = false,
    String? editorContent,
    PdfSessionData? pdf,
    ImageSessionData? images,
    MapSessionData? map,
    GoogleMapSessionData? googleMap,
  }) =>
      WorkspaceRecord(
        version: version,
        savedAt: savedAt ?? this.savedAt,
        view: view ?? this.view,
        tocItems: tocItems ?? this.tocItems,
        activeTocId: clearActiveTocId ? null : (activeTocId ?? this.activeTocId),
        editorContent: editorContent ?? this.editorContent,
        pdf: pdf ?? this.pdf,
        images: images ?? this.images,
        map: map ?? this.map,
        googleMap: googleMap ?? this.googleMap,
      );

  Map<String, Object?> toJson() => {
        'version': version,
        'savedAt': savedAt,
        'view': view,
        'tocItems': tocItems.map((item) => item.toJson()).toList(),
        'activeTocId': activeTocId,
        'editor': {'content': editorContent},
        'pdf': pdf.toJson(),
        'images': images.toJson(),
        'map': map.toJson(),
        'googleMap': googleMap.toJson(),
      };
}

/// Reads always pass through this, so a corrupt or legacy value degrades to a
/// safe default instead of throwing.
WorkspaceRecord normalizeWorkspace(Object? raw) {
  final source = raw is Map ? raw : const {};
  final editor = source['editor'] is Map
      ? source['editor'] as Map
      : const <String, Object?>{};
  final activeTocId = asString(source['activeTocId'], 64);
  final view = source['view'];
  return WorkspaceRecord(
    version: workspaceVersion,
    savedAt: asNonNegativeInt(source['savedAt']),
    view: workspaceViews.contains(view) ? view! as String : 'menu',
    tocItems: normalizeTocItems(source['tocItems']),
    activeTocId: activeTocId.isEmpty ? null : activeTocId,
    editorContent: editor['content'] is String
        ? editor['content'] as String
        : '',
    pdf: normalizePdfSession(source['pdf']),
    images: normalizeImageSession(source['images']),
    map: normalizeMapSession(source['map']),
    googleMap: normalizeGoogleMapSession(source['googleMap']),
  );
}

/// `JSON.stringify(normalizeWorkspace(state))`, the exact payload handed to
/// the durable store.
String serializeWorkspace(Object? state) {
  final source = state is WorkspaceRecord ? state.toJson() : state;
  return jsonEncode(normalizeWorkspace(source).toJson());
}
