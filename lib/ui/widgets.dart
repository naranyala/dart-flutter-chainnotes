import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../app/workspace_controller.dart';

enum ToolbarVariant { primary, subtle }

/// The shared `.toolbar-button` vocabulary from `styles/shell.css`.
class ToolbarButton extends StatelessWidget {
  const ToolbarButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = ToolbarVariant.subtle,
    this.leading,
    this.tooltip,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final ToolbarVariant variant;
  final Widget? leading;
  final String? tooltip;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 6)],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
    final button = switch (variant) {
      ToolbarVariant.primary => FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 44),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          child: child),
      ToolbarVariant.subtle => OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 44),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          child: child),
    };
    final padded = dense
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: button,
          )
        : button;
    if (tooltip == null) return padded;
    return Tooltip(message: tooltip!, child: padded);
  }
}

/// One status sentence per tool: `role="status"`, errors styled in danger.
class StatusLine extends StatelessWidget {
  const StatusLine({
    super.key,
    required this.id,
    this.message = '',
    this.error = false,
  });

  final String id;
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: Text(
        message,
        key: Key(id),
        style: TextStyle(
          fontSize: 12.5,
          color: error ? WorkspaceColors.danger : WorkspaceColors.textMuted,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// The eyebrow label every tool toolbar starts with.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
        color: WorkspaceColors.textMuted,
      ),
    );
  }
}

/// A bordered panel used by the sidebars.
class SidePanel extends StatelessWidget {
  const SidePanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 268,
      decoration: const BoxDecoration(
        color: WorkspaceColors.surface,
        border: Border(right: BorderSide(color: WorkspaceColors.borderSubtle)),
      ),
      padding: padding ?? const EdgeInsets.all(12),
      child: child,
    );
  }
}

/// The pill button that toggles a sidebar.
class PanelToggle extends StatelessWidget {
  const PanelToggle({super.key, required this.label, required this.open, required this.onPressed});

  final String label;
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(open ? Icons.chevron_right : Icons.chevron_left, size: 16),
      label: Text(label),
    );
  }
}

/// Shared toolbar row chrome: eyebrow, status, actions, spacer.
class ToolToolbar extends StatelessWidget {
  const ToolToolbar({super.key, required this.children, this.height = topBarHeight});

  final List<Widget> children;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: WorkspaceColors.surface,
        border: Border(bottom: BorderSide(color: WorkspaceColors.borderSubtle)),
      ),
      child: Row(
        children: [
          for (final child in children) ...[
            child,
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// The status bar's way back: one button that shows the entire menu grid
/// again from any tool.
class MenuGridButton extends StatelessWidget {
  const MenuGridButton({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('show-menu-grid'),
      tooltip: 'Show menu grid',
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      color: WorkspaceColors.textMuted,
      onPressed: () => controller.selectView('menu'),
      icon: const Icon(Icons.grid_view),
    );
  }
}
