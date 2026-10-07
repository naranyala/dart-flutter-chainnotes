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

The **Google Maps viewer is deliberately not ported.** Its section of the record
is kept so a workspace exported from the original still normalizes cleanly, and
whether to build it is an open product decision, not an oversight.

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
unless it is strictly older than the boot cache. State must also be flushed when
the app stops, not only when a timer happens to fire.

**Success looks like:** type a sentence, close the window, reopen, and the
sentence is there; corrupt either file and the app still starts with a readable
explanation instead of an empty crash.

### I1.4 — Keep the portable core from the original

The Welford metrics engine, the bridge envelope (`[[number, …]]`, comma or
newline separators), and the error-code vocabulary (`INVALID_REQUEST`,
`EMPTY_INPUT`, `INVALID_VALUE`, `ENGINE_FAILED`, `BUFFER_TOO_SMALL`,
`OUT_OF_MEMORY`) are ported as tested library code. This project ships no UI
for them; that is a scope statement to be made deliberately, not discovered.

### I1.5 — Approachable as a starter

Favor clear code paths, a short dependency list, reproducible commands, and
documentation that matches the code that actually runs.

### I1.6 — Map Explorer whose network access is one seam

Raster tiles come from OpenStreetMap behind `lib/core/map/tile_source.dart`
with a declared user agent, a memory LRU and a disk cache; location comes from
`geolocator` behind the platform permission entries; GeoJSON and place imports
are parsed in core. There is no page-side fetcher to fence off — the WebView
problem this intent was written against does not exist here — but the host,
rate behavior, and cache bounds must stay visible in one file rather than
spreading through the views.

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

Verified against the tree and a full run on 2026-10-07 — `flutter analyze`
(no issues), `flutter test` (67 tests), `flutter build linux --debug` — rather
than against these entries. Every claim below was checked by running it.

Already present and working:

- Six tools mounted in an `IndexedStack` with a shared status bar, all built
  from one composition root in `lib/main.dart` — **I1.1**, **I2.1**.
- Pure-Dart core: schema + normalizer, 4 MiB atomic store, debounce/merge
  persistence, Welford metrics, bridge envelope codec, Web-Mercator
  projection, OSM tile fetch/cache, best-effort PDF outline parser, and an
  outline-to-PDF writer — **I1.2**, **I4.2**.
- Boot wiring that compares two on-disk timestamps: `readBootCache` produces
  both the controller's initial state and the boot half of the merge, and
  `startPersistence` hydrates from it — **I1.3**. Locked by
  `test/boot_composition_test.dart`, which fails against the previous wiring.
- 67 tests across metrics, bridge, store, normalizer, persistence merge,
  boot composition, and a widget smoke test that mounts the shell and walks
  every view — **I4.1**.
- Map Explorer with pan/zoom, colour filters, grid, cursor readout, scale bar,
  saved places, GeoJSON layers, distance/bearing, locate, and a disk-backed
  tile cache under `https://tile.openstreetmap.org` with a named user agent —
  **I1.6**.
- Permission entries: `INTERNET` + coarse/fine location on Android,
  `NSLocationWhenInUseUsageDescription` on iOS — **I3.3**.
- README with the layout, the storage paths, and the commands that were run.

Known gaps, in the order they should be closed:

- **Nothing flushes when the app closes.** The engine only writes on a 250 ms
  debounce and in `dispose`, which a window close on desktop does not reliably
  reach, so the last keystrokes can be lost — **I1.3** is not held at exit.
  TODO-003.
- **The save label is wrong right after boot.** `mode` starts at `none`, so the
  footer reads "not saved" even when the durable file was just restored — the
  label describes "written this session" while the user reads "exists on disk".
  **I2.3**. TODO-004.
- **No CI and no run of the real binary.** The widget smoke test mounts the
  shell headlessly, but nothing has executed `build/linux/…/chainnotes` on a
  display; there is no workflow running analyze, test, or build — **I4.1**,
  **I2.4**. TODO-005, TODO-006.
- **View-level coverage is thin.** Declaring and reordering a section,
  attaching a PDF page, saving a place, and stepping the lightbox have no
  interaction tests; only the shell smoke test exercises the views — **I4.1**.
  TODO-007.
- **The tile client has no bounds beyond memory.** One hardcoded host, no rate
  limit or backoff, no disk-cache size cap or eviction — **I1.6**. TODO-008.
- **The store is weaker than the C original.** Writes flush the temp file and
  rename, but there is no `fsync` of the file before the rename nor of the
  directory after it, so a power loss can still lose the last write — the
  guarantee should be strengthened or stated — **I1.3**, **I4.3**. TODO-009.
- **Only Linux debug is built.** Windows, macOS, Android, and iOS have never
  been built here, and the location entries have never been exercised on a
  device — **I4.3**. TODO-010.
- **The metrics core has no production surface.** The engine and codec are
  tested library code with no UI caller; that is acceptable only as a decision
  — **I1.4**. TODO-011.
- **`docs/` was not ported.** The bridge protocol, architecture, and testing
  notes from the original live only in its tree; this project has a README and
  the two documents — **I1.5**. TODO-012.

**One thing this snapshot exists to prevent.** During the port the obvious
statement "a restart restores where you were" was written before the wiring
that makes it true existed: `hydrate` had been passed a record stamped with the
current time, so the durable copy was always "older" and was always skipped.
A document that describes intent can be aspirational; a document labelled
*current state* cannot, and it is the label that makes people stop checking.
