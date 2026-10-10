import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../app/workspace_controller.dart';
import '../core/workspace/workspace_persistence.dart';
import 'widgets.dart';

/// The application shell: every tool stays mounted in one `Stack` (the
/// Flutter equivalent of the original's `v-show` panes) so scroll position,
/// rendered pages, and canvas state survive a switch, with the shared status
/// bar underneath.
///
/// Switching tools crossfades with a short slide in the direction of the menu
/// order. Each pane keeps its own `State` the whole time — the animation only
/// changes opacity, pointer handling, and visibility, never the widget tree
/// position — and fully faded panes leave the paint and semantics trees
/// (state kept) while their tickers are muted.
///
/// How long a tool switch takes: short enough to feel instant, long enough
/// to read as a transition rather than a cut. Honoured as-is unless the
/// platform asks for reduced motion, in which case switches are jump cuts.
const Duration toolSwitchDuration = Duration(milliseconds: 200);

/// The application shell: every tool stays mounted, with the shared status
/// bar underneath.
class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({
    super.key,
    required this.controller,
    required this.views,
    required this.footer,
  });

  final WorkspaceController controller;

  /// One widget per tool, in `shellOrder`. Instances must stay in the same
  /// positions across rebuilds — the transition keeps each pane's `State`
  /// by position.
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

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  late int _lastIndex;

  /// Slide direction of the latest switch: +1 slides in from the right
  /// (forward in menu order), -1 from the left (going back).
  int _slideDirection = 1;

  @override
  void initState() {
    super.initState();
    _lastIndex = _index;
  }

  int get _index {
    final index = WorkspaceShell.shellOrder.indexOf(widget.controller.view);
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final index = _index;
        if (index != _lastIndex) {
          _slideDirection = index > _lastIndex ? 1 : -1;
          _lastIndex = index;
        }
        final onMenu = controller.view == 'menu';
        // Respect the platform reduced-motion setting: jump cuts only.
        final animate =
            !(MediaQuery.maybeAccessibleNavigationOf(context) ?? false);
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
                    child: Stack(
                      children: [
                        for (var i = 0; i < widget.views.length; i++)
                          _FadingChild(
                            active: i == index,
                            slideDirection: _slideDirection,
                            animate: animate,
                            child: widget.views[i],
                          ),
                      ],
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
                    // NOTE: the footer is already a Row (WorkspaceStatusBar). It must
                    // sit here directly: wrapping it in another Row would hand it
                    // unbounded width, and its flex children (Spacer/Expanded) would
                    // throw during layout and kill the first frame.
                    child: widget.footer,
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

/// One pane of the animated tool stack. The wrapped view keeps its `State`
/// for the life of the shell: switching only fades/slides it, drops it from
/// hit testing, and (once fully faded) from paint and semantics — muted
/// tickers included, so a hidden map canvas costs nothing.
class _FadingChild extends StatefulWidget {
  const _FadingChild({
    required this.active,
    required this.slideDirection,
    required this.animate,
    required this.child,
  });

  /// Whether this pane is the one on screen.
  final bool active;

  /// +1 slides in from the right, -1 from the left.
  final int slideDirection;

  /// False under reduced motion: jump cuts, no animation controllers running.
  final bool animate;

  final Widget child;

  @override
  State<_FadingChild> createState() => _FadingChildState();
}

class _FadingChildState extends State<_FadingChild>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  late Animation<Offset> _slide;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: toolSwitchDuration,
      value: widget.active ? 1.0 : 0.0,
    );
    _visible = widget.active;
    _slide = _slideFor();
  }

  Animation<Offset> _slideFor() => Tween<Offset>(
    begin: Offset(0.035 * widget.slideDirection, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _fade, curve: Curves.easeOutCubic));

  @override
  void didUpdateWidget(_FadingChild oldWidget) {
    super.didUpdateWidget(oldWidget);
    _slide = _slideFor();
    if (!widget.animate) {
      _fade.value = widget.active ? 1.0 : 0.0;
      _visible = widget.active;
      return;
    }
    if (widget.active && !oldWidget.active) {
      setState(() => _visible = true);
      _fade.forward();
    } else if (!widget.active && oldWidget.active) {
      // Fade out first so the switch reads as a crossfade; only then leave
      // the paint/semantics trees (state is kept either way).
      _fade.reverse().then((_) {
        if (mounted && !widget.active) setState(() => _visible = false);
      });
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Visibility(
      visible: _visible,
      maintainState: true,
      maintainAnimation: true,
      child: TickerMode(
        enabled: widget.active,
        child: IgnorePointer(
          ignoring: !widget.active,
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(position: _slide, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// The shared bottom bar: the save mode, the workspace report pill, and which
/// tool is on screen. Public (and built by the composition root) so widget
/// tests can mount the real footer — a stub footer once hid a layout
/// exception here that killed the first frame on device.
class WorkspaceStatusBar extends StatelessWidget {
  const WorkspaceStatusBar({
    super.key,
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Text(
                controller.view.toUpperCase(),
                key: ValueKey(controller.view),
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: WorkspaceColors.textMuted,
                ),
              ),
            ),
            MenuGridButton(controller: controller),
          ],
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
