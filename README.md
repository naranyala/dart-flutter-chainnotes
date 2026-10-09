# chainnotes

**Chainnotes is a Flutter desktop workspace for outline-driven reading and
note-taking: six tools working over one shared, persisted record.**

All correctness-critical logic — schema
normalization, the atomic file store, persistence merge, map projection, and
the metrics engine — lives in a widget-free `lib/core` that is unit-tested,
while the Flutter views stay thin.

In daily use, you declare the structure of your work in the **TOC Manager**,
draft against each heading in the **Text Editor**, and link headings outward
to a page in the **PDF Reader**, a folder group in the **Image Viewer**, or a
saved place in the **Map Explorer**, all launched from a **Menu** with live
badges. Everything reads and writes a single `WorkspaceRecord` owned by
`WorkspaceController`, autosaved through a debounced, atomic JSON store, so
switching tools never loses scroll, page, or map state, and a restart restores
the last view, outline, drafts, and each tool's recorded session.

Chainnotes is built as a small, readable starter: one composition root in
`lib/main.dart`, explicit seams for files, tiles, and location, and docs that
match the code that actually runs.

| Tool | What it is for |
| --- | --- |
| **Menu** | Launcher cards with live badges. |
| **TOC Manager** | The outline. Declare sections, import headings from a PDF, reorder, undo, export/import JSON, combine to a PDF. |
| **Text Editor** | A draft bound to a selected section. Autosaved per keystroke. |
| **PDF Reader** | Paged reader with a heading sidebar, remembered session, and attach-page links. |
| **Image Viewer** | Folder-grouped thumbnail grid with a full-screen lightbox. |
| **Map Explorer** | OpenStreetMap tiles, colour filters, saved places with prev/next stepping, go-to-coordinates, pin/centre tools, GeoJSON layers, distance and bearing, locate. |

The file format also has a reserved `googleMap` section. It loads and saves
like everything else, but nothing displays it — so workspaces that contain it
still open fine.

## Quick start

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

`flutter analyze` should come back clean and `flutter test` should pass —
right now that's **116 feature tests across ten suites (124 total with the
docs guard)**.
Checked on 2026-10-08 with Flutter 3.47.5 (stable), Dart 3.13.4: analyze
clean, 124/124 tests, `flutter build linux --debug` works. For setup steps,
the full command list, and where builds land, see
[`docs/development.md`](docs/development.md).

## Documents

Start at [`docs/README.md`](docs/README.md) — it's the index.

| Document | What you'll find |
| --- | --- |
| [`docs/overview.md`](docs/overview.md) | What the project is, how it feels to use, and what it doesn't try to be |
| [`docs/architecture.md`](docs/architecture.md) | How the layers fit together, and what happens from launch to first paint |
| [`docs/tools.md`](docs/tools.md) | The six tools, what each one remembers, and how they link to each other |
| [`docs/bridge-protocol.md`](docs/bridge-protocol.md) | The metrics format and the Dart APIs behind each tool |
| [`docs/development.md`](docs/development.md) | Setup, commands, where builds land, and fixes for common problems |
| [`docs/testing.md`](docs/testing.md) | The test suites, what each one covers, and what isn't tested |
| [`docs/map-sources.md`](docs/map-sources.md) | Where tiles come from, how they're cached, and attribution |
| [`PYRAMID-OF-INTENTS.md`](./PYRAMID-OF-INTENTS.md) | The rules a change should respect, plus a checked snapshot of what works now and what doesn't |
| [`TODOS.md`](./TODOS.md) | What's left. Every item points at an intent and says what "done" means |

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

* **One shared record.** `WorkspaceController` holds the outline, the editor
  draft, and each tool's saved session; sessions only hold what doesn't need
  saving.
* **Saving that survives restarts.** The boot copy is
  `…/cache/chainnotes/workspace.json`; the durable copy is
  `…/share/chainnotes/native-workspace/workspace.json`
  (`getApplicationCacheDirectory` / `getApplicationSupportDirectory`). Edits
  wait 250 ms, write the cache first then the durable file, using a temp file
  plus rename with a 4 MiB limit. On boot the durable copy wins unless it's
  strictly older than the boot copy.
