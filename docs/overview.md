# Project overview

## Purpose

This repository is a **Flutter port of the desktop workspace** from
`../webview-app-with-clua` — a C + Lua + Vue application that ran its UI inside
a WebView. The port answers a narrower question than the original did:

> Can the same six-tool workspace, the same persisted record, and the same
> correctness-critical core be delivered in pure Dart, with no C, no Lua, and
> no WebView, without losing the properties that made the original worth
> copying?

Three things carried over unchanged in spirit:

1. **A widget-free core** (`lib/core`) owns schema normalization, validation,
   serialization, the atomic store, the persistence merge, the projection
   math, and the metrics engine — with tests.
2. **Sessions** (`lib/sessions`) own each tool's transient state.
3. **Views** (`lib/ui`) own input and presentation, and reach shared state
   only through `WorkspaceController`.

The sample capability is a batch metrics engine: it accepts finite `double`
values and returns count, sum, minimum, maximum, arithmetic mean, and
population variance (`M2 / count`, not the sample variance), computed with
Welford's algorithm so the running mean and second moment never depend on a
running sum that has already lost its low-order bits.

## The shape of the claim

Two properties make this a port rather than a rewrite:

**The boundary is checkable, not aspirational.** No view opens a file, calls a
platform channel, or performs a network request directly. Pickers go through
`FileService`, tiles through `TileCache`, location through `geolocator` behind
`MapSession`, and persistence through `WorkspacePersistence`. You can verify
that with `grep` over `lib/ui`.

**Durability is the core's job, not the framework's.** Workspace state is
written to a file, debounced and atomically renamed. There is no
`SharedPreferences`, no `shared_preferences` plugin, and no platform store in
the path — one JSON file under the application support directory, and one
JSON file under the cache directory as the synchronous boot copy.

## The user experience

The desktop UI opens on a menu of six tools over one shared record.

The writing flow starts in **TOC Manager**, where a reader declares outline
items (title plus level). Selecting an item opens the **Text Editor** bound to
that heading: the draft is restored, saved on every keystroke, and the top bar
moves between neighbouring items. Items link outward — to a **PDF Reader**
page, to images in the **Image Viewer**, to a saved place on the **Map
Explorer**.

All six tools read and write one record, so the menu badges show live state
and a restart restores the last view, the outline, the open drafts, and each
tool's recorded session (which document was open, at which page and zoom,
which folder was selected, where the map was).

What a restart does *not* do is reopen the document itself: the PDF and the
image folder are offered from their remembered lists, not auto-loaded. That
is stated rather than implied — see [TODO-016](../TODOS.md).

### The map tool

**Map Explorer** is a hand-written OpenStreetMap tile canvas — no mapping
library. Pan and zoom over committed integer zoom levels, a colour filter and
a grid over one basemap, saved places with distance and bearing, GeoJSON
layers, and locate. Tiles are fetched by `lib/core/map/tile_source.dart`, a
seam that owns the host, the user agent, a 512-tile memory LRU, and a disk
cache — see [the map sources guide](map-sources.md).

**Google Maps is not ported.** Its section of the record still normalizes and
persists so a workspace exported from the original loads cleanly, but there is
no view for it. The original's viewer fetched from an unlicensed Google
endpoint; whether to build that here is an open decision, not an omission.

## What this project is not

It is not an analytics product, and the metrics engine is not the point of the
interface.

- No accounts, no server, no plugin system, no local HTTP server.
- Workspace persistence is a local JSON file under the user's data directory.
- The metrics engine and the bridge codec **have no production UI caller**.
  They are portable library code carried from the original, tested in
  `test/metrics_test.dart` and `test/bridge_test.dart`. That is a scope
  decision rather than an accident, and it is recorded in the intent pyramid
  (**I1.4**) and the backlog ([TODO-011](../TODOS.md)).

## Current state

Verified against the tree and a full run on 2026-10-07 — `flutter analyze`
clean, `flutter test` 114/114, `flutter build linux --debug`, `--release`,
and `flutter build web --release` succeed. The
authoritative version, with the reasoning behind each entry, is the
[current state snapshot](../PYRAMID-OF-INTENTS.md#current-state-snapshot) in
the intent pyramid.

Implemented and working:

- Six tools in one shell, all mounted at once so scroll position, rendered
  PDF pages, and the map canvas survive a switch.
- A widget-free core: normalizer, 4 MiB atomic store, debounce/merge
  persistence with lifecycle flush, Welford metrics, bridge codec,
  Web-Mercator projection, bounded tile fetch/cache, PDF outline parser,
  outline-to-PDF writer.
- 106 functional tests plus 8 docs-guard tests, including widget interaction
  suites and third-party seam tests that run without platform channels.

The gaps worth knowing before you build on it:

| Gap | Why it matters |
| --- | --- |
| PDF pages do not render on Linux | `pdfx` ships no Linux backend; opening reports `PDF rendering is not available on this platform.` Outline parsing still works everywhere. TODO-017 |
| No observed green CI run | The workflow exists but has never been seen green on GitHub. TODO-005 |
| Interaction coverage is core flows only | Picker cancel paths are thin; native PDF rendering is untestable on Linux. TODO-007 |
| Unbuilt platforms | Windows/macOS/Android/iOS targets exist but were not built here. TODO-010 |
| First-run latency unmeasured | The release bundle builds (25 M) but startup was never timed. TODO-015 |
| Last document and image folder are remembered, not reopened | A restart restores the record, not the open file. TODO-016 |

Follow-up work is tracked in [`TODOS.md`](../TODOS.md), and every item there is
linked to an intent in
[`PYRAMID-OF-INTENTS.md`](../PYRAMID-OF-INTENTS.md).
