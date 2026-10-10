# Pyramid of Intents

This document defines why the Flutter project exists, what it must enable, and
the constraints that should guide implementation decisions. `TODOS.md` is the
execution backlog; every backlog item must reference an intent ID from this
document.

The project is a port of the desktop workspace in `../webview-app-with-clua`
(C + Lua + Vue in a WebView) to pure Dart and Flutter. The port changes the
technology, not the product: six tools over one persisted record.

## How to use this pyramid

- Keep the intent IDs stable. Add a new intent instead of silently changing
  the meaning of an existing one.
- When proposing work, identify the highest-level intent it serves.
- A TODO is valid only when it has an `Intent:` reference and a verifiable
  outcome.
- If a task conflicts with a higher-level intent, resolve the conflict here
  before implementing it.

## I0 — North-star intent

### I0.1 — Ship a pure-Dart desktop workspace that is easy to run, read, and extend

Provide a small Flutter application in which the correctness-critical logic —
schema normalization, validation, the atomic store, the persistence merge, the
projection math, the metrics engine — lives in a widget-free `lib/core` with
tests, while the views stay thin and a contributor can understand the data flow
from one composition root.

**Success looks like:** a contributor can run `flutter analyze`,
`flutter test`, and `flutter build linux --debug` on a clean checkout, open
`lib/main.dart`, and follow a keystroke from a view to the shared record to the
debounced write without crossing a layering rule to do it.

## I1 — Product intents

### I1.1 — Six tools over one persisted record

Menu, TOC Manager, Text Editor, PDF Reader, Image Viewer, and Map Explorer are
not isolated screens. One record owns the outline and its drafts, the last view,
each tool's persisted session, and the cross-tool links (an outline item
pointing at a PDF page, an attached image, or a saved place).

The **Google Maps viewer has no view, by decision.** The `googleMap` section of
the record is normalized and persisted purely so a workspace exported elsewhere
loads without losing data. Building a viewer was rejected: the only known tile
source for it is an unlicensed endpoint. This is a closed decision, not an
oversight (TODO-013 closed).

**Success looks like:** a contributor can point at one store that owns the
cross-tool state, and a user moves from outline to source document and back
without re-declaring or re-losing anything.

### I1.2 — Keep the core/UI boundary explicit

Anything that decides whether input is valid, how state is clamped, what
survives a restart, or how a coordinate becomes a pixel belongs in `lib/core` or
`lib/app`, not in a widget. A view that parses a file itself, invents a
serialization format, or reaches past a session for shared state has crossed
this boundary without saying so.

### I1.3 — Durability a user can rely on

The workspace is written through one path: a 250 ms debounce, a synchronous
boot-cache write first and the durable file second, temp file + rename, a 4 MiB
cap checked before reading, and a merge on boot in which the durable copy wins
unless it is strictly older than the boot cache. A pending debounce is flushed
— not dropped — when the app hides, pauses, detaches, or disposes
(`AppLifecycleListener` → `flushNow()`, and `dispose()` flushes instead of
cancelling). A successful boot restore sets the save mode to `native`, so the
footer reads `saved to disk` rather than `not saved`.

Power-loss limit, stated not implied: the file is flushed but NOT fsynced
before the rename, and the parent directory is NOT fsynced after it
(`dart:io` exposes neither). Crash-during-write is safe (old or new file,
never half-written); power loss in the rename window may still lose the last
write.

**Success looks like:** type a sentence, close the window, reopen, and the
sentence is there; corrupt either file and the app still starts with a readable
explanation instead of an empty crash.

### I1.4 — Keep the portable core from the original

The Welford metrics engine, the bridge envelope (`[[number, …]]`, comma or
newline separators), and the error-code vocabulary (`INVALID_REQUEST`,
`EMPTY_INPUT`, `INVALID_VALUE`, `ENGINE_FAILED`, `BUFFER_TOO_SMALL`,
`OUT_OF_MEMORY`) are tested library code with **no production UI caller, by
decision** (TODO-011 closed). The README states this plainly so no reader
mistakes the engine for a product feature.

### I1.5 — Approachable as a starter

Favor clear code paths, a short dependency list, reproducible commands, and
documentation that matches the code that actually runs.

### I1.6 — Map Explorer whose network access is one seam

