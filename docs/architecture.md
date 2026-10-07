# Architecture and data flow

## The one rule

> **The views own input and presentation. The core owns validation, state,
> and persistence.**

Almost every design decision follows from that sentence, so it is worth being
concrete about what it forbids:

- A view must not parse a file, decode JSON, or decide whether input is
  valid — it asks a session or `WorkspaceController`.
- A view must not reach the network or the filesystem directly — `FileService`,
  `TileCache`, and `WorkspaceStore` are the only modules that do.
- Shared state must not be mirrored: there is one `WorkspaceRecord`, owned by
  `WorkspaceController`, and a second copy inside a widget would diverge.

`lib/core` and `lib/app` import no widgets from `lib/ui`. `lib/ui` imports the
layers below it, never the reverse. `flutter analyze` does not enforce that
today — it is a convention with a `grep` behind it — and keeping it that way is
[TODO-007](../TODOS.md)'s neighbour rather than a tooling project.

## Component map

```text
                       lib/ui  (views, one per tool)
        menu · toc · editor · pdf · images · map  ─── shell (IndexedStack)
                    │                 │
                    │ reads/writes    │ transient state
                    ▼                 ▼
        lib/app/workspace_controller.dart     lib/sessions/{pdf,image,map}_session.dart
                    │  the single WorkspaceRecord          │
                    │                                     │
                    ▼                                     │
        lib/core/workspace/workspace_persistence.dart      │
          250 ms debounce → boot cache → durable file ◄────┘
                    │
                    ▼
        lib/core/workspace/workspace_store.dart
          temp file · flush · rename · 4 MiB cap
                    │
                    ▼
        <support>/native-workspace/workspace.json   (durable)
        <cache>/workspace.json                      (boot cache)

        lib/core/{geo,metrics,map,pdf}/  — pure functions and services
        lib/app/services.dart            — file pickers and text read/write
        lib/core/map/tile_source.dart    — the only HTTP client in the app
```

## Ownership

### The controller

[`lib/app/workspace_controller.dart`](../lib/app/workspace_controller.dart) is
the single owner of `WorkspaceRecord`: the outline and its drafts, the active
item, the editor buffer, and each tool's persisted session. It also carries
the operations that change more than one tool's view of that record — outline
CRUD, link attachment (`attachPdfPage`, `attachImages`, `attachLocation`),
place management, remembered paths, and the JSON export/import envelope.

Two rules keep it honest:

- **Every write funnels through `touch()`** (or an operation that calls it):
  the user-interaction latch first, then the debounced write, then
  `notifyListeners`. Hydration runs before any interaction, so a restore can
  never be overwritten by a state the user has already changed.
- **`notifyChanged()` is the non-interaction path**, for a session that
  changed shared state without a user gesture. It rebuilds without scheduling
  a save.

### The sessions

| Session | File | Owns |
| --- | --- | --- |
| `PdfSession` | [`lib/sessions/pdf_session.dart`](../lib/sessions/pdf_session.dart) | The open document, page count, render zoom, page image cache, extracted headings, TOC load |
| `ImageSession` | [`lib/sessions/image_session.dart`](../lib/sessions/image_session.dart) | Directory scan, folder groups, lightbox index, scan limits |
| `MapSession` | [`lib/sessions/map_session.dart`](../lib/sessions/map_session.dart) | Viewport, pin, fly requests, GeoJSON layers, locate, import parsers |

A session reads shared state from the controller and writes back through it,
so persistence still happens on one path. What a session keeps — a decoded
PDF, a list of scanned images, a decoded tile layer — never reaches disk.

### The core

