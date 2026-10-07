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
import 'ui/widgets.dart';

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
  Widget get _footer => _StatusBar(
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

/// The shared bottom bar: the save mode, the workspace report pill, and which
/// tool is on screen.
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.controller,
    required this.signal,
    required this.persistence,
    required this.onDismissReport,
  });

  final WorkspaceController controller;
  final ChangeNotifier signal;
  final WorkspacePersistence persistence;
  final VoidCallback onDismissReport;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, signal]),
      builder: (context, _) {
        final pending = persistence.hasPendingSave;
        return Row(
          children: [
            Text(
              pending ? 'Saving…' : controller.saveLabel,
              key: const Key('save-mode'),
              style: const TextStyle(
                fontSize: 11.5,
                color: WorkspaceColors.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            WorkspaceReportPill(
              controller: controller,
              onDismiss: onDismissReport,
            ),
            const Spacer(),
            Text(
              controller.view.toUpperCase(),
              key: const Key('active-view'),
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                color: WorkspaceColors.textMuted,
              ),
            ),
            MenuGridButton(controller: controller),
          ],
        );
      },
    );
  }
}