Raster tiles come from OpenStreetMap behind `lib/core/map/tile_source.dart`
(`TileCache`) with a declared user agent, an explicit host list
(`TileCache.tileHosts`), a 512-tile memory LRU, and a disk cache capped at
2000 files / 64 MiB with oldest-first eviction; at most 4 concurrent fetches
with ≥100 ms spacing and exponential backoff on 429/5xx
(`lib/core/map/tile_policy.dart`, `TileRequestGate`). Location comes from
`geolocator` behind the platform permission entries (Android, iOS, and macOS
all declare theirs); GeoJSON and place imports are parsed in core. The host,
rate behavior, and cache bounds stay visible in these two files rather than
spreading through the views.

Scope, decided: one basemap with a colour filter (no switcher) and no place
search — a geocoder would be a second network client behind a new seam
(TODO-014 closed; the README states it).

**Success looks like:** a user pans, bookmarks, locates, and reloads with the
bookmarks and last position intact, with attribution on screen and the tile
behaviour documented.

## I2 — User intents

### I2.1 — A user does not lose work when switching tools or restarting

Every tool stays mounted, so scroll position, rendered PDF pages, and the map
canvas survive a switch; the outline, drafts, and session context survive a
restart.

### I2.2 — A user receives useful feedback for invalid input

A missing title, an unreadable file, an unsupported outline export, a denied
location permission, or a corrupt workspace must produce a clear, actionable
sentence in that tool's status line rather than silence or an exception.

### I2.3 — A user can trust the displayed state

Save mode, status lines, word counts, badges, and the report pill must reflect
what actually happened. A label that claims work was not saved when it was, or
that a document is open when it is not, is a defect even if nothing crashes.

### I2.4 — A developer can run and extend the project quickly

The README, the analysis options, the test suites, and the build commands
should agree on the supported workflow.

## I3 — System intents

### I3.1 — One record owns shared state; sessions own transient state

`WorkspaceController` holds what reaches disk; `PdfSession`, `ImageSession`,
and `MapSession` hold what does not. A piece of state that both need must have
one owner and one write path.

### I3.2 — Failures are bounded and observable

The normalizer clamps corrupt input to safe defaults, the store returns a
result code instead of throwing, hydration records a report the pill can show,
and no failure path leaves a half-written workspace.

### I3.3 — Platform affordances are declared

Storage directories, file pickers, tile network access, and location
permissions are stated in `pubspec.yaml`, `AndroidManifest.xml`, and
`Info.plist` where the platform requires it, rather than assumed at runtime.

### I3.4 — File and network access sit behind small seams

`FileService`, `TileCache`, `WorkspaceStore`, and `geolocator` are the only
places that touch the outside world, so they can be swapped, faked, or bounded
in one edit.

## I4 — Quality and evolution intents

### I4.1 — Test behavior at each boundary

The metrics engine, the bridge codec, the atomic store, the merge rules, the
boot composition, and the view tree have proportionate automated verification.

### I4.2 — Prefer numerically sound statistics

The metrics implementation keeps Welford's algorithm so variance stays correct
for inputs whose sum would lose precision, and formatting stays stable.

### I4.3 — Make toolchain and platform assumptions explicit

Flutter and Dart versions, the platforms that are actually built, and the
network requirements of a first run should be documented and checked.

### I4.4 — Keep the architecture replaceable at the seams

The PDF backend, the tile cache, the file pickers, and the sessions should be
changeable independently behind small contracts.

## Current state snapshot

Verified against the tree and a full run on 2026-10-08 — `flutter analyze`
(no issues), `flutter test` (164/164: 156 functional + 8 docs guard),
`flutter build linux --debug`, `flutter build linux --release`,
`flutter build web --release`, `tool/smoke.sh --build --timeout=10`
(Smoke OK, exit 124 = stayed up) — rather than against these entries. Every
claim below was checked by running it.

Already present and working:

- Six tools in an animated stack (200 ms crossfade + slide) with a shared
  status bar, all built from one composition root in `lib/main.dart` —
  **I1.1**, **I2.1**.
- Pure-Dart core: schema + normalizer, 4 MiB atomic store, debounce/merge
  persistence with dispose-flush and post-hydrate `native` mode, Welford
  metrics, bridge envelope codec, Web-Mercator projection, bounded OSM tile
  fetch/cache with gate + eviction, best-effort PDF outline parser, and an
  outline-to-PDF writer — **I1.2**, **I4.2**.
