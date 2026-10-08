# Bridge protocol and tool surfaces

## What carried over

The original app ran its UI in a WebView, so the UI couldn't do much alone:
it called one of **14 bindings** and got back JSON, or
`{"error":{"code":…,"message":…}}` when something went wrong.

There's no WebView here, so there are no bindings. What did carry over is the
part that was always a *promise* rather than a transport:

1. **The metrics request/response shape**, compatible with the old C code, in
   [`lib/core/metrics/summarize_bridge.dart`](../lib/core/metrics/summarize_bridge.dart).
2. **The habit of returning failures as values, not exceptions** — a small
   object with a code and a message, which every part of the app follows.

Everything else — pickers, opening documents, scanning folders, fetching
tiles, saving the workspace — is now a plain Dart API in a named module. The
table in [Tool surfaces](#tool-surfaces) maps old binding names to their new
homes.

## Metrics format

The one serialized format still in the project. It's kept because tests use it
and it could be exposed again at any time.

### Request

```
[[number, number, ...]]
```

An outer array holding one inner array of numbers. The parser accepts:

- **Commas or newlines between values.** A newline counts as a separator,
  just like the C parser did.
- **Spaces anywhere between tokens**, even inside the brackets.
- **Signs and exponents** (`-1.5`, `+2`, `1e-3`), plus `nan`, `inf`,
  `infinity` and their signed forms — those *parse* first and then fail the
  "must be finite" check, so they come back as `INVALID_VALUE` rather than
  `INVALID_REQUEST`. That order matches what `strtod` does.
- **Nothing else.** A bare space isn't a separator: `[[1 2]]` is
  `INVALID_REQUEST`. Anything after the outer bracket is trailing data, also
  `INVALID_REQUEST`.

### A successful reply

```json
{"count":3,"sum":12,"min":1,"max":9,"mean":4,"variance":2.6666666666666665}
```

`variance` is the **population** variance (`M2 / count`). Numbers are written
as short as possible; whole numbers below `1e21` have no decimal point.

### When something's wrong

```json
{"error":{"code":"INVALID_VALUE","message":"Every value must be finite (not NaN or infinity) and within the numeric range."}}
```

Same shape the C code produced, built by `errorEnvelope(code, message)` with
`jsonString` escaping quotes, backslashes, control characters, and line
breaks.

### Error codes

| Code | When you get it |
| --- | --- |
| `INVALID_REQUEST` | The request isn't `[[…]]`, a value is missing, or something follows the array |
| `EMPTY_INPUT` | The inner array is fine but empty |
| `INVALID_VALUE` | A value parses but isn't finite (`nan`, `inf`) |
| `ENGINE_FAILED` | The engine turned down a value it was given |
| `BUFFER_TOO_SMALL` | The reply didn't fit the buffer |
| `OUT_OF_MEMORY` | The engine couldn't be created |
| `NULL_RESPONSE` / null request | A null buffer or null request |

Two honest differences from the C version:

- **`BUFFER_TOO_SMALL` and `NULL_RESPONSE` can't happen in Dart.** There's no
  caller-provided buffer and no nullable buffer argument. The codes and
  messages stay so the vocabulary matches and `test/bridge_test.dart` can pin
  every code to a message. Nothing in the app can raise them.
- **The format is produced but never called.** No view calls
  `runSummarizeBridge` — the metrics code has no production caller (intent
  **I1.4**, [TODO-011](../TODOS.md)).

## Tool surfaces

What each old binding became. The left column is the name from the original
C code; the right is where that work happens now.

| Original binding | Dart replacement | File |
| --- | --- | --- |
| `loadWorkspace` / `saveWorkspace` | `WorkspacePersistence` over `WorkspaceStore` | `lib/core/workspace/workspace_persistence.dart`, `workspace_store.dart` |
| `summarize` | `runSummarizeBridge` (library only, no UI caller) | `lib/core/metrics/summarize_bridge.dart` |
| `openPdf` / `openPdfAt` | `PdfSession.openAt` | `lib/sessions/pdf_session.dart` |
| `extractPdfToc` | `PdfSession.loadToc` via `parsePdfOutline` | `lib/sessions/pdf_session.dart`, `lib/core/pdf/pdf_outline.dart` |
| `openImageDirectory` / `openImageDirectoryAt` | `ImageSession.openAt` | `lib/sessions/image_session.dart` |
| `loadImageAt` | `Image.file` on the scanned path | `lib/ui/images_view.dart` |
| `openTextFile` / `saveTextFile` | `FileService.readTextFile` / `writeTextFile` | `lib/app/services.dart` |
| `chooseOutlineDirectory` / `renderOutlinePdf` | `renderOutlinePdf` | `lib/core/pdf/outline_pdf_writer.dart` |
| Tile fetching (page-side `<img>`, never a binding) | `TileCache.tile` | `lib/core/map/tile_source.dart` |
| Location (`navigator.geolocation`) | `Geolocator` behind `MapSession.locate` | `lib/sessions/map_session.dart` |
| File and directory pickers (`app_support.c`) | `FileService.chooseFile` / `choosePath` / `chooseDirectory` | `lib/app/services.dart` |
| Heading import into the outline | `WorkspaceController.importPdfHeadings` | `lib/app/workspace_controller.dart` |

The shape of the change is simple: where the old code had a *file-format
boundary* (JSON in, JSON out), the new code has a *module boundary* (objects
in, objects out). Both are easy to check — the first with this doc and a
parser test, the second by seeing who imports whom.

## How failures reach you

Anything you can see going wrong shows up as a sentence in a status line or
the small report pill — never as an unhandled exception:

| Where | Who owns it | Example |
| --- | --- | --- |
| Per-tool status line | `ToolStatus` on the session or controller | `That file is not an outline export.` |
| Store result codes | `WorkspaceStoreResult` (`ok`, `read`, `write`, `tooLarge`, `argument`) | Shown as `The workspace could not be saved on this device.` |
| Save/load report | `PersistenceReport` + `formatWorkspaceReport` | `Workspace not saved: This device rejected the workspace write.` |
| Save pill | `PersistenceMode` (`native` / `local` / `none`) | `saved to disk` / `auto-saved` / `not saved` |

The report pill only ever says two things —
`Workspace not saved: …` for a failed write and
`Saved workspace not restored: …` for a failed load. Both come from one
function so the wording can't drift.

## Testing it

```sh
flutter test test/bridge_test.dart     # 11 tests: codes, parsing, envelope
flutter test test/metrics_test.dart    # 12 tests: the engine behind it
```

The bridge tests check every code has a message, the success shape, signed and
exponential input, spacing, newlines as separators, trailing data, and the
escaping in `jsonString`. What they can't cover is a caller, because there
isn't one: see [TODO-011](../TODOS.md).