* **Metrics format.** `lib/core/metrics/summarize_bridge.dart` reads
  `[[number, …]]` (commas or newlines between values) and replies with either
  the stats or an error code (`INVALID_REQUEST`, `EMPTY_INPUT`,
  `INVALID_VALUE`, `ENGINE_FAILED`, `BUFFER_TOO_SMALL`, `OUT_OF_MEMORY`).
* **All six views stay mounted** in an animated stack, so scroll position, open
  PDF pages, and the map stay put when you switch. Switching plays a 200 ms
  crossfade with a short slide in the menu direction (jump cuts under reduced
  motion). Sidebars collapse to a top panel on narrow windows, and the system
  back button returns to the menu instead of leaving the app.
* **Restarting brings the record back** — last view, outline, drafts, and each
  tool's session. It doesn't reopen the files themselves; the PDF and image
  folder are picked again from their remembered lists ([TODO-016](./TODOS.md)).

---

## Repository map

Every source file, grouped by layer. A list of just the interesting files
can't answer "where does X live", so this lists everything.
[`test/readme_test.dart`](test/readme_test.dart) keeps it in sync both ways:
a new file that's not listed fails the tests, and a listed file that's gone
fails them too.

```text
--- application ---------------------------------------------------
lib/main.dart                 Composition root: directories, boot cache,
                              persistence wiring, WorkspaceApp, status bar
lib/app/workspace_controller.dart  The single shared WorkspaceRecord: outline
                              CRUD, links, editor buffer, touch()/notifyChanged()
lib/app/services.dart         FileService: open/save/directory pickers, text I/O
lib/app/location.dart         LocationQuery seam over geolocator (fakeable)
lib/app/theme.dart            Design tokens for the workspace theme

--- core: widget-free ------------------------------------------------
lib/core/geo/geo.dart         Great-circle distance, bearing, compass points
lib/core/metrics/metrics_engine.dart  Welford engine, population variance
lib/core/metrics/summarize_bridge.dart  Request parser, success payload,
                              error vocabulary and envelope
lib/core/map/projection.dart  Web-Mercator project/unproject, zoom clamping
lib/core/map/tile_source.dart TileCache: hosts, user agent, memory LRU, disk cache
lib/core/map/tile_policy.dart Request gate (concurrency, spacing, backoff),
                              disk eviction picker
lib/core/pdf/pdf_outline.dart Best-effort /Outlines parser (ObjStm, page tree)
lib/core/pdf/outline_pdf_writer.dart  Outline-to-PDF renderer
lib/core/workspace/workspace_models.dart  Schema, clamps, normalize/serialize
lib/core/workspace/workspace_store.dart   Atomic durable file, 4 MiB cap, codes
lib/core/workspace/workspace_persistence.dart  Debounce, write order, merge,
                              save modes, persistence report

--- sessions: per-tool transient state -------------------------------
lib/sessions/pdf_session.dart    Open document, page count, zoom, page cache
lib/sessions/pdf_backend.dart    PdfOpener seam: pdfx + pdfrx renderers,
                               picked per platform, over engine-neutral pages
lib/sessions/image_session.dart  Directory scan, folder groups, lightbox
lib/sessions/map_session.dart    Viewport, pin, layers, locate, import parsers

--- ui: views ---------------------------------------------------------
lib/ui/shell.dart             Animated stack over the six views + status bar
lib/ui/menu_view.dart         Launcher cards with live badges
lib/ui/toc_view.dart          Outline spine, links, JSON/PDF transfers
lib/ui/editor_view.dart       Draft bound to the selected outline item
lib/ui/pdf_view.dart          Paged reader, headings sidebar, attach page
lib/ui/images_view.dart       Folder groups, thumbnail grid, lightbox
lib/ui/map_view.dart          Tile canvas, filters, grid, places, layers
lib/ui/widgets.dart           Shared toolbar/status/eyebrow vocabulary

--- tests ---------------------------------------------------------------
test/workspace_test.dart          Schema normalization, clamps, helpers (14)
test/persistence_test.dart        Debounce, write order, merge, save modes (17)
test/workspace_store_test.dart    Atomic store, size cap, result codes (13)
test/boot_composition_test.dart   The composition root wiring (3)
test/metrics_test.dart            Engine precision and rejected values (12)
test/bridge_test.dart             Protocol parser, envelope, codes (11)
test/tile_policy_test.dart        Request gate, eviction, cache constants (9)
test/tools_interaction_test.dart  TOC, editor, links, places, map stepping, lightbox (19)
test/package_integration_test.dart  Pickers, locate, pdf seams, real pdfrx render (15)
test/app_smoke_test.dart          Shell, real footer, navbar width, menu button (3)
test/readme_test.dart             Keeps this map, the docs index, and the
                                  README's commands in step with the tree

--- documentation -------------------------------------------------------
docs/README.md                 Documentation index and the honesty guard
docs/overview.md               Purpose, scope, current state, known gaps
docs/architecture.md           Layering rule, ownership, runtime sequence
docs/tools.md                  The six tools in detail
docs/bridge-protocol.md        The metrics contract and the Dart surfaces
docs/development.md            Prerequisites, commands, troubleshooting
docs/testing.md                Suites, coverage, and what is not tested
docs/map-sources.md            Tile host, caching, policy position
PYRAMID-OF-INTENTS.md          The constraints a change must respect
TODOS.md                       The backlog, every item linked to an intent
```

