# The six tools

One window, six views, one shared record. Every tool reads and writes the same
`WorkspaceRecord` through `WorkspaceController`, so a change in one shows up
in the others right away and gets saved the same way.

Things a tool only needs for now live in a session; things that should survive
a restart live in the record. Here's the split:

| Tool | View | Session | Saved in the record |
| --- | --- | --- | --- |
| Launcher | `lib/ui/menu_view.dart` | — | `view` (which tool to reopen) |
| TOC Manager | `lib/ui/toc_view.dart` | — | `outline`, `editor`, `lastRemoved` |
| Text Editor | `lib/ui/editor_view.dart` | — | `editor` (text, word count, cursor) |
| PDF Reader | `lib/ui/pdf_view.dart` | `PdfSession` | `pdf` (path, page, zoom, headings) |
| Image Viewer | `lib/ui/images_view.dart` | `ImageSession` | `images` (path, groups, lightbox) |
| Map Explorer | `lib/ui/map_view.dart` | `MapSession` | `map`, `googleMap` |

All six stay mounted in an animated stack in `lib/ui/shell.dart` — a 200 ms
crossfade with a short slide in the menu direction — so switching tools
doesn't rebuild anything: scroll position, open PDF pages, and the map stay
where they were.

## Launcher

The front door. Six cards, each with a title, a one-line description, and a
**live badge** taken from the shared record:

- **TOC Manager** — how many items, or `empty`
- **Text Editor** — words in the current draft, or `no selection`
- **PDF Reader** — `page 12 / 80`, or `no document`
- **Image Viewer** — `42 images`, or `no directory`
- **Map Explorer** — pin and place counts

Tapping a card sets `controller.view`, and the shell follows it. The launcher
doesn't store anything itself — it's just buttons over state the other tools
wrote.

## TOC Manager

This is the spine of the workspace — the outline everything else points at.

**Adding.** Type a title, pick a level (1–3), and add it. Empty titles are
turned away with a status message instead of being quietly dropped, and ids
come from `createTocItem`, which keeps them unique.

**Moving and removing.** Items move up and down, and removing one remembers it
so `Undo remove` can bring it back — `lastRemoved` is saved, so undo works
even after a restart.

**Filtering.** A simple text filter over titles. It only shows up once you
have enough items to need it.

**Writing.** Picking an item calls `controller.selectTocItem`, which loads
that item's draft into the editor. That's the connection between the outline
and the writing surface — see [Text Editor](#text-editor).

**Linking outward.** An item can point at a PDF page, some images, a location,
and a label. You attach those from the *other* tool's toolbar (`Attach page`,
`Select outline item`, `Attach location`), and the TOC shows what came back.
Those links are also what the editor toolbar jumps to.

**Moving outlines around.**

- `Export…` / `Import…` — a JSON file (`metrics-toc`, version 1) via
  `FileService`. Opening anything else says
  `That file is not an outline export.`
- `Combine to PDF` — renders the whole outline to a PDF with
  `renderOutlinePdf`, then offers `Preview <name> · N pages`, which opens it
  in the PDF Reader.
- **Import headings from PDF** — when a document is open, pulls its headings
  into the outline with `importPdfHeadings`.

## Text Editor

One text box tied to one heading: `controller.editorContent` plus which item
is selected.

**How it stays in sync.** Picking a heading loads its draft; every keystroke
goes through `setEditorContent`, which saves the text, recounts words, and
calls `syncTocDraft` — so the outline and the editor always agree. Saving
itself is the usual `touch()` → 250 ms debounce → store.

**Toolbar.** `‹ Outline` goes back to the list, `PDF p.<n>` and `Location`
jump to whatever this heading links to, `‹ Prev` / `Next ›` step between
headings without leaving the editor, and `Import…` / `Export…` move a draft
through files.

**Status line.** `N words · <save mode>`, where the mode is `saved to disk`,
`auto-saved`, or `not saved` — plus `Line x, Col y` for the cursor.

**A quirk worth knowing.** The label counts saves made *in this run*, so right
after a restore it says `not saved` until you type again. Nothing failed;
that's just how it counts: [TODO-004](../TODOS.md).

## PDF Reader

Opens a document, shows its pages, reads its headings, and remembers where
you were.

**Opening.** `FileService.chooseFile` → `PdfSession.openAt`. Pages are
decoded by the platform renderer (`pdfx` on mobile and macOS/Windows,
`pdfrx`/PDFium on Linux) and rendered as needed into a small cache. The
reader is a plain `ListView` of pages, so scrolling feels normal.

