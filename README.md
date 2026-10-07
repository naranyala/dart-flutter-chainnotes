# chainnotes

A Flutter port of the desktop workspace in `../webview-app-with-clua`: six tools
over one persisted record, written in pure Dart with no C, no Lua, and no
WebView.

| Tool | What it is for |
| --- | --- |
| **Menu** | Launcher cards with live badges. |
| **TOC Manager** | The outline. Declare sections, import headings from a PDF, reorder, undo, export/import JSON, combine to a PDF. |
| **Text Editor** | A draft bound to a selected section. Autosaved per keystroke. |
| **PDF Reader** | Paged reader with a heading sidebar, remembered session, and attach-page links. |
| **Image Viewer** | Folder-grouped thumbnail grid with a full-screen lightbox. |
| **Map Explorer** | OpenStreetMap tiles, colour filters, saved places, GeoJSON layers, distance and bearing, locate. |

The Google Maps viewer was not ported (it depends on an unlicensed tile
endpoint); the record keeps the `googleMap` section so a workspace exported from
the original still normalizes cleanly.

## Quick start

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

`flutter analyze` must be clean and `flutter test` must pass — currently
**67 tests across seven suites**. Verified on 2026-10-07 against Flutter 3.47.5
(stable), Dart 3.13.4: analyze clean, 67/67 tests, `flutter build linux --debug`
succeeds. Full command list, prerequisites, and output paths are in
[`docs/development.md`](docs/development.md).

## Documents

Start at [`docs/README.md`](docs/README.md).

| Document | What it is |
| --- | --- |
| [`docs/overview.md`](docs/overview.md) | Why the project exists, what it does, what it deliberately does not |
| [`docs/architecture.md`](docs/architecture.md) | Which layer owns what, and what happens between launch and first paint |
| [`docs/tools.md`](docs/tools.md) | The six tools, the session behind each, and how they reference each other |
| [`docs/bridge-protocol.md`](docs/bridge-protocol.md) | The surviving metrics contract and what replaced the WebView bindings |
| [`docs/development.md`](docs/development.md) | Prerequisites, commands, output paths, troubleshooting |
| [`docs/testing.md`](docs/testing.md) | Every suite, what each proves, what is not tested |
| [`docs/map-sources.md`](docs/map-sources.md) | Tile host, user agent, caching, attribution, licensing position |
| [`PYRAMID-OF-INTENTS.md`](./PYRAMID-OF-INTENTS.md) | Why the project exists, the intents implementation must serve, and a verified snapshot of what holds today and what does not |
| [`TODOS.md`](./TODOS.md) | The backlog. Every item names the intent it serves, its priority, and a definition of done |

## Architecture

```
lib/core/          pure Dart, no Flutter widgets — portable and unit-tested
  geo/             distance, bearing, formatting
  metrics/         Welford metrics engine + the bridge envelope codec
  map/             slippy-map projection, tile fetch/cache
  pdf/             best-effort PDF outline parser, outline-to-PDF writer
  workspace/       schema + normalizer, 4 MiB atomic store, persistence rules
lib/app/           WorkspaceController (shared record), theme, file pickers
lib/sessions/      per-tool transient state (pdf, images, map)
lib/ui/            the six views, shared widgets, shell, status bar
lib/main.dart      composition root: boot cache → hydrate → sessions → shell
```

* **One record.** `WorkspaceController` owns the outline, editor draft, and each
  tool's persisted session; sessions hold what never reaches disk.
* **Durability.** The boot cache is `…/cache/chainnotes/workspace.json`; the
  durable copy is `…/share/chainnotes/native-workspace/workspace.json`
  (`getApplicationCacheDirectory` / `getApplicationSupportDirectory`). Writes are
  debounced 250 ms, cache first then durable, through a temp file + rename with a
  4 MiB cap. The durable copy wins on boot unless it is strictly older than the
  boot cache.
* **Bridge contract.** `lib/core/metrics/summarize_bridge.dart` keeps the
  original request envelope (`[[number, …]]`, comma or newline separators) and
  error codes (`INVALID_REQUEST`, `EMPTY_INPUT`, `INVALID_VALUE`,
  `ENGINE_FAILED`, `BUFFER_TOO_SMALL`, `OUT_OF_MEMORY`).
* **All six stay mounted** in an `IndexedStack`, so scroll position, rendered
  PDF pages, and the map canvas survive a tool switch.
* **A restart restores the record** — last view, outline, drafts, and each
  tool's recorded session. It does not reopen the document itself; the PDF and
  the image folder are offered from their remembered lists ([TODO-016](./TODOS.md)).

---

## Repository map

Every source file, grouped by layer. A map that lists only the interesting
files cannot answer "where does X live", which is the only reason to have one.
[`test/readme_test.dart`](test/readme_test.dart) checks this list against the
filesystem in both directions: a new module that is not listed fails the suite,
and a listed file that has been deleted fails it too.