## Known gaps

Things that aren't finished yet, each tracked in [`TODOS.md`](./TODOS.md):

* Closing the window inside the 250 ms save window can lose what you just
  typed ([TODO-003](./TODOS.md)).
* The save label counts saves made in this run, so it says `not saved` right
  after a restore until you type again ([TODO-004](./TODOS.md)).
* CI is set up as `.github/workflows/ci.yml` (analyze + test + Linux debug
  build) but hasn't been seen passing on GitHub yet ([TODO-005](./TODOS.md)).
* Tests cover the main flows: outline add/move/undo/filter, editor syncing,
  PDF attach, outline import/export, places, place stepping, go-to-coordinates,
  lightbox stepping (`test/tools_interaction_test.dart`). Picker-cancellation
  paths and some picker flows aren't covered ([TODO-007](./TODOS.md)).
* The release app builds but nobody timed first launch ([TODO-015](./TODOS.md)).
* The store flushes but doesn't `fsync` the file or its folder, so losing
  power can drop the last save even after `ok` ([TODO-009](./TODOS.md)).
  Crashing mid-write is safe (you get the old or the new file, never half of
  one).
* The metrics engine and bridge code have no button in the UI that calls them
  ([TODO-011](./TODOS.md)).

## Notes

* Map tiles come from OpenStreetMap with a real user agent, kept in memory
  (512 tiles) and on disk (2000 files / 64 MiB, oldest dropped first;
  `lib/core/map/tile_source.dart`, `lib/core/map/tile_policy.dart`). At most
  4 downloads at once, 100 ms apart, backing off on 429/5xx. Attribution and
  the full reasoning are in [`docs/map-sources.md`](docs/map-sources.md).
* Android and iOS list `INTERNET` and the location permissions that Locate
  needs; iOS and macOS explain location use in their `Info.plist` files.
* PDF pages render with `pdfx` on Android/iOS/macOS/Windows and with `pdfrx`
  (PDFium) on Linux, both through the `PdfOpener` seam
  (`lib/sessions/pdf_backend.dart`), which picks the renderer for the running
  platform. The outline parser (`lib/core/pdf/pdf_outline.dart`) is plain Dart
  and works everywhere, but `pdfx` exposes no outline API, so headings come
  from it and fall back to a readable message when they can't be read.
* Platforms: Linux is what gets tested (debug + release); Web release builds
  too. Windows, macOS, Android, and iOS folders exist but weren't built here.
  Sizes on 2026-10-07: `build/linux/x64/release/bundle` 25 M,
  `build/linux/x64/debug/bundle` 126 M, `build/web` 41 M.
* The metrics engine and bridge code are small libraries with no UI button;
  the `googleMap` section is kept so imports don't lose data, with no view;
  Map Explorer has one basemap with a tint and no place search (that would
  need a second network client).