- Boot wiring that compares two on-disk timestamps: `readBootCache` produces
  both the controller's initial state and the boot half of the merge, and
  `startPersistence` hydrates from it — **I1.3**. Locked by
  `test/boot_composition_test.dart`, which fails against the previous wiring.
- Lifecycle flush: `AppLifecycleListener` (pause/hide/detach) calls
  `flushNow()`, and `WorkspacePersistence.dispose()` flushes a pending
  debounce instead of cancelling it — **I1.3**, **I2.1**. Locked by the
  dispose-flush test in `test/persistence_test.dart` (TODO-003 closed).
- Post-hydrate save mode: a successful restore sets `native`, so the footer
  reads `saved to disk`; empty and damaged durable files leave `none` with
  (for damaged) an `INVALID_CONTENT` report — **I2.3**. Locked by three tests
  in `test/persistence_test.dart` (TODO-004 closed).
- Reopened sessions: `reopenRemembered` in `lib/main.dart` reopens the
  remembered PDF at its recorded page/zoom and the image folder at its
  recorded group; gone paths are forgotten with a sentence — **I2.1**.
  Locked by `test/boot_reopen_test.dart` (TODO-016 closed).
- 164 tests: metrics (12), bridge (11), store (14), normalizer (14),
  persistence merge + modes (17), boot composition (4), tile gate + eviction
  (9), tile cache (5), tool interactions (36), third-party seams (25),
  shell smoke (5), boot reopen (5), theme (1), docs guard (8) — **I4.1**.
- Third-party seams with fakes: `FakeFileService` picker flows (including
  cancellations), `LocationQuery` over `geolocator` (denied/disabled/forever/
  failing tested), `PdfOpener` over `pdfx` / `pdfrx` (per-platform gates,
  unsupported-platform refusal, and a real Linux open-and-render tested),
  `pdf`-package rendering and outline parsing headlessly — **I3.4**,
  **I4.1**. Audit finding: the unused `image` dependency was removed from
  `pubspec.yaml`.
- Map Explorer with pan/zoom, colour filters, grid, cursor readout, scale bar,
  saved places, GeoJSON layers, distance/bearing, locate, and a bounded tile
  cache (4 concurrent, 100 ms spacing, 429/5xx backoff, 2000 files / 64 MiB
  oldest-first) under `TileCache.tileHosts` with a named user agent —
  **I1.6** (TODO-008 closed).
- Explicit power-loss statement in code (`workspace_store.dart`) and README:
  flush but no fsync; crash-safe, power-loss may lose the last write —
  **I1.3**, **I4.3** (TODO-009 closed).
- CI workflow `.github/workflows/ci.yml` (analyze + test + Linux debug build
  on Flutter 3.47.5), green on `main` with a README badge; `tool/smoke.sh`
  builds and runs the real binary with isolated XDG dirs — **I4.1**,
  **I2.4** (TODO-005 and TODO-006 closed).
- Permission entries: `INTERNET` + coarse/fine location on Android,
  `NSLocationWhenInUseUsageDescription` on iOS and macOS — **I3.3**.
- Release accounting: Linux release bundle 33 M (25 M before PDFium),
  debug 126 M, web 41 M; launch to first frame ~3.5 s cold, ~3.2 s warm;
  Linux debug + release and web release build here; Windows/macOS/Android/iOS
  scaffolding unbuilt — **I4.3** (TODO-010 narrowed; TODO-015 closed).
- Decisions stated in the README: metrics/bridge are library code with no UI
  caller (TODO-011 closed), `googleMap` is import-compat only with no view
  (TODO-013 closed), one basemap + filter and no place search (TODO-014
  closed), seven `docs/` guides (TODO-012 closed).

Known gaps, in the order they should be closed:

- **Interaction coverage is core flows plus picker cancellations.** TOC
  import/export/combine and PDF-open cancel paths are tested; image-folder
  and map-file cancellations are not — **I4.1**. (TODO-007 closed.)
- **Unbuilt platforms.** Windows, macOS, Android, and iOS targets exist with
  plugin dependencies unverified there, and location has never been exercised
  on a device — **I4.3**. TODO-010.
