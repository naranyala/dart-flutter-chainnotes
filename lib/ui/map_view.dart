import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../app/workspace_controller.dart';
import '../core/geo/geo.dart';
import '../core/map/projection.dart';
import '../core/map/tile_source.dart';
import '../core/workspace/workspace_models.dart';
import '../sessions/map_session.dart';
import 'widgets.dart' as w;

const Map<String, ColorFilter> _filters = {
  'none': ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0,
  ]),
  'grayscale': ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0,
  ]),
  'dark': ColorFilter.matrix(<double>[
    0.7, 0, 0, 0, 0, //
    0, 0.7, 0, 0, 0, //
    0, 0, 0.8, 0, 0, //
    0, 0, 0, 1, 0,
  ]),
  'sepia': ColorFilter.matrix(<double>[
    0.393, 0.769, 0.189, 0, 0, //
    0.349, 0.686, 0.168, 0, 0, //
    0.272, 0.534, 0.131, 0, 0, //
    0, 0, 0, 1, 0,
  ]),
  'vivid': ColorFilter.matrix(<double>[
    1.2, 0, 0, 0, 0, //
    0, 1.2, 0, 0, 0, //
    0, 0, 1.2, 0, 0, //
    0, 0, 0, 1, 0,
  ]),
  'faded': ColorFilter.matrix(<double>[
    0.85, 0, 0, 0, 0.08, //
    0, 0.85, 0, 0, 0.08, //
    0, 0, 0.85, 0, 0.08, //
    0, 0, 0, 1, 0,
  ]),
};

