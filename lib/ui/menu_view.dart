import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../app/workspace_controller.dart';
import '../core/workspace/workspace_models.dart';
import '../sessions/image_session.dart';
import '../sessions/map_session.dart';
import '../sessions/pdf_session.dart';
import '../ui/widgets.dart' as w;

/// The launcher: one card per tool with a live badge, ported from
/// `MenuView.vue`.
class MenuView extends StatelessWidget {
  const MenuView({
    super.key,
    required this.controller,
    required this.pdf,
    required this.images,
    required this.map,
  });

  final WorkspaceController controller;
  final PdfSession pdf;
  final ImageSession images;
  final MapSession map;

  String get _tocBadge {
    if (controller.tocItems.isEmpty) {
      return 'Declare outline items, then write each section';
    }
    final written = controller.tocItems
        .where((item) => item.content.trim().isNotEmpty)
        .length;
    return '${controller.tocItems.length} items declared · $written written';
  }

  String get _editorBadge {
    final active = controller.activeTocItem;
    final words = countWords(controller.editorContent);
    if (active != null) return 'Writing “${active.title}” · $words words';
    if (controller.editorContent.trim().isNotEmpty) {
      return '$words words in an unpicked draft';
    }
    return 'Pick a section to start writing';
  }

  String get _summary {
    final items = controller.tocItems.length;
    final words = countWords(controller.editorContent);
    if (items == 0 && words == 0) return 'Empty workspace';
    return '$items section${items == 1 ? '' : 's'} · $words words';
  }

  @override
  Widget build(BuildContext context) {
    final cards = <_ToolCardData>[
      _ToolCardData(
        view: 'toc',
        glyph: 'TOC',
        title: 'TOC Manager',
        badge: _tocBadge,
      ),
      _ToolCardData(
        view: 'editor',
        glyph: 'Aa',
        title: 'Text Editor',
        badge: _editorBadge,
      ),
      _ToolCardData(
        view: 'pdf',
        glyph: 'PDF',
        title: 'PDF Reader',
        badge: pdf.badge,
      ),
      _ToolCardData(
        view: 'images',
        glyph: 'IMG',
        title: 'Image Viewer',
        badge: images.badge,
      ),
      _ToolCardData(
        view: 'map',
        glyph: 'MAP',
        title: 'Map Explorer',
        badge: map.badge,
      ),
    ];

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.4, -0.6),
                radius: 1.2,
                colors: [Color(0xFF1B2029), WorkspaceColors.background],
              ),
            ),
            child: Column(
              children: [
                _navbar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const w.Eyebrow('APPLICATIONS'),
                        const SizedBox(height: 8),
                        Text(
                          'What would you like to open?',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Choose a local tool to get started.',
                          style: TextStyle(color: WorkspaceColors.textMuted),
                        ),
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            // Cards fill the whole width at any window size:
                            // one column on phones, two on narrow windows,
                            // three beyond that.
                            final narrow = constraints.maxWidth < 560;
                            final columns = narrow
                                ? 1
                                : constraints.maxWidth < 1100
                                    ? 2
                                    : 3;
                            return GridView.count(
                              crossAxisCount: columns,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              mainAxisSpacing: 18,
                              crossAxisSpacing: 18,
                              childAspectRatio: narrow ? 3.2 : 2.4,
                              children: [
                                for (final card in cards)
                                  _ToolCard(
                                    data: card,
                                    onTap: () =>
                                        controller.selectView(card.view),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  /// Full-width top bar matching the other tools' toolbars, so the menu opens
  /// on chrome that spans the window instead of floating text.
  Widget _navbar() {
    return Container(
      key: const Key('menu-navbar'),
      constraints: const BoxConstraints(minHeight: topBarHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: WorkspaceColors.surface,
        border: Border(bottom: BorderSide(color: WorkspaceColors.borderSubtle)),
      ),
      child: Row(
        children: [
          const w.Eyebrow('APPLICATIONS'),
          const Spacer(),
          Flexible(
            child: Text(
              _summary,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: WorkspaceColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolCardData {
  const _ToolCardData({
    required this.view,
    required this.glyph,
    required this.title,
    required this.badge,
  });

  final String view;
  final String glyph;
  final String title;
  final String badge;
}

class _ToolCard extends StatefulWidget {
  const _ToolCard({required this.data, required this.onTap});

  final _ToolCardData data;
  final VoidCallback onTap;

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _hovered ? WorkspaceColors.cardHover : WorkspaceColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: WorkspaceColors.borderSubtle),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: WorkspaceColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: WorkspaceColors.border),
                ),
                child: Text(
                  data.glyph,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 0.5,
                    color: WorkspaceColors.accent,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data.badge,
                      style: const TextStyle(
                        fontSize: 12,
                        color: WorkspaceColors.textMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: WorkspaceColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
