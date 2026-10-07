import 'dart:convert';
import 'dart:io';

/// Upper bound for a stored workspace payload (serialized JSON): 4 MiB.
const int workspaceStoreMaxBytes = 4 * 1024 * 1024;

enum WorkspaceStoreResult {
  ok('ok'),
  tooLarge('the workspace payload exceeds the storage limit'),
  read('the workspace file could not be read'),
  write('the workspace file could not be written'),
  argument('the request argument is not a JSON string'),
  outOfMemory('memory allocation failed');

  const WorkspaceStoreResult(this.message);

  final String message;
}

class WorkspaceStoreLoad {
  const WorkspaceStoreLoad.ok(this.data) : result = WorkspaceStoreResult.ok;
  const WorkspaceStoreLoad.failed(this.result) : data = null;

  final String? data;
  final WorkspaceStoreResult result;

  bool get ok => result == WorkspaceStoreResult.ok;
}

/// Durable workspace file store.
///
/// Power-loss guarantee (explicit): save writes `workspace.json.tmp`,
/// flushes the file content (`flushSync`), then renames it over the target.
/// A completed write never leaves a half-written workspace behind, but the
/// file is NOT fsynced before the rename and the parent directory is NOT
/// fsynced after it — `dart:io` exposes neither. An OS crash or power loss
/// in that window may therefore lose the last write even after `ok` was
/// returned. Crash-during-write is safe (old file or new file, never half);
/// power-loss-during-rename is only as durable as the platform's rename.
///
/// Load checks the on-disk size *before* reading so a runaway file never costs
/// an allocation, and save writes `workspace.json.tmp`, flushes it, renames it
/// over the target, and flushes again.
///
/// Note: `dart:io` does not expose a directory-level fsync, so the rename is
/// atomic but the directory entry is only as durable as the platform's rename.
class WorkspaceStore {
  const WorkspaceStore();

  /// Reads the file. A missing file is success with an empty payload: no state
  /// written yet is not an error.
  WorkspaceStoreLoad load(String path) {
    if (path.isEmpty) {
      return const WorkspaceStoreLoad.failed(WorkspaceStoreResult.read);
    }
    try {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        return const WorkspaceStoreLoad.ok('');
      }
      if (type != FileSystemEntityType.file) {
        return const WorkspaceStoreLoad.failed(WorkspaceStoreResult.read);
      }
      // Size first: a runaway file never costs an allocation.
      final size = File(path).lengthSync();
      if (size > workspaceStoreMaxBytes) {
        return const WorkspaceStoreLoad.failed(WorkspaceStoreResult.tooLarge);
      }
      final bytes = File(path).readAsBytesSync();
      if (bytes.length > workspaceStoreMaxBytes) {
        return const WorkspaceStoreLoad.failed(WorkspaceStoreResult.tooLarge);
      }
      return WorkspaceStoreLoad.ok(utf8.decode(bytes, allowMalformed: true));
    } on FileSystemException {
      if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
        return const WorkspaceStoreLoad.ok('');
      }
      return const WorkspaceStoreLoad.failed(WorkspaceStoreResult.read);
    }
  }

  WorkspaceStoreResult save(String path, String data) {
    if (path.isEmpty) {
      return WorkspaceStoreResult.argument;
    }
    final bytes = utf8.encode(data);
    if (bytes.length > workspaceStoreMaxBytes) {
      return WorkspaceStoreResult.tooLarge;
    }
    final temp = File('$path.tmp');
    try {
      final raf = temp.openSync(mode: FileMode.write);
      try {
        raf.writeFromSync(bytes);
        raf.flushSync();
      } finally {
        raf.closeSync();
      }
      temp.renameSync(path);
      return WorkspaceStoreResult.ok;
    } on FileSystemException {
      if (temp.existsSync()) {
        try {
          temp.deleteSync();
        } on FileSystemException {
          // Nothing more we can do; the temp file is already abandoned.
        }
      }
      return WorkspaceStoreResult.write;
    }
  }
}

/// A shallow check only: leading and trailing whitespace allowed, the payload
/// must begin with `{` and end with `}`. It does not parse JSON, exactly like
/// `workspace_store_is_object` in C.
bool workspaceStoreIsObject(String? data) {
  if (data == null || data.isEmpty) return false;
  var start = 0;
  var end = data.length;
  while (start < end && _isSpace(data.codeUnitAt(start))) {
    start++;
  }
  if (start >= end || data.codeUnitAt(start) != 0x7b) return false;
  while (end > start && _isSpace(data.codeUnitAt(end - 1))) {
    end--;
  }
  return end > start && data.codeUnitAt(end - 1) == 0x7d;
}

bool _isSpace(int code) =>
    code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d || code == 0x0c;

/// `$XDG_DATA_HOME/native-workspace/workspace.json` on every platform we
/// target: the durable home of the record.
String workspaceDirectoryPath(String dataDirectory) =>
    '$dataDirectory${Platform.pathSeparator}native-workspace';

String workspaceFilePath(String dataDirectory) =>
    '${workspaceDirectoryPath(dataDirectory)}${Platform.pathSeparator}workspace.json';

/// Creates a directory the store is about to write into (the equivalent of
/// `ensure_workspace_directory` in C). The store itself never creates
/// directories, so a missing parent still fails the write.
bool ensureDirectory(String directoryPath) {
  final directory = Directory(directoryPath);
  try {
    if (directory.existsSync()) return true;
    directory.createSync(recursive: true);
    return directory.existsSync();
  } on FileSystemException {
    return false;
  }
}
