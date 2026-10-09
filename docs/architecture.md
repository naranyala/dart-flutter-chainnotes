# Architecture and data flow

## The one rule

> **Views handle input and display. Core handles validation, state, and saving.**

Most decisions in this project come back to that line. In practice it means:

- A view doesn't parse files, decode JSON, or decide if input is valid — it
  asks a session or `WorkspaceController`.
- A view doesn't touch the network or the filesystem — only `FileService`,
  `TileCache`, and `WorkspaceStore` do.
- There's exactly one `WorkspaceRecord`, owned by `WorkspaceController`. A
  widget never keeps its own second copy, because the two would drift apart.

`lib/core` and `lib/app` don't import widgets from `lib/ui`. `lib/ui`
imports from the layers below, never the other way around.
`flutter analyze` doesn't enforce this — it's a convention you check with
`grep` — and keeping it that way matters more than adding tooling for it.

## How the pieces fit

```text
                       lib/ui  (one view per tool)
        menu · toc · editor · pdf · images · map  ─── shell (animated stack)
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

        lib/core/{geo,metrics,map,pdf}/  — plain functions and services
        lib/app/services.dart            — file pickers and text read/write
        lib/core/map/tile_source.dart    — the only HTTP client in the app
```

## Who owns what

### The controller

[`lib/app/workspace_controller.dart`](../lib/app/workspace_controller.dart)
owns the `WorkspaceRecord`: the outline and its drafts, the selected item,
the editor buffer, and each tool's saved session. It also has the operations
that touch more than one tool — outline edits, link attachments
(`attachPdfPage`, `attachImages`, `attachLocation`), places, remembered paths,
and JSON import/export.

Two habits keep it predictable:

- **Every user edit goes through `touch()`.** That latches the interaction,
  schedules the debounced save, then notifies listeners. Restoring from disk
  happens before any interaction, so a restore can't be overwritten by
  something you just typed.
- **`notifyChanged()` is for the quiet path**, when a session updates shared
  state without a user gesture. It rebuilds the UI without scheduling a save.

### Sessions

| Session | File | Keeps track of |
| --- | --- | --- |
| `PdfSession` | [`lib/sessions/pdf_session.dart`](../lib/sessions/pdf_session.dart) | Open document, page count, zoom, cached pages, headings, TOC load |
| `ImageSession` | [`lib/sessions/image_session.dart`](../lib/sessions/image_session.dart) | Folder scan, folder groups, lightbox position, scan limits |
| `MapSession` | [`lib/sessions/map_session.dart`](../lib/sessions/map_session.dart) | Map position, pin, fly requests, GeoJSON layers, locate, file parsing |

A session reads shared state from the controller and writes back through it,
so saving still happens in one place. What a session keeps for itself — a
decoded PDF, a list of scanned images, decoded tiles — never touches disk.

### Core

| File | What it does |
| --- | --- |
| [`lib/core/workspace/workspace_models.dart`](../lib/core/workspace/workspace_models.dart) | The file format, safe defaults, and `normalizeWorkspace` / `serializeWorkspace` |
| [`lib/core/workspace/workspace_store.dart`](../lib/core/workspace/workspace_store.dart) | Saving the durable file: temp write, flush, rename, 4 MiB limit checked *before* reading, result codes instead of exceptions |
| [`lib/core/workspace/workspace_persistence.dart`](../lib/core/workspace/workspace_persistence.dart) | The 250 ms debounce, the order (cache first, durable second), the boot merge, and the report shown in the status bar |
| [`lib/core/metrics/metrics_engine.dart`](../lib/core/metrics/metrics_engine.dart) | Welford's engine: count, sum, min, max, mean, population variance |
| [`lib/core/metrics/summarize_bridge.dart`](../lib/core/metrics/summarize_bridge.dart) | The request/response format and error codes |
| [`lib/core/map/projection.dart`](../lib/core/map/projection.dart) | Web-Mercator math, tile listing, zoom clamping, easing |
| [`lib/core/map/tile_source.dart`](../lib/core/map/tile_source.dart) | The only HTTP client: host, user agent, memory and disk cache |
| [`lib/core/pdf/pdf_outline.dart`](../lib/core/pdf/pdf_outline.dart) | Reads PDF outlines (`/Outlines`, object streams, page tree) as best it can |
| [`lib/core/pdf/outline_pdf_writer.dart`](../lib/core/pdf/outline_pdf_writer.dart) | Turns an outline back into a PDF |
| [`lib/core/geo/geo.dart`](../lib/core/geo/geo.dart) | Distance, bearing, compass points, formatting |
| [`lib/app/services.dart`](../lib/app/services.dart) | `FileService`: file open/save and folder pickers, with an 8 MiB guard on text reads |
| [`lib/app/theme.dart`](../lib/app/theme.dart) | The design tokens for the workspace theme |

