# The six tools

One shell, six views, one shared record. Every tool reads and writes the same
`WorkspaceRecord` through `WorkspaceController`, so a change made in one is
visible in another immediately and reaches disk on the same debounced path.

What each tool owns *transiently* lives in a session; what it owns *durably*
lives in a section of the record. The table is the map:

| Tool | View | Session | Record section |
| --- | --- | --- | --- |
| Launcher | `lib/ui/menu_view.dart` | — | `view` (what to reopen) |
| TOC Manager | `lib/ui/toc_view.dart` | — | `outline`, `editor`, `lastRemoved` |
| Text Editor | `lib/ui/editor_view.dart` | — | `editor` (buffer, word count, cursor) |
| PDF Reader | `lib/ui/pdf_view.dart` | `PdfSession` | `pdf` (path, page, zoom, headings) |
| Image Viewer | `lib/ui/images_view.dart` | `ImageSession` | `images` (path, groups, lightbox) |
| Map Explorer | `lib/ui/map_view.dart` | `MapSession` | `map`, `googleMap` |

All six are mounted at once inside an `IndexedStack` in
`lib/ui/shell.dart`, so switching tools does not rebuild anything: scroll
position, decoded PDF pages, and the map canvas all survive.

## Launcher

The entry point, ported from `frontend-vue/src/App.vue`. Six cards — each with
a title, one line of description, and a **live badge** drawn from the shared
record rather than a static string:

- **TOC Manager** — item count, or `empty`
- **Text Editor** — words in the active draft, or `no selection`
- **PDF Reader** — `page 12 / 80`, or `no document`
- **Image Viewer** — `42 images`, or `no directory`
- **Map Explorer** — pin count and named places

A card is a button; clicking it sets `controller.view`, which the shell's
`IndexedStack` follows. Nothing else is stored: the launcher is pure
presentation over state other tools write.

## TOC Manager

The outline spine — the tool that creates the structure the other three
reference.

**Declare.** A title field, a level selector (1–3), and an add action. Empty
titles are refused with a status line rather than silently ignored; ids come
from `createTocItem`, which is tested for uniqueness.

**Reorder and remove.** Items move up and down, and a removal is remembered so
`Undo remove` can put it back — `lastRemoved` is part of the record, so the
undo survives a restart.

**Filter.** A substring filter over titles; it appears only once there are
enough items to need it.

