import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../app/workspace_controller.dart';
import '../core/workspace/workspace_persistence.dart';

/// The application shell: every tool stays mounted (an `IndexedStack`, the
/// Flutter equivalent of the original's `v-show` panes) so scroll position,
/// rendered pages, and canvas state survive a switch, with the shared status
/// bar underneath.
class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({
    super.key,
    required this.controller,
    required this.views,
    required this.footer,
  });

  final WorkspaceController controller;

  /// One widget per tool, in `shellOrder`.
  final List<Widget> views;

  /// The bottom bar contents, built by the composition root.
  final Widget footer;

  static const List<String> shellOrder = [
    'menu',
    'toc',
    'editor',
    'pdf',
    'images',
    'map',
  ];

  int get _index {
    final index = shellOrder.indexOf(controller.view);
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final onMenu = controller.view == 'menu';
        return PopScope(
          // On phones the system back button goes back to the menu instead
          // of leaving the app, so a stray back press never loses context.
          canPop: onMenu,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !onMenu) controller.selectView('menu');
          },
          child: Scaffold(
      backgroundColor: WorkspaceColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => IndexedStack(
                  index: _index,
                  children: views,
                ),
              ),
            ),
            Container(
              height: statusBarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                color: WorkspaceColors.surface,
                border: Border(
                  top: BorderSide(color: WorkspaceColors.borderSubtle),
                ),
              ),
              child: Row(
                children: [
                  footer,
                ],
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
}

/// The header pill: `Workspace not saved: …` / `Saved workspace not restored: …`
class WorkspaceReportPill extends StatelessWidget {
  const WorkspaceReportPill({
    super.key,
    required this.controller,
    required this.onDismiss,
  });

  final WorkspaceController controller;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final report = controller.report;
    if (report == null) return const SizedBox.shrink();
    final text = formatWorkspaceReport(report);
    if (text.isEmpty) return const SizedBox.shrink();
    return Expanded(
      child: Row(
        children: [
          Flexible(
            child: Tooltip(
              message: text,
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: WorkspaceColors.danger,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}