- **Remembered documents are not reopened.** A restart restores the record
  (path, page, zoom, folder, viewport) but the PDF and the image folder must
  be picked again from their remembered lists — **I2.1**. TODO-016.
- **PDF pages render on Linux.** `pdfrx` (PDFium) renders where `pdfx` ships
  no backend; the `PdfOpener` seam picks per platform behind engine-neutral
  handles, and outline parsing stays pure Dart — **I4.4**, **I4.3**.
  (TODO-017 closed).

## Appendix — how the app is shaped: input → process → output

Every tool follows one pipeline: a gesture in the view, a decision in core
(or a session), a write through the single record, and a visible
confirmation. Nothing reaches disk except through `WorkspaceController`, and
nothing reaches the network or filesystem except through the four seams
(`FileService`, `TileCache`, `WorkspaceStore`, `geolocator`).

| Tool | Input (gesture) | Process (where the decision lives) | Output (record + visible feedback) |
| --- | --- | --- | --- |
| TOC Manager | Title + level → Add; move up/down; remove; filter text; JSON/heading imports | `WorkspaceController.addTocItem/moveTocItem/removeTocItem/undoTocRemoval` validate + clamp; `importTocJson/importPdfHeadings` accept or set the `That file is not an outline export.` sentence | `outline` items + `lastRemoved` persisted; status sentence + row order on screen |
| Text Editor | Keystroke in the bound buffer; Prev/Next; import/export draft | `setEditorContent` stores text, recomputes word count, `syncTocDraft` so outline and editor never disagree; `touch()` → 250 ms debounce → store | `editor` buffer + item draft persisted; `N words · <save mode>` + cursor position |
| PDF Reader | Choose file; page/zoom controls; Attach page | `PdfSession.openAt` decodes via the platform renderer (`pdfrx` on Linux, `pdfx` elsewhere), caches pages; `parsePdfOutline` extracts headings; `attachPdfPage` binds page to the linked outline item | `pdf` path/name/page/zoom/recents persisted and reopened on restart; page readout + sidebar + remembered list |
| Image Viewer | Choose directory; pick group; lightbox step (chevrons, keys, swipe); attach to section | `ImageSession.openAt` scans (500-file, depth, size caps) and groups; `stepLightbox` wraps; `attachImages` binds paths to the linked item | `images` path/groups/recents persisted and reopened on restart; grid + lightbox + `N images` badge |
| Map Explorer | Drag/zoom; long-press pin; Save pin/centre; Prev/Next stepping; go-to-coordinates; rename; GeoJSON load; Locate; Attach location | `MapSession` viewport math via `projection.dart`; `parsePlacesFile` validates CSV/GeoJSON (200-place cap); `TileRequestGate` admits or sheds load; `attachLocation` binds pin to the linked item; Clear-alls ask first | `map` places/filter/layers persisted; pin, readout (`045° NE · 1.2 km`), attribution on screen |
| Menu | Tap a card (ripple on touch) | Reads badges from the controller + sessions; `selectView` crossfades the animated stack | `view` persisted so restart reopens the same tool; live badges |

Global flows:

```text
boot:    main() → directories → readBootCache → WorkspaceController(boot)
         → startPersistence → hydrate (durable wins unless strictly older)
         → sessions → reopenRemembered (PDF at page/zoom, folder at group)
         → runApp → shell shows recorded view
         output: mode=native + `saved to disk` when restored, else none

keystroke: view → controller.setX → touch() → schedule()
           → 250 ms → persist(): cache first, durable second (temp+rename)
           → mode + report → status bar

shutdown: hide/pause/detach → flushNow(); dispose() flushes pending
          output: last sentence survives a window close

metrics (library only): `[[1,2,3]]` → parser (comma/newline, signs, exponents)
          → Welford engine → {count,sum,min,max,mean,variance} or
          {error:{code,message}} — no view calls it, by decision
```

**One thing this snapshot exists to prevent.** During the port the obvious
statement "a restart restores where you were" was written before the wiring
that makes it true existed: `hydrate` had been passed a record stamped with the
current time, so the durable copy was always "older" and was always skipped.
A document that describes intent can be aspirational; a document labelled
*current state* cannot, and it is the label that makes people stop checking.
