# Project overview

## What this is

Chainnotes is a small desktop workspace for working with outlines, drafts,
and source material in one place. You lay out your headings, write against
them, and tie each heading to the page, image, or map location it came from.

Under the hood it's split in a simple way:

1. **`lib/core` holds the parts that have to be right** — how the workspace
   file looks, how it gets validated and saved, how map coordinates become
   pixels, and the small metrics engine. No widgets in there, and everything
   has tests.
2. **`lib/sessions` remembers what's open right now** — the PDF page you're
   on, the image folder you're browsing, where the map is.
3. **`lib/ui` is just input and display** — it reads shared state through
   `WorkspaceController` and doesn't invent its own.

There's also a small batch metrics engine tucked into core: give it a list of
finite numbers and it returns count, sum, min, max, mean, and population
variance (`M2 / count`), using Welford's method so large values don't lose
precision along the way.

## How it's put together

Two ideas shape most of the code:

**Views don't touch the outside world directly.** If you search the views for
file access, network calls, or platform channels, you won't find any. Pickers
go through `FileService`, tiles go through `TileCache`, location goes through
`MapSession`, and saving goes through `WorkspacePersistence`. You can check
that with a quick `grep` over `lib/ui`.

**Saving is just files, not framework magic.** The workspace is one JSON file
under the app support directory, plus a boot copy under the cache directory
that the app can read synchronously at startup. Writes are debounced and done
with temp-file plus rename. No `SharedPreferences`, no platform store in the
middle.

## What it feels like to use

The app opens on a menu with six tools that all share one record.

Most work starts in the **TOC Manager**, where you add headings (a title plus
a level). Pick a heading and the **Text Editor** shows its draft — it saves as
you type, and you can step between neighbouring headings from the top bar.
Headings can point outward: to a page in the **PDF Reader**, to images in the
**Image Viewer**, or to a saved place in the **Map Explorer**.

Because everything shares one record, the menu badges stay up to date, and a
restart brings back your last view, your outline, your drafts, and each tool's
session — the open document at its page, the browsed folder at its group,
where the map was. A remembered file that is gone is forgotten with a
sentence saying so.

### The map

**Map Explorer** draws its own OpenStreetMap tiles — no mapping package. You
can pan and zoom over integer zoom levels, tint the basemap, overlay a grid,
save places, load GeoJSON layers, and use locate. Tile fetching lives in
`lib/core/map/tile_source.dart`, which owns the host, the user agent, and the
memory and disk caches — see [the map sources guide](map-sources.md).

**There's no Google Maps view.** That part of the record still loads and saves
so a workspace from elsewhere doesn't lose data, but nothing displays it.

## What this isn't

It's not an analytics product, and the metrics engine isn't the main event —
it's a small library carried along with the project, tested but not wired to
any button.

More concretely:

- No accounts, no server, no plugins, no local HTTP server.
- Saving is a local JSON file in your data directory.
- The metrics engine and bridge codec **aren't called by the UI**. That's on
  purpose, and it's noted in the intent pyramid (**I1.4**) and
  [TODO-011](../TODOS.md) so nobody mistakes it for a missing feature.

## Where things stand

Checked on 2026-10-08 — `flutter analyze` clean, `flutter test` 164/164,
`flutter build linux --debug`, `--release`, and `flutter build web --release`
all pass. The full story with reasons is in the
[current state snapshot](../PYRAMID-OF-INTENTS.md#current-state-snapshot).

What works:

- All six tools in one window, kept mounted so scroll position, open PDF
  pages, and the map survive switching.
- The core pieces: file format handling, the 4 MiB atomic store, debounced
  saving with a flush on hide/close, Welford metrics, the bridge format,
  map projection, bounded tile fetching, a PDF outline reader, and an
  outline-to-PDF writer.
- 125 feature tests plus 8 docs tests, including widget tests and fakes for
  pickers, location, and PDF opening that run without a device.

Things worth knowing before you build on it:

| Gap | What it means |
| --- | --- |
| Tests cover the main flows | Image-folder and map-file picker cancellations aren't covered |
| Some platforms unbuilt | Windows, macOS, Android, and iOS targets exist but weren't built here. TODO-010 |

Follow-ups live in [`TODOS.md`](../TODOS.md), each one linked to an intent in
[`PYRAMID-OF-INTENTS.md`](../PYRAMID-OF-INTENTS.md).