/// The Map Explorer: a tiled Web-Mercator canvas with a pin, saved places,
/// colour filters, GeoJSON layers, and the outline link panel.
class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.controller,
    required this.map,
    required this.tiles,
    this.files = const FileService(),
  });

  final WorkspaceController controller;
  final MapSession map;
  final TileCache tiles;
  final FileService files;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Stopwatch _clock = Stopwatch();
  final TextEditingController _renameController = TextEditingController();
  String? _renamingPlaceId;

  Size _size = Size.zero;
  Offset? _cursor;
  String? _cursorLabel;
  final Set<String> _requested = <String>{};

  MapSession get session => widget.map;
  WorkspaceController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    session.addListener(_onSessionChanged);
    controller.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _ticker.dispose();
    session.removeListener(_onSessionChanged);
    controller.removeListener(_onSessionChanged);
    _renameController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final request = session.flyRequest;
    if (request != _lastFly) {
      _lastFly = request;
      _startFlight();
    }
    setState(() {});
  }

  int _lastFly = 0;

  void _startFlight() {
    _flightFromLat = session.centerLat;
    _flightFromLon = session.centerLon;
    _flightFromZoom = session.zoom;
    _clock
      ..reset()
      ..start();
    _flightActive = true;
  }

  bool _flightActive = false;
  double _flightFromLat = 0;
  double _flightFromLon = 0;
  double _flightFromZoom = 2;

  static const int flightMicros = 560000;

  void _onTick(Duration _) {
    if (!_flightActive) return;
    final t = (_clock.elapsedMicroseconds / flightMicros).clamp(0.0, 1.0);
    final eased = easeInOutCubic(t);
    setState(() {
      session.centerLat = clampLatitude(
        _flightFromLat + (session.flyLat - _flightFromLat) * eased,
      );
      session.centerLon = wrapLongitude(
        _flightFromLon + (session.flyLon - _flightFromLon) * eased,
      );
      session.zoom =
          _flightFromZoom + (session.flyZoom - _flightFromZoom) * eased;
      if (t >= 1) _flightActive = false;
    });
  }

  /* --- geometry ------------------------------------------------------------ */

  double get _safeZoom => committedZoom(session.zoom);

  double get _scale => math.pow(2, session.zoom - _safeZoom).toDouble();

  Offset _project(double lat, double lon) {
    final world = projectToPixel(lon, lat, _safeZoom);
    final center =
        projectToPixel(session.centerLon, session.centerLat, _safeZoom);
    return Offset(
      (world.x - center.x) * _scale + _size.width / 2,
      (world.y - center.y) * _scale + _size.height / 2,
    );
  }

  LatLon _unproject(Offset screen) {
    final center =
        projectToPixel(session.centerLon, session.centerLat, _safeZoom);
    final world = Offset(
      (screen.dx - _size.width / 2) / _scale + center.x,
      (screen.dy - _size.height / 2) / _scale + center.y,
    );
    return unprojectFromPixel(world.dx, world.dy, _safeZoom);
  }

  Rect _tileScreenRect(VisibleTile tile) {
    final center =
        projectToPixel(session.centerLon, session.centerLat, _safeZoom);
    final left =
        (tile.left - center.x) * _scale + _size.width / 2;
    final top = (tile.top - center.y) * _scale + _size.height / 2;
    final size = tileSize * _scale;
    return Rect.fromLTWH(left, top, size, size);
  }

  /* --- tiles --------------------------------------------------------------- */

  void _requestTiles() {
    if (_size == Size.zero) return;
    final tiles = visibleTiles(
      centerLat: session.centerLat,
      centerLon: session.centerLon,
      zoom: session.zoom,
      width: _size.width,
      height: _size.height,
    );
    final pending = <Future<ui.Image?>>[];
    for (final tile in tiles) {
      if (widget.tiles.contains(tile.z, tile.x, tile.y)) continue;
      if (!_requested.add(tile.key)) continue;
      pending.add(widget.tiles.tile(tile.z, tile.x, tile.y));
    }
    if (pending.isEmpty) return;
    Future.wait(pending).then((_) {
      _requested.clear();
      if (mounted) setState(() {});
    });
  }

  /* --- gestures ------------------------------------------------------------ */

  double _startZoom = 0;

  void _onScaleStart(ScaleStartDetails details) {
    _flightActive = false;
    _startZoom = session.zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount <= 1) {
      session.panByPixels(
        details.focalPointDelta.dx,
        details.focalPointDelta.dy,
      );
      return;
    }
    if (_startZoom > 0) {
      final zoom = _startZoom + math.log(details.scale.clamp(0.05, 20.0)) / math.ln2;
      session.setZoom(zoom);
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _flightActive = false;
      session.zoomBy(event.scrollDelta.dy > 0 ? -0.25 : 0.25);
    }
  }

  void _dropPinAt(Offset screen) {
    final point = _unproject(screen);
    session.dropPin(point.lat, point.lon);
  }

  /* --- sidebar actions ----------------------------------------------------- */

  Future<void> _importPlaces() async {
    final path = await widget.files.chooseFile(
      extensions: const ['geojson', 'json', 'csv'],
      label: 'Places file',
    );
    if (path == null || !mounted) return;
    final file = await widget.files.readTextFile(path);
    if (!mounted) return;
    if (!file.ok) {
      session.setStatus(file.error!, error: true);
      return;
    }
    session.importPlaces(file.name, file.content);
    setState(() {});
  }

  Future<void> _loadGeoJson() async {
    final path = await widget.files.chooseFile(
      extensions: const ['geojson', 'json'],
      label: 'GeoJSON',
    );
    if (path == null || !mounted) return;
    final file = await widget.files.readTextFile(path);
    if (!mounted) return;
    if (!file.ok) {
      session.setStatus(file.error!, error: true);
      return;
    }
    session.addLayerFromText(file.name, file.content);
    setState(() {});
  }

  /* --- build --------------------------------------------------------------- */

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, session]),
      builder: (context, _) {
        return Column(
          children: [
            _toolbar(),
            _optionsBar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (controller.map.sidebarOpen) _sidebar(),
                  Expanded(child: _canvas()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _toolbar() {
    final status = session.status;
    return Container(
      constraints: const BoxConstraints(minHeight: topBarHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: WorkspaceColors.surface,
        border: Border(bottom: BorderSide(color: WorkspaceColors.borderSubtle)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          const w.Eyebrow('MAP EXPLORER'),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              session.centerLabel,
              key: const Key('map-center-label'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5, color: WorkspaceColors.textMuted),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 120, maxWidth: 380),
            child: w.StatusLine(
              id: 'map-status',
              message: status.message,
              error: status.isError,
            ),
          ),
          const SizedBox(width: 4),
          w.ToolbarButton(
            label: '−',
            onPressed: () {
              _flightActive = false;
              session.zoomBy(-1);
            },
          ),
          SizedBox(
            width: 56,
            child: Text(
              'z${session.zoom.round()}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          w.ToolbarButton(
            label: '+',
            onPressed: () {
              _flightActive = false;
              session.zoomBy(1);
            },
          ),
          w.ToolbarButton(
            label: session.locateBusy ? 'Locating…' : 'Locate',
            onPressed: session.locateBusy ? null : () => session.locate(),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String?>(
              initialValue: controller.linkTargetId,
              hint: const Text('Attach to…',
                  style: TextStyle(fontSize: 12.5)),
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Select outline item',
                      style: TextStyle(fontSize: 12.5)),
                ),
                for (final item in controller.tocItems)
                  DropdownMenuItem<String?>(
                    value: item.id,
                    child: Text(
                      item.title,
                      style: const TextStyle(fontSize: 12.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                controller.setLinkTarget(value);
                setState(() {});
              },
            ),
          ),
          w.ToolbarButton(
            label: 'Attach location',
                  variant: w.ToolbarVariant.primary,
            onPressed: controller.linkTarget == null || session.pin == null
                ? null
                : () {
                    session.attachPinToSection();
                    setState(() {});
                  },
          ),
          w.ToolbarButton(
            label: controller.map.sidebarOpen
                ? 'Hide places'
                : 'Places (${controller.map.places.length})',
            onPressed: session.toggleSidebar,
          ),
        ],
      ),
    );
  }

  Widget _optionsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: WorkspaceColors.surfaceRaised,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 4,
        children: [
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: controller.map.filter,
              isDense: true,
              items: [
                for (final filter in mapFilters)
                  DropdownMenuItem(
                    value: filter,
                    child: Text(
                      switch (filter) {
                        'none' => 'Original colours',
                        'grayscale' => 'Grayscale',
                        'dark' => 'Dark',
                        'sepia' => 'Sepia',
                        'vivid' => 'Vivid',
                        _ => 'Faded',
                      },
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) session.setFilter(value);
                setState(() {});
              },
            ),
          ),
          Text(
            controller.map.renderer == 'canvas' ? 'Canvas renderer' : 'DOM renderer',
            style:
                const TextStyle(fontSize: 12, color: WorkspaceColors.textMuted),
          ),
          TextButton(
            onPressed: () => session.toggleGrid(),
            style: TextButton.styleFrom(
              foregroundColor: controller.map.showGrid
                  ? WorkspaceColors.accent
                  : WorkspaceColors.textMuted,
            ),
            child: Text('Grid ${controller.map.showGrid ? 'on' : 'off'}'),
          ),
          TextButton(
            onPressed: () => session.toggleCursor(),
            style: TextButton.styleFrom(
              foregroundColor: controller.map.showCursor
                  ? WorkspaceColors.accent
                  : WorkspaceColors.textMuted,
            ),
            child: Text('Cursor ${controller.map.showCursor ? 'on' : 'off'}'),
          ),
        ],
      ),
    );
  }

  Widget _canvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = Size(constraints.maxWidth, constraints.maxHeight);
        _requestTiles();
        final pin = session.pin;
        return Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: (_) => _startZoom = 0,
            onDoubleTapDown: (details) {
              _flightActive = false;
              session.zoomBy(1);
            },
            onTapUp: (details) => _dropPinAt(details.localPosition),
            child: MouseRegion(
              onHover: (event) {
                if (!controller.map.showCursor) return;
                final point = _unproject(event.localPosition);
                final next =
                    '${point.lat.toStringAsFixed(5)}, ${point.lon.toStringAsFixed(5)}';
                if (next != _cursorLabel) {
                  _cursorLabel = next;
                  _cursor = event.localPosition;
                  setState(() {});
                }
              },
              onExit: (_) {
                if (_cursor != null) {
                  _cursor = null;
                  setState(() {});
                }
              },
              cursor: SystemMouseCursors.click,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _MapPainter(
                        session: session,
                        tiles: widget.tiles,
                        scale: _scale,
                        safeZoom: _safeZoom,
                        centerLat: session.centerLat,
                        centerLon: session.centerLon,
                        size: _size,
                        filter: _filters[controller.map.filter] ??
                            _filters['none']!,
                        showGrid: controller.map.showGrid,
                        project: _project,
                        tileRect: _tileScreenRect,
                      ),
                    ),
                  ),
                  for (final place in controller.map.places)
                    if (_isOnScreen(place))
                      Positioned(
                        left: _project(place.lat, place.lon).dx - 8,
                        top: _project(place.lat, place.lon).dy - 8,
                        child: _placeMarker(place),
                      ),
                  if (pin != null && _isOnScreenLocation(pin))
                    Positioned(
                      left: _project(pin.lat, pin.lon).dx - 10,
                      top: _project(pin.lat, pin.lon).dy - 28,
                      child: const Icon(Icons.location_on,
                          color: Color(0xFFF06A5A), size: 26),
                    ),
                  if (controller.map.showCursor && _cursorLabel != null)
                    Positioned(
                      left: 10,
                      bottom: 34,
                      child: _readout(_cursorLabel!),
                    ),
                  if (session.pin != null && _selectedPlace != null)
                    Positioned(
                      left: 10,
                      bottom: 8,
                      child: _bearingReadout(),
                    ),
                  Positioned(
                    right: 10,
                    bottom: 8,
                    child: _scaleBar(),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 34,
                    child: Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: WorkspaceColors.text.withValues(alpha: 0.75),
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Place? get _selectedPlace {
    for (final place in controller.map.places) {
      if (place.id == session.selectedPlaceId) return place;
    }
    return null;
  }

  bool _isOnScreen(Place place) {
    final point = _project(place.lat, place.lon);
    return point.dx > -40 &&
        point.dy > -40 &&
        point.dx < _size.width + 40 &&
        point.dy < _size.height + 40;
  }

  bool _isOnScreenLocation(Location location) {
    final point = _project(location.lat, location.lon);
    return point.dx > -40 &&
        point.dy > -60 &&
        point.dx < _size.width + 40 &&
        point.dy < _size.height + 40;
  }

  Widget _placeMarker(Place place) {
    final selected = place.id == session.selectedPlaceId;
    return Tooltip(
      message: place.label,
      child: InkWell(
        onTap: () {
          session.selectPlace(place);
          setState(() {});
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: selected
                ? WorkspaceColors.accent
                : WorkspaceColors.surfaceRaised.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? WorkspaceColors.accent : WorkspaceColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag,
                  size: 13,
                  color: selected
                      ? WorkspaceColors.accentInk
                      : WorkspaceColors.accent),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  place.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: selected
                        ? WorkspaceColors.accentInk
                        : WorkspaceColors.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readout(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 11.5, color: Colors.white, fontFeatures: []),
        ),
      );

  Widget _bearingReadout() {
    final place = _selectedPlace!;
    final pin = session.pin!;
    final distance = distanceMeters(
      Location(lat: place.lat, lon: place.lon, label: place.label),
      pin,
    );
    final bearing = bearingDegrees(
      Location(lat: place.lat, lon: place.lon, label: place.label),
      pin,
    );
    if (distance == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${(bearing ?? 0).toStringAsFixed(0).padLeft(3, '0')}° '
        '${compassPoint(bearing)} · ${formatDistance(distance)} · '
        '${formatDistanceImperial(distance)}',
        style: const TextStyle(fontSize: 11.5, color: Colors.white),
      ),
    );
  }

  Widget _scaleBar() {
    final latRad = session.centerLat * math.pi / 180;
    final metersPerPixel =
        156543.03392 * math.cos(latRad) / math.pow(2, session.zoom);
    if (!metersPerPixel.isFinite || metersPerPixel <= 0) {
      return const SizedBox.shrink();
    }
    final targets = <double>[
      10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000,
      100000, 250000, 500000, 1000000
    ];
    double chosen = targets.first;
    for (final target in targets) {
      if (target / metersPerPixel <= 140) chosen = target;
    }
    final width = chosen / metersPerPixel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: width,
            height: 4,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 1),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${formatDistance(chosen)} · ${formatDistanceImperial(chosen)}',
            style: const TextStyle(fontSize: 10.5, color: Colors.white),
          ),
        ],
      ),
    );
  }

  /* --- sidebar ------------------------------------------------------------- */

  Widget _sidebar() {
    return Container(
      width: 292,
      decoration: const BoxDecoration(
        color: WorkspaceColors.surface,
        border: Border(right: BorderSide(color: WorkspaceColors.borderSubtle)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          Row(
            children: [
              const Expanded(child: w.Eyebrow('SAVED PLACES')),
              Text(
                key: const Key('map-place-count'),
                '${controller.map.places.length}',
                style: const TextStyle(
                    fontSize: 12, color: WorkspaceColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: w.ToolbarButton(
                  label: 'Save pin',
            variant: w.ToolbarVariant.primary,
                  onPressed: session.pin == null
                      ? null
                      : () {
                          session.savePin();
                          setState(() {});
                        },
                ),
              ),
              const SizedBox(width: 6),
              w.ToolbarButton(
                label: 'Clear',
                onPressed: controller.map.places.isEmpty
                    ? null
                    : () {
                        controller.clearPlaces();
                        setState(() {});
                      },
              ),
              const SizedBox(width: 6),
              w.ToolbarButton(label: 'Import', onPressed: _importPlaces),
            ],
          ),
          const SizedBox(height: 8),
          w.StatusLine(
            id: 'map-place-status',
            message: session.status.message,
            error: session.status.isError,
          ),
          const SizedBox(height: 8),
          if (controller.map.places.isEmpty)
            const Text(
              'No places yet. Click the map to drop a pin, then save it with a name.',
              style: TextStyle(
                  fontSize: 12.5, color: WorkspaceColors.textMuted),
            )
          else
            for (var index = 0;
                index < controller.map.places.length;
                index++)
              _placeRow(controller.map.places[index], index),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(child: w.Eyebrow('GEOJSON LAYERS')),
              Text(
                '${session.layers.fold<int>(0, (sum, layer) => sum + layer.featureCount)} features',
                style: const TextStyle(
                    fontSize: 12, color: WorkspaceColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: w.ToolbarButton(
                  label: 'Load GeoJSON',
                  onPressed: _loadGeoJson,
                ),
              ),
              const SizedBox(width: 6),
              w.ToolbarButton(
                label: 'Clear',
                onPressed: session.layers.isEmpty
                    ? null
                    : () {
                        session.clearLayers();
                        setState(() {});
                      },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (session.layers.isEmpty)
            const Text(
              'No layers loaded.',
              style: TextStyle(
                  fontSize: 12.5, color: WorkspaceColors.textMuted),
            )
          else
            for (final layer in session.layers.toList())
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${layer.name}${layer.visible ? '' : ' (hidden)'} · '
                        '${layer.featureCount}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    TextButton(
                      onPressed: () => session.toggleLayer(layer),
                      child: Text(layer.visible ? 'Hide' : 'Show'),
                    ),
                    IconButton(
                      tooltip: 'Remove layer',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 15),
                      onPressed: () => session.removeLayer(layer),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _placeRow(Place place, int index) {
    final active = session.pin != null &&
        session.pin!.lat == place.lat &&
        session.pin!.lon == place.lon;
    final selected = place.id == session.selectedPlaceId;
    final renaming = _renamingPlaceId == place.id;
    final previous = index > 0 ? controller.map.places[index - 1] : null;
    final leg = previous == null
        ? null
        : distanceMeters(
            Location(lat: previous.lat, lon: previous.lon),
            Location(lat: place.lat, lon: place.lon),
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? WorkspaceColors.surfaceRaised : WorkspaceColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: active || selected
              ? WorkspaceColors.accent
              : WorkspaceColors.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (leg != null && index > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '↳ ${formatDistance(leg)}',
                style: const TextStyle(
                    fontSize: 10.5, color: WorkspaceColors.textMuted),
              ),
            ),
          if (renaming)
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _renameController,
                    maxLength: 80,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(counterText: ''),
                    onFieldSubmitted: (_) => _commitRename(place),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: () => _commitRename(place),
                  child: const Text('Save'),
                ),
                TextButton(
                  onPressed: () => setState(() => _renamingPlaceId = null),
                  child: const Text('Cancel'),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      session.selectPlace(place);
                      setState(() {});
                    },
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        Text(
                          '${place.lat.toStringAsFixed(5)}, '
                          '${place.lon.toStringAsFixed(5)}',
                          style: const TextStyle(
                              fontSize: 10.5,
                              color: WorkspaceColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Link to outline item',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.link, size: 15),
                  onPressed: controller.linkTarget == null
                      ? null
                      : () {
                          session.attachPlaceToSection(place);
                          setState(() {});
                        },
                ),
                IconButton(
                  tooltip: 'Rename',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  onPressed: () {
                    _renamingPlaceId = place.id;
                    _renameController.text = place.label;
                    setState(() {});
                  },
                ),
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 15),
                  onPressed: () {
                    controller.removePlace(place);
                    setState(() {});
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _commitRename(Place place) {
    controller.renamePlace(place, _renameController.text);
    _renamingPlaceId = null;
    setState(() {});
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.session,
    required this.tiles,
    required this.scale,
    required this.safeZoom,
    required this.centerLat,
    required this.centerLon,
    required this.size,
    required this.filter,
    required this.showGrid,
    required this.project,
    required this.tileRect,
  });

  final MapSession session;
  final TileCache tiles;
  final double scale;
  final double safeZoom;
  final double centerLat;
  final double centerLon;
  final Size size;
  final ColorFilter filter;
  final bool showGrid;
  final Offset Function(double lat, double lon) project;
  final Rect Function(VisibleTile tile) tileRect;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    canvas.drawRect(
      Offset.zero & canvasSize,
      Paint()..color = const Color(0xFF1A1D23),
    );

    final list = visibleTiles(
      centerLat: centerLat,
      centerLon: centerLon,
      zoom: safeZoom,
      width: canvasSize.width,
      height: canvasSize.height,
    );

    final imagePaint = Paint()
      ..colorFilter = filter
      ..filterQuality = FilterQuality.low;

    for (final tile in list) {
      final image = tiles.peek(tile.z, tile.x, tile.y);
      if (image == null) continue;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        tileRect(tile),
        imagePaint,
      );
    }

    if (showGrid) _drawGrid(canvas, canvasSize);
    _drawGeoJson(canvas);
  }

  /// Grid lines aligned to the tile grid of the committed zoom level.
  void _drawGrid(Canvas canvas, Size canvasSize) {
    final step = tileSize * scale;
    if (step < 12) return;
    final center = projectToPixel(centerLon, centerLat, safeZoom);
    final originX = center.x - canvasSize.width / 2 / scale;
    final originY = center.y - canvasSize.height / 2 / scale;
    final firstX = (originX / tileSize).ceilToDouble() * tileSize;
    final firstY = (originY / tileSize).ceilToDouble() * tileSize;
    final paint = Paint()
      ..color = const Color(0x558AB4F8)
      ..strokeWidth = 1;
    for (var x = firstX;
        x <= originX + canvasSize.width / scale;
        x += tileSize) {
      final screen = (x - center.x) * scale + canvasSize.width / 2;
      canvas.drawLine(
        Offset(screen, 0),
        Offset(screen, canvasSize.height),
        paint,
      );
    }
    for (var y = firstY;
        y <= originY + canvasSize.height / scale;
        y += tileSize) {
      final screen = (y - center.y) * scale + canvasSize.height / 2;
      canvas.drawLine(
        Offset(0, screen),
        Offset(canvasSize.width, screen),
        paint,
      );
    }
  }

  void _drawGeoJson(Canvas canvas) {
    final stroke = Paint()
      ..color = const Color(0xFF8AB4F8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fill = Paint()
      ..color = const Color(0x558AB4F8)
      ..style = PaintingStyle.fill;
    final dot = Paint()..color = const Color(0xFFF06A5A);

    for (final layer in session.layers) {
      if (!layer.visible) continue;
      for (final shape in layer.shapes) {
        switch (shape.kind) {
          case GeoShapeKind.polygon:
            final path = Path();
            for (final ring in shape.rings) {
              for (var i = 0; i < ring.length; i++) {
                final point = project(ring[i].lat, ring[i].lon);
                if (i == 0) {
                  path.moveTo(point.dx, point.dy);
                } else {
                  path.lineTo(point.dx, point.dy);
                }
              }
              path.close();
            }
            canvas.drawPath(path, fill);
            canvas.drawPath(path, stroke);
          case GeoShapeKind.line:
            for (final ring in shape.rings) {
              final path = Path();
              for (var i = 0; i < ring.length; i++) {
                final point = project(ring[i].lat, ring[i].lon);
                if (i == 0) {
                  path.moveTo(point.dx, point.dy);
                } else {
                  path.lineTo(point.dx, point.dy);
                }
              }
              canvas.drawPath(path, stroke);
            }
          case GeoShapeKind.point:
            for (final ring in shape.rings) {
              for (final point in ring) {
                final screen = project(point.lat, point.lon);
                canvas.drawCircle(screen, shape.pointRadius, dot);
              }
            }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.session != session ||
      old.scale != scale ||
      old.centerLat != centerLat ||
      old.centerLon != centerLon ||
      old.filter != filter ||
      old.showGrid != showGrid ||
      old.size != size;
}