| File | Responsibility |
| --- | --- |
| [`lib/core/workspace/workspace_models.dart`](../lib/core/workspace/workspace_models.dart) | The schema, the clamps, and `normalizeWorkspace` / `serializeWorkspace` — the only shape the file may take |
| [`lib/core/workspace/workspace_store.dart`](../lib/core/workspace/workspace_store.dart) | The durable file: temp write, flush, rename, 4 MiB cap checked *before* reading, result codes instead of exceptions |
| [`lib/core/workspace/workspace_persistence.dart`](../lib/core/workspace/workspace_persistence.dart) | The 250 ms debounce, the write order (cache first, durable second), the boot merge rules, and the report the status pill renders |
| [`lib/core/metrics/metrics_engine.dart`](../lib/core/metrics/metrics_engine.dart) | Welford's engine: count, sum, min, max, mean, population variance |
| [`lib/core/metrics/summarize_bridge.dart`](../lib/core/metrics/summarize_bridge.dart) | The request/response codec and the error vocabulary carried from `src/webview_bridge.c` |
| [`lib/core/map/projection.dart`](../lib/core/map/projection.dart) | Web-Mercator project/unproject, tile enumeration, zoom clamping, easing |
| [`lib/core/map/tile_source.dart`](../lib/core/map/tile_source.dart) | The only HTTP client: host, user agent, memory LRU, disk cache |
| [`lib/core/pdf/pdf_outline.dart`](../lib/core/pdf/pdf_outline.dart) | Best-effort PDF outline parser (`/Outlines`, `/ObjStm`, page-tree walk) |
| [`lib/core/pdf/outline_pdf_writer.dart`](../lib/core/pdf/outline_pdf_writer.dart) | The outline-to-PDF renderer, ported from `src/outline_pdf.c` |
| [`lib/core/geo/geo.dart`](../lib/core/geo/geo.dart) | Distance, bearing, compass points, formatting |
| [`lib/app/services.dart`](../lib/app/services.dart) | `FileService`: open/save/directory pickers and the 8 MiB text read guard |
| [`lib/app/theme.dart`](../lib/app/theme.dart) | The design tokens ported from `styles/tokens.css` |

### The workspace store and the merge

The store writes `<support>/native-workspace/workspace.json` by writing a
temporary file, flushing it, and renaming it — a completed write never leaves
a half-written workspace behind. It enforces the 4 MiB cap in both
directions, and the read path checks the file's length **before** allocating.

There is no `fsync` of the file or its parent directory, which is what the C
original guarantees. Either strengthen it or state it — [TODO-009](../TODOS.md).

The merge on boot is one comparison, and both of its inputs come from disk:

```dart
final boot = readBootCache(bridge);          // <cache>/workspace.json
final controller = WorkspaceController(boot: boot);
startPersistence(boot: boot, controller: controller, bridge: bridge);
// inside: hydrate(boot) → native wins unless native.savedAt < boot.savedAt
```

Passing `controller.snapshot()` here instead of `boot` stamps the boot side
with the current time, so the durable copy always loses and a restart restores
nothing while every merge-rule test still passes. That was a real defect, and
`test/boot_composition_test.dart` now fails against it — see
[TODO-001](../TODOS.md).

### The views

| View | File | Reads |
| --- | --- | --- |
| Launcher | `lib/ui/menu_view.dart` | Controller badges plus each session's badge |
| TOC Manager | `lib/ui/toc_view.dart` | Controller outline, all three sessions for cross-links |
| Text Editor | `lib/ui/editor_view.dart` | Controller draft, active item, status |
| PDF Reader | `lib/ui/pdf_view.dart` | `PdfSession`, controller page/zoom/link target |
| Image Viewer | `lib/ui/images_view.dart` | `ImageSession`, controller link target |
| Map Explorer | `lib/ui/map_view.dart` | `MapSession`, controller places/filter/renderer, `TileCache` |
| Shell | `lib/ui/shell.dart` | `IndexedStack` over the six, status bar beneath |
| Widgets | `lib/ui/widgets.dart` | The shared toolbar/status/eyebrow vocabulary |

Full detail, including what each tool does and how they reference each other,
is in [the tools guide](tools.md).

## Runtime sequence

1. `main()` resolves the cache and support directories through
   `path_provider`.
2. `readBootCache` reads the boot cache — a damaged file degrades to an empty
   workspace rather than an exception.
3. `WorkspaceController` is constructed from that record; the shell renders
   the recorded view.
4. `startPersistence` builds the engine and hydrates: the durable copy wins
   unless it is strictly older than the boot cache.
5. The sessions are constructed and the app is handed to `runApp`.
6. A gesture — declaring a section, opening a PDF, dropping a pin — goes
   through a view to a session or the controller.
7. The controller latches the interaction, schedules a write, and notifies.
8. 250 ms later `persist()` writes the boot cache synchronously, then the
   durable file when its payload changed.
9. A failure sets the report the status pill renders as
   `Workspace not saved: …` or `Saved workspace not restored: …`.

## The extension rule

For a new capability:

1. Put the domain logic and its tests in `lib/core`.
2. Give it a session in `lib/sessions` only if it carries state that does not
   reach disk.
3. Add operations to `WorkspaceController` only if they change the shared
   record — and let `touch()` do the saving.
4. Let the view render and collect input; it should not decide anything.
5. Test the core first, then the boundary, then the view.

Do not put validation in a widget to avoid adding a core function; that is the
one direction the layers are not allowed to lean.