**Bind to the editor.** Selecting an item calls `controller.selectTocItem`,
which restores that item's draft into the editor buffer. This is the link
between the spine and the writing surface — see
[Text Editor](#text-editor).

**Link outward.** Each item can carry a PDF page, a set of images, a location,
and a link label. Attaching happens from the *other* tool's toolbar
(`Attach page`, the images' `Select outline item`, `Attach location`), and the
TOC shows what came back. Links are one of the three things the editor toolbar
jumps to.

**Transfers.**

- `Export…` / `Import…` — a JSON envelope (`metrics-toc`, version 1) through
  `FileService`. An import of something else reports
  `That file is not an outline export.`
- `Combine to PDF` — renders the whole outline to a PDF via
  `renderOutlinePdf`, then offers `Preview <name> · N pages`, which opens the
  result in the PDF Reader.
- **Import headings from PDF** — when a document is open, its extracted
  headings are pulled into the outline with `importPdfHeadings`.

## Text Editor

A single bound buffer: `controller.editorContent`, plus the active item.

**Binding.** `selectTocItem` loads the item's saved draft; every keystroke
goes through `setEditorContent`, which stores the text, recomputes the word
count, and calls `syncTocDraft` — so the outline and the editor never disagree
about what a heading says. The write itself is the controller's usual
`touch()` → 250 ms debounce → store path.

**Toolbar.** `‹ Outline` returns to the spine, `PDF p.<n>` and `Location` jump
to the linked targets in their tools, `‹ Prev` / `Next ›` move between
neighbouring outline items without leaving the buffer, and
`Import…` / `Export…` move a draft through `FileService`.

**Status line.** `N words · <save mode>` where the mode comes from
`PersistenceMode` — `saved to disk`, `auto-saved`, or `not saved` — plus a
live `Line x, Col y` cursor position.

**Note on the save label.** It reports writes made *this session*, so it reads
`not saved` immediately after a successful restore until the next edit. That
is a known wart, not a failed write: [TODO-004](../TODOS.md).

## PDF Reader

Opens a document, renders its pages, extracts its headings, and keeps its
position in the record.

**Opening.** `FileService.chooseFile` → `PdfSession.openAt`. Pages are decoded
with `pdfx` and rendered on demand into a page cache; the reader is a
`ListView` of pages, so scrolling and page count are natural rather than
modelled.

**Controls.** `Previous` / `Next` paging, a page readout
(`Page 12 of 80`), and zoom in 10 % steps clamped to **60 %–250 %**
(`renderZoom`), with the percentage shown in the toolbar.

**Persistence.** The record keeps `path`, `name`, `page`, `zoom`, and the
remembered path list. What it does **not** do is reopen the file by itself: on
restart the reader shows a `REMEMBERED` list and the recorded page is applied
when you pick it. [TODO-016](../TODOS.md) tracks closing that gap.

**Headings.** The extracted outline (from `lib/core/pdf/pdf_outline.dart`, a
best-effort parser that walks `/Outlines`, object streams, and the page tree)
appears in a sidebar with a count, and `Import headings` pushes them into the
TOC Manager. When a document is open, the TOC's `Import headings from PDF`
action uses the same path.

**Linking.** `Attach page` on the current page binds it to the selected
outline item, which the editor's `PDF p.<n>` button then jumps back to.

## Image Viewer

A directory scanner and viewer, not a file manager.

**Choosing.** `Choose directory` opens a folder; the scan walks it, groups
files by their parent folder name, and records the path in the record's
remembered list. Two limits are enforced during the scan — `maxBrowserImages`
(500) and a per-directory cap — and hitting one sets `limited`, reported as
`N images (the scan reached its limit)` rather than silently truncating.

**Browsing.** A sidebar of folder groups with counts, a grid of thumbnails
decoded on demand, and a lightbox with keyboard navigation. Selected group and
lightbox index are recorded, so a restart comes back to the same place.

**Linking.** `Select outline item` on an image attaches it to the outline item
— the counterpart of the editor's `Attach images`, stored as
`links.images` on the item.

## Map Explorer

A hand-written OpenStreetMap tile canvas — no mapping library — plus the saved
places and layers. The full sourcing, caching, and licensing position is in
[map sources](map-sources.md); this is the interaction layer.

**Viewport.** Pan by dragging, zoom in fixed steps over committed integer zoom
levels (1–19) with wheel/pinch and `−` / `+`, plus optional rotation with a
bearing readout (`045° NE · 1.2 km · 18/19`) in the corner.

**Style.** A colour filter over one basemap — `none`, `grayscale`, `dark`,
`sepia`, `vivid`, `faded` — and a `Grid` overlay aligned to the tile grid of
the committed zoom level. The renderer label (`Canvas renderer` / `DOM
renderer`) is carried from the original for parity.

**Places.** Click to drop a pin, `Save pin` to record it with a name,
`Clear` to remove it, `Import` to load a places file (`.csv` or GeoJSON, via
`parsePlacesFile`), and `Attach location` to bind the pin to the selected
outline item. The record keeps up to 200 places in order.

**Layers.** `Load GeoJSON` draws a feature layer over the tiles; `Clear`
removes it.

**Locate.** `Locate` asks `geolocator` for permission and flies to the current
position; a denial is a status message, never a thrown error.

## The shared record

Everything above is one document:

```jsonc
{
  "view": "pdf",              // which tool to show on restart
  "outline": [ … ],           // items, levels, drafts, links
  "editor": { … },            // active item, buffer, word count, cursor
  "pdf": { … },               // path, name, page, zoom, headings, recents
  "images": { … },            // path, selected group, lightbox, recents
  "map": { … },               // viewport, pin, places, filter, layers
  "googleMap": { … },         // normalized and persisted, not displayed
  "savedAt": 1759000000000
}
```

`normalizeWorkspace` accepts any subset of that and returns something usable,
which is what makes a corrupt or partial file a degraded workspace rather than
a crash. The section names are also the fields in
`lib/core/workspace/workspace_models.dart`.

## Google Maps: record only

There is no Google Maps view. The `googleMap` section is normalized and
persisted so a workspace exported from the original application loads here
without losing data, but nothing renders it — the original's viewer fetched
tiles from an unlicensed endpoint, and whether to build that into this project
is an open decision ([TODO-013](../TODOS.md)).