```text
--- application ---------------------------------------------------
lib/main.dart                 Composition root: directories, boot cache,
                              persistence wiring, WorkspaceApp, status bar
lib/app/workspace_controller.dart  The single shared WorkspaceRecord: outline
                              CRUD, links, editor buffer, touch()/notifyChanged()
lib/app/services.dart         FileService: open/save/directory pickers, text I/O
lib/app/theme.dart            Design tokens ported from styles/tokens.css

--- core: widget-free ------------------------------------------------
lib/core/geo/geo.dart         Great-circle distance, bearing, compass points
lib/core/metrics/metrics_engine.dart  Welford engine, population variance
lib/core/metrics/summarize_bridge.dart  Request parser, success payload,
                              error vocabulary and envelope
lib/core/map/projection.dart  Web-Mercator project/unproject, zoom clamping
lib/core/map/tile_source.dart TileCache: host, user agent, memory LRU, disk cache
lib/core/pdf/pdf_outline.dart Best-effort /Outlines parser (ObjStm, page tree)
lib/core/pdf/outline_pdf_writer.dart  Outline-to-PDF renderer (ported C)
lib/core/workspace/workspace_models.dart  Schema, clamps, normalize/serialize
lib/core/workspace/workspace_store.dart   Atomic durable file, 4 MiB cap, codes
lib/core/workspace/workspace_persistence.dart  Debounce, write order, merge,
                              save modes, persistence report

--- sessions: per-tool transient state -------------------------------
lib/sessions/pdf_session.dart    Open document, page count, zoom, page cache
lib/sessions/image_session.dart  Directory scan, folder groups, lightbox
lib/sessions/map_session.dart    Viewport, pin, layers, locate, import parsers

--- ui: views ---------------------------------------------------------
lib/ui/shell.dart             IndexedStack over the six views + status bar
lib/ui/menu_view.dart         Launcher cards with live badges
lib/ui/toc_view.dart          Outline spine, links, JSON/PDF transfers
lib/ui/editor_view.dart       Draft bound to the selected outline item
lib/ui/pdf_view.dart          Paged reader, headings sidebar, attach page
lib/ui/images_view.dart       Folder groups, thumbnail grid, lightbox
lib/ui/map_view.dart          Tile canvas, filters, grid, places, layers
lib/ui/widgets.dart           Shared toolbar/status/eyebrow vocabulary

--- tests ---------------------------------------------------------------
test/workspace_test.dart          Schema normalization, clamps, helpers (14)
test/persistence_test.dart        Debounce, write order, merge, save modes (13)
test/workspace_store_test.dart    Atomic store, size cap, result codes (13)
test/boot_composition_test.dart   The composition root wiring (3)
test/metrics_test.dart            Engine precision and rejected values (12)
test/bridge_test.dart             Protocol parser, envelope, codes (11)
test/app_smoke_test.dart          Mounts the shell, walks all six views (1)
test/readme_test.dart             Keeps this map, the docs index, and the
                                  README's commands in step with the tree

--- documentation -------------------------------------------------------
docs/README.md                 Documentation index and the honesty guard
docs/overview.md               Purpose, scope, current state, known gaps
docs/architecture.md           Layering rule, ownership, runtime sequence
docs/tools.md                  The six tools in detail
docs/bridge-protocol.md        The metrics contract and the binding replacement
docs/development.md            Prerequisites, commands, troubleshooting
docs/testing.md                Suites, coverage, and what is not tested
docs/map-sources.md            Tile host, caching, policy position
PYRAMID-OF-INTENTS.md          The constraints a change must respect
TODOS.md                       The backlog, every item linked to an intent
```

## Known gaps

The honest list, with owners in [`TODOS.md`](./TODOS.md):

* Nothing flushes on window close, so typing inside the 250 ms debounce window
  can be lost ([TODO-003](./TODOS.md)).
* The save label reports writes this session, so it reads `not saved` right
  after a successful restore ([TODO-004](./TODOS.md)).
* No CI, no interaction tests beyond the shell smoke test, and the built binary
  has never been launched on a display ([TODO-005](./TODOS.md),
  [TODO-006](./TODOS.md), [TODO-007](./TODOS.md)).
* The tile client has no rate limit and no disk-cache cap
  ([TODO-008](./TODOS.md)).
* The store does not `fsync` before renaming ([TODO-009](./TODOS.md)).
* The metrics engine and bridge codec have no production UI caller
  ([TODO-011](./TODOS.md)).

## Notes

* Map tiles come from OpenStreetMap with a declared user agent, cached in
  memory (512 tiles) and on disk (`lib/core/map/tile_source.dart`); see
  [`docs/map-sources.md`](docs/map-sources.md) for the attribution and policy
  position.
* Android/iOS declare `INTERNET` and the location permissions the Locate action
  needs; iOS explains location use in `Info.plist`.
* The PDF reader renders with `pdfx`; the document outline is parsed by a
  custom best-effort parser (`lib/core/pdf/pdf_outline.dart`) because `pdfx`
  exposes no outline API, and it fails soft with a readable message.
