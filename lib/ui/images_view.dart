import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../app/workspace_controller.dart';
import '../sessions/image_session.dart';
import 'widgets.dart' as w;

/// The Image Viewer: folder groups, a thumbnail grid, and the lightbox.
class ImagesView extends StatefulWidget {
  const ImagesView({
    super.key,
    required this.controller,
    required this.images,
    this.files = const FileService(),
  });

  final WorkspaceController controller;
  final ImageSession images;
  final FileService files;

  @override
  State<ImagesView> createState() => _ImagesViewState();
}

class _ImagesViewState extends State<ImagesView> {
  ImageSession get session => widget.images;
  WorkspaceController get controller => widget.controller;

  Future<void> _chooseDirectory({String? path}) async {
    var target = path;
    target ??= await widget.files.chooseDirectory(
      confirmButtonText: 'Choose an image folder',
    );
    if (target == null || !mounted) return;
    await session.openAt(target);
    if (mounted) setState(() {});
  }

  Future<void> _openLightbox(int index) async {
    session.openLightbox(index);
    setState(() {});
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _Lightbox(
        controller: controller,
        images: session,
        files: widget.files,
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, session]),
      builder: (context, _) {
        return Column(
          children: [
            _toolbar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (session.sidebarOpen) _sidebar(),
                  Expanded(
                    child: session.hasImages ? _grid() : _empty(),
                  ),
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
          const w.Eyebrow('IMAGE VIEWER'),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              session.hasImages ? session.directoryName : 'Choose an image directory',
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 140, maxWidth: 420),
            child: w.StatusLine(
              id: 'image-status',
              message: status.message,
              error: status.isError,
            ),
          ),
          const SizedBox(width: 4),
          if (session.hasImages)
            w.ToolbarButton(
              label: 'Choose directory',
              variant: w.ToolbarVariant.primary,
              onPressed: () => _chooseDirectory(),
            ),
          w.ToolbarButton(
            label: session.sidebarOpen
                ? 'Hide folders'
                : 'Folders (${session.groups.isNotEmpty ? session.groups.length - 1 : 0})',
            onPressed: session.toggleSidebar,
          ),
        ],
      ),
    );
  }

  Widget _sidebar() {
    final groups = session.groups;
    return Container(
      width: 236,
      decoration: const BoxDecoration(
        color: WorkspaceColors.surface,
        border: Border(right: BorderSide(color: WorkspaceColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: const w.Eyebrow('FOLDERS'),
          ),
          Expanded(
            child: groups.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Open a folder to group its images.',
                      style: TextStyle(
                          fontSize: 12.5, color: WorkspaceColors.textMuted),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                    children: [
                      for (final group in groups) _groupButton(group),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _groupButton(ImageGroup group) {
    final selected = controller.images.selectedGroup == group.name;
    return TextButton(
      onPressed: () {
        session.selectGroup(group.name);
        setState(() {});
      },
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        backgroundColor:
            selected ? WorkspaceColors.surfaceRaised : Colors.transparent,
        foregroundColor:
            selected ? WorkspaceColors.accent : WorkspaceColors.text,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              group.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: WorkspaceColors.surfaceRaised,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '${group.images.length}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid() {
    final visible = session.visibleImages;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 190).floor().clamp(2, 8);
        return GridView.builder(
          padding: const EdgeInsets.all(14),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.15,
          ),
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final image = visible[index];
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openLightbox(index),
              child: Container(
                decoration: BoxDecoration(
                  color: WorkspaceColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: WorkspaceColors.borderSubtle),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Image.file(
                        File(image.path),
                        fit: BoxFit.cover,
                        cacheWidth: 320,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: WorkspaceColors.textMuted),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Text(
                        image.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: WorkspaceColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _empty() {
    final remembered = controller.images.recentPaths;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: WorkspaceColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: WorkspaceColors.border),
                ),
                child: const Text('IMG',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: WorkspaceColors.accent)),
              ),
              const SizedBox(height: 14),
              const Text('Open a folder of images',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'Images are grouped by the folders they live in.',
                textAlign: TextAlign.center,
                style: TextStyle(color: WorkspaceColors.textMuted),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _chooseDirectory(),
                child: const Text('Choose directory'),
              ),
              if (remembered.isNotEmpty) ...[
                const SizedBox(height: 26),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: w.Eyebrow('REMEMBERED'),
                ),
                const SizedBox(height: 8),
                for (final path in remembered.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () => _chooseDirectory(path: path),
                        icon: const Icon(Icons.history, size: 15),
                        label: Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          backgroundColor: WorkspaceColors.card,
                          foregroundColor: WorkspaceColors.text,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The lightbox: wrapping navigation, a caption, and the attach row.
class _Lightbox extends StatefulWidget {
  const _Lightbox({
    required this.controller,
    required this.images,
    required this.files,
  });

  final WorkspaceController controller;
  final ImageSession images;
  final FileService files;

  @override
  State<_Lightbox> createState() => _LightboxState();
}

class _LightboxState extends State<_Lightbox> {
  final FocusNode _focus = FocusNode();
  final ScrollController _targets = ScrollController();

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    _targets.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.images.closeLightbox();
      Navigator.of(context).maybePop();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      widget.images.stepLightbox(1);
      setState(() {});
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      widget.images.stepLightbox(-1);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.images;
    final visible = session.visibleImages;
    final index = session.lightboxIndex;
    if (index < 0 || index >= visible.length) {
      return const SizedBox.shrink();
    }
    final image = visible[index];

    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, event) {
        _handleKey(event);
        return KeyEventResult.handled;
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Stack(
                children: [
                  Center(
                    child: InteractiveViewer(
                      maxScale: 6,
                      child: Image.file(
                        File(image.path),
                        errorBuilder: (_, _, _) => const SizedBox(
                          width: 320,
                          height: 240,
                          child: Center(
                            child: Text('This image could not be opened.',
                                style: TextStyle(color: Colors.white70)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: 'Close',
                      onPressed: () {
                        session.closeLightbox();
                        Navigator.of(context).maybePop();
                      },
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                  if (visible.length > 1) ...[
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: IconButton(
                          tooltip: 'Previous',
                          onPressed: () {
                            session.stepLightbox(-1);
                            setState(() {});
                          },
                          icon: const Icon(Icons.chevron_left,
                              color: Colors.white, size: 36),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: IconButton(
                          tooltip: 'Next',
                          onPressed: () {
                            session.stepLightbox(1);
                            setState(() {});
                          },
                          icon: const Icon(Icons.chevron_right,
                              color: Colors.white, size: 36),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: WorkspaceColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: WorkspaceColors.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${image.relativePath} · ${index + 1} of ${visible.length}',
                    style: const TextStyle(fontSize: 12.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          isExpanded: true,
                          initialValue: widget.controller.linkTargetId,
                          hint: const Text('Select outline item',
                              style: TextStyle(fontSize: 12.5)),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Select outline item',
                                  style: TextStyle(fontSize: 12.5)),
                            ),
                            for (final item in widget.controller.tocItems)
                              DropdownMenuItem<String?>(
                                value: item.id,
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 220),
                                  child: Text(
                                    item.title,
                                    style: const TextStyle(fontSize: 12.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              widget.controller.setLinkTarget(value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: widget.controller.linkTarget == null
                            ? null
                            : () {
                                if (session.attachCurrentToSection()) {
                                  setState(() {});
                                }
                              },
                        child: const Text('Attach to section'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
