import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'workspace_models.dart';
import 'workspace_store.dart';

/// How long a burst of changes waits before it is written.
const int saveDebounceMs = 250;

class PersistenceReport {
  const PersistenceReport({
    required this.scope,
    required this.code,
    required this.message,
    required this.at,
  });

  final String scope; // 'load' | 'save'
  final String code;
  final String message;
  final int at;
}

enum PersistenceMode {
  native('saved to disk'),
  local('auto-saved'),
  none('not saved');

  const PersistenceMode(this.label);

  final String label;
}

String saveLabelFor(PersistenceMode mode) => mode.label;

/// Sources a persistence engine reads from and writes to. Injected so tests
/// can drive the debounce/merge rules without touching the filesystem.
class WorkspaceStoreBridge {
  const WorkspaceStoreBridge({
    required this.cachePath,
    required this.durablePath,
    this.hasNativeStore = true,
    this.store = const WorkspaceStore(),
  });

  final String cachePath;
  final String durablePath;
  final bool hasNativeStore;
  final WorkspaceStore store;

  /// The synchronous boot cache (the localStorage equivalent).
  bool saveCache(String payload) {
    if (!ensureDirectory(File(cachePath).parent.path)) return false;
    return store.save(cachePath, payload).isOkResult;
  }

  String? loadCache() {
    final loaded = store.load(cachePath);
    return loaded.ok ? loaded.data : null;
  }

  /// The durable file (the native loadWorkspace/saveWorkspace equivalent).
  bool saveDurable(String payload) {
    if (!ensureDirectory(File(durablePath).parent.path)) return false;
    return store.save(durablePath, payload).isOkResult;
  }

  WorkspaceStoreLoad loadDurableDetailed() => store.load(durablePath);
}

extension on WorkspaceStoreResult {
  bool get isOkResult => this == WorkspaceStoreResult.ok;
}

/// Rules for reconciling the boot cache with the durable copy, extracted as a
/// pure function so the merge can be tested without a filesystem:
///
/// * the durable copy wins unless it is strictly older than the boot copy;
/// * an empty durable store keeps the boot state;
/// * no durable store means no hydration at all;
/// * a user who already interacted never gets hydrated over.
WorkspaceRecord? hydrateWorkspace({
  required WorkspaceRecord boot,
  WorkspaceRecord? native,
  required bool hasNativeStore,
  required bool userInteracted,
}) {
  if (!hasNativeStore || userInteracted) return null;
  if (native == null) return null;
  if (native.savedAt < boot.savedAt) return null;
  return native;
}

/// The persistence engine: a 250 ms debounce in front of two writes, a
/// synchronous cache write first and the durable file second, plus the report
/// the header pill renders.
class WorkspacePersistence {
  WorkspacePersistence({
    required this.bridge,
    required this.snapshot,
    required this.apply,
    this.onFailure,
    this.onChanged,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final WorkspaceStoreBridge bridge;
  final WorkspaceRecord Function() snapshot;
  final void Function(WorkspaceRecord) apply;
  final void Function(String message)? onFailure;

  /// Called whenever [mode] or [report] may have changed, so a UI footer can
  /// refresh without polling.
  final void Function()? onChanged;

  final DateTime Function() _clock;

  Timer? _timer;
  PersistenceMode mode = PersistenceMode.none;
  PersistenceReport? report;
  String? _lastDurablePayload;
  int _pending = 0;

  bool get hasPendingSave => _timer?.isActive ?? false;

  /// Number of changes batched into the current debounce window.
  int get pendingSaves => _pending;

  void schedule() {
    _pending++;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: saveDebounceMs), flush);
  }

  /// Writes immediately. Returns the synchronous cache-write result, mirroring
  /// the C/JS engine where the local write is the caller-visible one.
  bool flush() {
    _timer?.cancel();
    _pending = 0;
    return persist();
  }

  bool persist() {
    final state = snapshot();
    final payload = serializeWorkspace(state);
    final savedLocally = bridge.saveCache(payload);

    if (!bridge.hasNativeStore) {
      mode = savedLocally ? PersistenceMode.local : PersistenceMode.none;
      _refreshReport(savedLocally: savedLocally, savedNatively: false);
      onChanged?.call();
      return savedLocally;
    }

    var savedNatively = false;
    if (payload != _lastDurablePayload) {
      savedNatively = bridge.saveDurable(payload);
      if (savedNatively) _lastDurablePayload = payload;
    } else {
      savedNatively = true;
    }

    if (savedNatively) {
      mode = PersistenceMode.native;
    } else {
      mode = savedLocally ? PersistenceMode.local : PersistenceMode.none;
    }
    _refreshReport(savedLocally: savedLocally, savedNatively: savedNatively);

    if (!savedLocally && !savedNatively) {
      onFailure?.call('Workspace not saved: both stores rejected the write.');
    }
    onChanged?.call();
    return savedLocally;
  }

  /// Boot-time reconciliation. Returns true when a durable copy was applied.
  bool hydrate(WorkspaceRecord boot) {
    if (!bridge.hasNativeStore) return false;
    final loaded = bridge.loadDurableDetailed();
    if (!loaded.ok) {
      recordLoadFailure('READ_FAILED', loaded.result.message);
      return false;
    }
    final raw = loaded.data;
    if (raw == null || raw.isEmpty) return false;
    if (!workspaceStoreIsObject(raw)) {
      recordLoadFailure(
        'INVALID_CONTENT',
        'The saved workspace file is damaged and cannot be restored.',
      );
      return false;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      recordLoadFailure(
        'INVALID_CONTENT',
        'The saved workspace file is damaged and cannot be restored.',
      );
      return false;
    }
    final restored = normalizeWorkspace(decoded);
    final chosen = hydrateWorkspace(
      boot: boot,
      native: restored,
      hasNativeStore: true,
      userInteracted: false,
    );
    if (chosen == null) return false;
    apply(chosen);
    _lastDurablePayload = serializeWorkspace(chosen);
    report = null;
    onChanged?.call();
    return true;
  }

  void clearSaveReport() {
    if (report?.scope == 'save') report = null;
    onChanged?.call();
  }

  void recordLoadFailure(String code, String message) {
    report = PersistenceReport(
      scope: 'load',
      code: code,
      message: message,
      at: _clock().millisecondsSinceEpoch,
    );
  }

  void recordSaveFailure(String code, String message) {
    report = PersistenceReport(
      scope: 'save',
      code: code,
      message: message,
      at: _clock().millisecondsSinceEpoch,
    );
  }

  void _refreshReport({
    required bool savedLocally,
    required bool savedNatively,
  }) {
    if (savedLocally || savedNatively) {
      clearSaveReport();
      return;
    }
    recordSaveFailure('WRITE_FAILED', 'This device rejected the workspace write.');
  }

  void dispose() {
    _timer?.cancel();
  }
}

/// The header pill sentence.
String formatWorkspaceReport(PersistenceReport? report) {
  if (report == null) return '';
  if (report.scope == 'save') {
    return 'Workspace not saved: ${report.message}';
  }
  return 'Saved workspace not restored: ${report.message}';
}
