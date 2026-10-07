# Bridge protocol and tool surfaces

## What the bridge was, and what it is now

In `../webview-app-with-clua` the UI could do nothing on its own: it called one
of **14 WebView bindings**, and got structured JSON or
`{"error":{"code":…,"message":…}}` back. That protocol is documented for the
original in its own `docs/bridge-protocol.md`.

There is no WebView here, so there are no bindings. What survived the port is
the part that was always a *contract* rather than a transport:

1. **The metrics request/response envelope**, byte-for-byte compatible with
   `src/webview_bridge.c`, in
   [`lib/core/metrics/summarize_bridge.dart`](../lib/core/metrics/summarize_bridge.dart).
2. **The rule that a failure is a value, not an exception** — a result object
   with a code and a message, which every seam in the app follows.

Everything else — pickers, document loading, directory scans, tile fetches,
workspace writes — became a Dart API in a named module. The table in
[Tool surfaces](#tool-surfaces) is the mapping, so a reader of the original can
find the replacement for any binding.

## Metrics envelope

The one serialized contract still in the tree, kept because it is exercised by
tests and could be re-exposed at any time.

### Request

```
[[number, number, ...]]
```

An outer array containing one inner array of numbers. The parser accepts:

- **Comma or newline as separators.** A newline between values is an implicit
  separator, exactly as the C parser treats it.
- **Whitespace anywhere between tokens**, including inside the brackets.
- **Signs and exponents** (`-1.5`, `+2`, `1e-3`), and the literals `nan`,
  `inf`, `infinity` and their sign variants — which *parse* and then fail the
  finite check, so they report `INVALID_VALUE` rather than `INVALID_REQUEST`.
  That ordering is deliberate: it is what `strtod` does.
- **Nothing else.** Space alone is not a separator: `[[1 2]]` is
  `INVALID_REQUEST`. Trailing content after the outer bracket is
  `trailingData` → `INVALID_REQUEST`.

### Success response

```json
{"count":3,"sum":12,"min":1,"max":9,"mean":4,"variance":2.6666666666666665}
```

`variance` is the **population** variance (`M2 / count`). Doubles are written
in the shortest faithful decimal form; an integral value below `1e21` is
written without a decimal point.

### Error response

```json
{"error":{"code":"INVALID_VALUE","message":"Every value must be finite (not NaN or infinity) and within the numeric range."}}
```

The same envelope shape the C writer produced, produced by
`errorEnvelope(code, message)` with `jsonString` escaping for quotes,
backslashes, control characters, and line breaks.

### Error codes

| Code | Raised when |
| --- | --- |
| `INVALID_REQUEST` | The request is not `[[…]]`, a value is missing, or data follows the array |
| `EMPTY_INPUT` | The inner array is well-formed but holds no values |
| `INVALID_VALUE` | A value parses but is not finite (`nan`, `inf`) |
| `ENGINE_FAILED` | The engine rejected a value it was given |
| `BUFFER_TOO_SMALL` | The response buffer cannot hold the result |
| `OUT_OF_MEMORY` | The engine could not be allocated |
| `NULL_RESPONSE` / null request | A null buffer or null request argument |

Two honest divergences from the C bridge, because pretending otherwise would
mislead:

- **`BUFFER_TOO_SMALL` and `NULL_RESPONSE` are unreachable in Dart.** There is
  no caller-supplied response buffer and no nullable buffer argument; the codes
  and their messages exist so the vocabulary matches the original and so
  `test/bridge_test.dart` can pin every code to a message. Nothing in this
  application can raise them.
- **The envelope is produced, not consumed, by the application.** No view calls
  `runSummarizeBridge`; the metrics core has no production caller (intent
  **I1.4**, [TODO-011](../TODOS.md)).

## Tool surfaces

What each original binding became. The left column is the binding name from
`src/webview_app.c`; the right column is where the work happens now.

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

The shape of the change: where the original had a *serialization boundary*
(request JSON in, response JSON out), the port has a *module boundary*
(objects in, objects out). Both are checkable — the first with a protocol
document and a parser test, the second by reading who imports whom.

## Failure reporting in the UI

Every failure the user can see is a sentence in a status line or the report
pill, never an unhandled exception:

| Surface | Owner | Example |
| --- | --- | --- |
| Per-tool status line | `ToolStatus` on the session or controller | `That file is not an outline export.` |
| Store result codes | `WorkspaceStoreResult` (`ok`, `read`, `write`, `tooLarge`, `argument`) | Surfaced as `The workspace could not be saved on this device.` |
| Persistence report | `PersistenceReport` + `formatWorkspaceReport` | `Workspace not saved: This device rejected the workspace write.` |
| Save mode pill | `PersistenceMode` (`native` / `local` / `none`) | `saved to disk` / `auto-saved` / `not saved` |

The report pill carries two sentences, and only two —
`Workspace not saved: …` for a rejected write and
`Saved workspace not restored: …` for a rejected load. Both are produced by
one function so the wording cannot drift between call sites.

## Testing the contract

```sh
flutter test test/bridge_test.dart     # 11 tests: vocabulary, parsing, envelope
flutter test test/metrics_test.dart    # 12 tests: the engine behind it
```

The bridge suite pins every error code to a non-empty message, the success
shape, signed and exponential input, whitespace handling, the newline
separator, trailing-data rejection, and the escaping in `jsonString`. What it
does not cover — and what no test here can — is a caller, because there is
none: see [TODO-011](../TODOS.md).