**Controls.** `Previous` / `Next`, a `Page 12 of 80` readout, and zoom in 10%
steps from **60% to 250%** (`renderZoom`), with the percentage in the toolbar.

**Remembering.** The record keeps `path`, `name`, `page`, `zoom`, and recent
paths. It doesn't reopen the file on its own: after a restart you get a
`REMEMBERED` list, and picking from it restores the saved page.
[TODO-016](../TODOS.md) tracks whether that should become automatic.

**Headings.** The outline (read by `lib/core/pdf/pdf_outline.dart`, which does
its best with `/Outlines`, object streams, and the page tree) shows in a
sidebar with a count, and `Import headings` sends them to the TOC Manager.
The TOC's `Import headings from PDF` button uses the same path when a
document is open.

**Linking.** `Attach page` ties the current page to the selected heading, and
the editor's `PDF p.<n>` button jumps back to it.

## Image Viewer

A folder browser, not a file manager.

**Picking.** `Choose directory` opens a folder; the scan groups files by their
parent folder name and remembers the path. Two limits keep big folders sane —
`maxBrowserImages` (500) and a per-folder cap — and hitting one shows
`N images (the scan reached its limit)` instead of quietly cutting off.

**Looking around.** Folder groups with counts on the side, a thumbnail grid,
and a lightbox you can step through with the keyboard. The selected group and
lightbox position are saved, so you land back where you were.

**Linking.** `Select outline item` on an image ties it to a heading — the
other half of the editor's image link, stored as `links.images`.

## Map Explorer

A hand-drawn OpenStreetMap canvas — no mapping package — with places and
layers on top. Tile hosting, caching, and licensing are in
[map sources](map-sources.md); this is how it feels to use.

**Moving around.** Drag to pan, zoom in fixed steps (levels 1–19) with the
wheel, pinch, or `−` / `+`. You can rotate with a bearing readout in the
corner (`045° NE · 1.2 km · 18/19`).

**Look.** One basemap with a tint — `none`, `grayscale`, `dark`, `sepia`,
`vivid`, `faded` — plus a `Grid` lined up to the current zoom. The renderer
label (`Canvas renderer` / `DOM renderer`) is kept for parity with the
original.

**Places.** Long-press to drop a pin, `Save pin` to name it, `Clear` to
remove all places, `Import` for a places file (`.csv` or GeoJSON via
`parsePlacesFile`), and `Attach location` to tie the pin to the selected
heading. Up to 200 places are kept, in order. Tapping a place — in the list
or its marker on the canvas — flies to it; `‹ Prev` / `Next ›` steps through
all of them with wraparound and a `2 of 5` readout, so you can hop between
locations one tap at a time.

**Position.** The sidebar always shows live coordinates — the pin's, or the
map centre's when there is no pin — with `Copy` for the clipboard, `Clear
pin`, and `Save centre` to store what the canvas is showing as a place.

**Go to.** Two fields and a `Go` button fly to typed coordinates (`48.8566,
2.3522`; commas work as decimal separators) and drop the pin there. Anything
else gets a sentence explaining the format instead of silence.

**Layers.** `Load GeoJSON` draws features over the tiles; `Clear` takes them
off again.

**Locate.** `Locate` asks `geolocator` for permission and flies to where you
are. If you say no, that's a status message, not a crash.

## The shared record

It's all one document underneath:

```jsonc
{
  "view": "pdf",              // which tool to show on restart
  "outline": [ … ],           // headings, levels, drafts, links
  "editor": { … },            // selected item, text, word count, cursor
  "pdf": { … },               // path, name, page, zoom, headings, recents
  "images": { … },            // path, selected group, lightbox, recents
  "map": { … },               // position, pin, places, tint, layers
  "googleMap": { … },         // loaded and saved, not shown
  "savedAt": 1759000000000
}
```

`normalizeWorkspace` turns any subset of that into something usable, which is
why a corrupt or half-written file becomes a degraded workspace instead of a
crash. The section names match the fields in
`lib/core/workspace/workspace_models.dart`.

## Google Maps: saved but not shown

There's no Google Maps view. The `googleMap` section still loads and saves so
a workspace from elsewhere doesn't lose anything, but nothing draws it.
Whether to build that here is still open ([TODO-013](../TODOS.md)).
