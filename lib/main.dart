import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/theme.dart';
import 'app/workspace_controller.dart';
import 'core/map/tile_source.dart';
import 'core/workspace/workspace_models.dart';
import 'core/workspace/workspace_persistence.dart';
import 'sessions/image_session.dart';
import 'sessions/map_session.dart';
import 'sessions/pdf_session.dart';
import 'ui/editor_view.dart';
import 'ui/images_view.dart';
import 'ui/map_view.dart';
import 'ui/menu_view.dart';
import 'ui/pdf_view.dart';
import 'ui/shell.dart';
import 'ui/toc_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final directories = await _resolveDirectories();
  final bridge = WorkspaceStoreBridge(
    cachePath: '${directories.cache.path}/workspace.json',
    durablePath:
        '${directories.support.path}/native-workspace/workspace.json',
  );

  final boot = readBootCache(bridge);
  final controller = WorkspaceController(boot: boot);

  // The persistence engine is pure Dart, so the footer listens through this
  // signal instead of the engine itself.
  final persistenceSignal = _Signal();

  final persistence = startPersistence(
    boot: boot,
    controller: controller,
    bridge: bridge,
    onChanged: persistenceSignal.ping,
  );

  final pdf = PdfSession(controller);
  final images = ImageSession(controller);
  final map = MapSession(controller);

  // Bring back what the last run remembered: the open document at its
  // recorded page/zoom and the browsed folder at its recorded group. Gone
  // files get a sentence instead of a silent empty tool (TODO-016).
  await reopenRemembered(pdf: pdf, images: images, controller: controller);

  runApp(WorkspaceApp(
    controller: controller,
    persistence: persistence,
    persistenceSignal: persistenceSignal,
    pdf: pdf,
    images: images,
    map: map,
    tiles: TileCache(
      cacheDirectory: Directory('${directories.cache.path}/tiles'),
    ),
  ));
}

/// Reopens what the last run remembered so a restart lands where you were:
/// the PDF at its recorded page/zoom, the image folder at its recorded
/// group. A remembered path whose file is gone is forgotten with a sentence
/// in that tool's status line instead of failing silently.
Future<void> reopenRemembered({
  required PdfSession pdf,
  required ImageSession images,
  required WorkspaceController controller,
}) async {
  final pdfPath = controller.pdf.path;
  if (pdfPath.isNotEmpty) {
    if (!File(pdfPath).existsSync()) {
      controller.forgetPdfPath(pdfPath);
      pdf.setStatus(
          'The remembered document is gone — pick it again to reopen it.',
          error: true);
    } else {
      // openAt applies the recorded page (clamped) and zoom, remembers the
      // path again, and reports a sentence when the file won't open.
      await pdf.openAt(pdfPath);
    }
  }

  final directory = controller.images.directoryPath;
  if (directory.isNotEmpty) {
    if (!Directory(directory).existsSync()) {
      controller.forgetImageDirectory(directory);
      images.setStatus(
          'The remembered folder is gone — pick it again to reopen it.',
          error: true);
    } else {
      // openAt resets the group to 'All Images'; capture the recorded one
      // first so it can be put back when it still exists.
      final recordedGroup = controller.images.selectedGroup;
      final opened = await images.openAt(directory);
      if (opened &&
          recordedGroup.isNotEmpty &&
          recordedGroup != 'All Images' &&
          images.groups.any((group) => group.name == recordedGroup)) {
        images.selectGroup(recordedGroup);
      }
    }
  }
}

/// A change listener for the persistence engine's mode/report transitions.
class _Signal extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _Directories {
  const _Directories({required this.cache, required this.support});

  final Directory cache;
  final Directory support;
}

Future<_Directories> _resolveDirectories() async {
  final cache = await getApplicationCacheDirectory();
  final support = await getApplicationSupportDirectory();
  return _Directories(cache: cache, support: support);
}

/// The boot cache is the synchronous "what did the last run leave behind?"
/// read: a damaged file degrades to an empty workspace instead of failing.
///
/// The record returned here is also the boot snapshot the durable copy is
/// merged against, so both sides of `hydrateWorkspace` carry the timestamps
/// they had on disk rather than a freshly stamped one.
WorkspaceRecord readBootCache(WorkspaceStoreBridge bridge) {
  final raw = bridge.loadCache();
  if (raw == null || raw.isEmpty) return normalizeWorkspace(null);
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return normalizeWorkspace(null);
  }
  return normalizeWorkspace(decoded);
}

/// Builds the persistence engine, attaches it to [controller], and hydrates
/// the shared record from the durable copy using the boot cache as the other
/// half of the merge.
WorkspacePersistence startPersistence({
  required WorkspaceRecord boot,
  required WorkspaceController controller,
  required WorkspaceStoreBridge bridge,
  void Function()? onChanged,
}) {
  final persistence = WorkspacePersistence(
    bridge: bridge,
    snapshot: controller.snapshot,
    apply: controller.apply,
    onFailure: (message) =>
        controller.persistence?.recordSaveFailure('WRITE_FAILED', message),
    onChanged: () {
      controller.notifyChanged();
      onChanged?.call();
    },
  );
  controller.persistence = persistence;
  persistence.hydrate(boot);
  return persistence;
}

class WorkspaceApp extends StatefulWidget {
  const WorkspaceApp({
    super.key,
    required this.controller,
    required this.persistence,
    required this.persistenceSignal,
    required this.pdf,
    required this.images,
    required this.map,
    required this.tiles,
  });

  final WorkspaceController controller;
  final WorkspacePersistence persistence;
  final ChangeNotifier persistenceSignal;
  final PdfSession pdf;
  final ImageSession images;
  final MapSession map;
  final TileCache tiles;

  @override
  State<WorkspaceApp> createState() => _WorkspaceAppState();
}

class _WorkspaceAppState extends State<WorkspaceApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onPause: _flushWorkspace,
      onHide: _flushWorkspace,
      onDetach: _flushWorkspace,
    );
  }

  void _flushWorkspace() => widget.controller.flushNow();
  Widget get _footer => WorkspaceStatusBar(
        controller: widget.controller,
        signal: widget.persistenceSignal,
        persistence: widget.persistence,
        onDismissReport: () {
          widget.persistence.clearSaveReport();
          widget.controller.notifyChanged();
        },
      );

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return MaterialApp(
      title: 'chainnotes',
      debugShowCheckedModeBanner: false,
      theme: buildWorkspaceTheme(),
      home: WorkspaceShell(
        controller: controller,
        footer: _footer,
        views: [
          MenuView(
            controller: controller,
            pdf: widget.pdf,
            images: widget.images,
            map: widget.map,
          ),
          TocView(
            controller: controller,
            pdf: widget.pdf,
            images: widget.images,
            map: widget.map,
          ),
          EditorView(controller: controller),
          PdfView(controller: controller, pdf: widget.pdf),
          ImagesView(controller: controller, images: widget.images),
          MapView(
            controller: controller,
            map: widget.map,
            tiles: widget.tiles,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.controller.flushNow();
    widget.persistence.dispose();
    widget.tiles.dispose();
    widget.pdf.closeDocument();
    super.dispose();
  }
}