### Saving and merging

The store writes `<support>/native-workspace/workspace.json` by writing a
temp file, flushing it, and renaming it over the old one — so a finished
write never leaves a half-written file behind. It enforces the 4 MiB limit
both ways, and checks the size on disk **before** allocating memory to read.

One honest limit: the file is flushed but not `fsync`ed, and neither is its
folder, which is weaker than the C original. That's documented rather than
hidden — [TODO-009](../TODOS.md).

Merging at boot is a single comparison, and both sides come from disk:

```dart
final boot = readBootCache(bridge);          // <cache>/workspace.json
final controller = WorkspaceController(boot: boot);
startPersistence(boot: boot, controller: controller, bridge: bridge);
// inside: hydrate(boot) → durable wins unless native.savedAt < boot.savedAt
```

It's easy to get this wrong by passing `controller.snapshot()` instead of
`boot` — that stamps the boot side with "right now", so the durable copy
always looks older and a restart restores nothing, while all the merge-rule
tests still pass. That actually happened once, and
`test/boot_composition_test.dart` now guards the wiring — see
[TODO-001](../TODOS.md).

### Views

| View | File | Shows |
| --- | --- | --- |
| Launcher | `lib/ui/menu_view.dart` | Badges from the controller and sessions |
| TOC Manager | `lib/ui/toc_view.dart` | Outline plus links from all three sessions |
| Text Editor | `lib/ui/editor_view.dart` | Draft, selected item, status |
| PDF Reader | `lib/ui/pdf_view.dart` | `PdfSession` plus saved page/zoom/link target |
| Image Viewer | `lib/ui/images_view.dart` | `ImageSession` plus link target |
| Map Explorer | `lib/ui/map_view.dart` | `MapSession` plus places, filter, and tiles |
| Shell | `lib/ui/shell.dart` | All six in an animated stack (crossfade + slide), status bar below |
| Widgets | `lib/ui/widgets.dart` | Shared toolbar, status, and eyebrow styles |

What each tool actually does is in [the tools guide](tools.md).

## From launch to typing

1. `main()` finds the cache and support folders via `path_provider`.
2. `readBootCache` reads the boot copy — a damaged file becomes an empty
   workspace, not a crash.
3. `WorkspaceController` starts from that record; the shell shows the saved
   view.
4. `startPersistence` hydrates: the durable copy wins unless it's strictly
   older than the boot copy.
5. Sessions are created and `runApp` takes over.
6. Anything you do — adding a heading, opening a PDF, dropping a pin — goes
   from a view to a session or the controller.
7. The controller notes the interaction, schedules a save, and notifies.
8. 250 ms later `persist()` writes the boot cache, then the durable file if
   it changed.
9. If something fails, the status bar shows `Workspace not saved: …` or
   `Saved workspace not restored: …`.

## Adding something new

If you're adding a capability:

1. Put the logic and its tests in `lib/core`.
2. Add a session in `lib/sessions` only if it needs state that doesn't get
   saved.
3. Add operations to `WorkspaceController` only if they change the shared
   record — and let `touch()` handle saving.
4. Let the view render and collect input; it shouldn't make decisions.
5. Test the core first, then the boundary, then the view.

Don't validate input in a widget just to avoid adding a core function. That's
the one direction the layers aren't allowed to lean.
