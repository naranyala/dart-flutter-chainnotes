# Testing guide

Tests are split by layer, so a failure points at the smallest place that
could be wrong. Nothing below the smoke test needs a screen, a network, or a
real file on disk.

```sh
flutter test                                          # everything, 125 feature + 8 guard
flutter test test/persistence_test.dart               # one suite
flutter test --reporter expanded                      # one line per test
flutter analyze                                       # should stay clean too
```

| Suite | Tests | What it checks |
| --- | ---: | --- |
| `test/workspace_test.dart` | 14 | Bad input becomes a safe record, and a good record round-trips |
| `test/persistence_test.dart` | 17 | Debounce timing, write order, boot merging, save labels, flush on close, and mode after restore |
| `test/workspace_store_test.dart` | 13 | Atomic saves, the 4 MiB limit checked before reading, result codes |
| `test/boot_composition_test.dart` | 3 | Startup wires in the *boot cache* — not a fresh snapshot |
| `test/metrics_test.dart` | 12 | Welford engine: precision, and bad values never corrupt state |
| `test/bridge_test.dart` | 11 | Request parsing, success shape, error codes and envelope |
| `test/tile_policy_test.dart` | 9 | Tile limits (how many at once, spacing, backoff) and old-first disk cleanup |
| `test/tools_interaction_test.dart` | 23 | Outline add/move/undo/filter, editor syncing, PDF attach, outline import/export, places, place stepping, go-to-coordinates, save-centre, picker cancellations, lightbox |
| `test/package_integration_test.dart` | 15 | Pickers with fakes, location denied/disabled/fix, PDF rendering and outline reading, open paths, plus a real `pdfrx` open-and-render on Linux |
| `test/app_smoke_test.dart` | 3 | The window opens with the real footer, all six views render, the menu navbar spans the window, and the menu button goes home |
| `test/boot_reopen_test.dart` | 5 | Restart reopens the remembered PDF/folder; gone paths are forgotten with a sentence |

The pattern throughout: every layer can be tested **without the one above
it**. Core tests need no widgets, widget tests need no network or file
writes, and no test needs a built desktop app.

## What each suite looks at

### File format — `workspace_test.dart`

`normalizeWorkspace` is the only way bytes from disk become a
`WorkspaceRecord`, so it's the only place where "corrupt" has to turn into
"safe" instead of throwing. The tests cover empty or garbage input becoming
defaults, an unknown `view` being rejected, remembered paths being trimmed
and capped, title-less outline items being dropped, a broken location reading
as no location, places keeping order with duplicate ids dropped and a 200
cap, map options falling back to defaults, a full save/load round-trip, plus
`countWords`, `clampLevel`, and unique ids.

### Saving — `persistence_test.dart`

This is the behaviour where a bug quietly loses work, so it's pinned down:
**hydrate from the boot record, not from `controller.snapshot()`.** The tests
cover both merge directions (newer durable wins, older is ignored, a tie keeps
durable, empty keeps boot), user input blocking a restore, a single debounced
write, cache-then-durable order, the three save labels, what happens when the
durable path is broken, and a damaged file reporting `INVALID_CONTENT`.

### The store — `workspace_store_test.dart`

Every `WorkspaceStoreResult` carries a message (nothing fails silently), a
missing file reads as empty rather than an error, save/load round-trips bytes
and UTF-8, an oversized save is rejected *before* writing, a file exactly at
the limit passes, an on-disk file over the limit is rejected *before
allocating memory*, the temp file is gone after saving, and a missing folder
or a folder-where-a-file-should-be fails with a message.

### Startup wiring — `boot_composition_test.dart`

Three tests for one past bug. `readBootCache` and `startPersistence` are
public so the wiring can be tested without widgets: a newer durable copy is
applied, an older one leaves the boot state alone, and a damaged boot cache
becomes an empty workspace. Undoing the one-line fix in `main.dart` fails the
first test — see [TODO-001](../TODOS.md).

### Metrics — `metrics_test.dart`

Known answers (`2, 4, 6` → count 3, sum 12, mean 4, variance `8/3`; the worked
example → population variance `6.125`), big values keeping precision,
overflow leaving state alone, a bad value never touching the running totals,
resets, bulk adds, and reference values for `1..4`.

### Bridge format — `bridge_test.dart`

Every error code has a message, spacing and signed exponents parse, newlines
separate values, single and negative arrays work, an empty inner array is
`EMPTY_INPUT`, the success shape is right, bad and trailing data is rejected,
non-finite values are `INVALID_VALUE`, null is rejected, and the error shape
holds. The format itself is in
[bridge protocol](bridge-protocol.md#metrics-envelope).

### Window smoke test — `app_smoke_test.dart`

The only tests that build widgets. The first opens the real composition root
with the real status-bar footer, checks the menu, then walks **all six
views** — menu, outline, editor, PDF, images, map — making sure each renders
without a Flutter error and nothing overflows. That overflow check earned its
keep twice: it caught a `DropdownButtonFormField` that was too wide for its
toolbar on the first run ([TODO-002](../TODOS.md)), and a status-bar `Row`
nested in another `Row` that killed the first frame on device. The second
asserts the menu navbar spans the full window width at 1600 px.

## What isn't tested

| Gap | What it means |
| --- | --- |
| Main flows only | Pickers, locate, open paths, and picker cancellations (TOC import/export/combine, PDF open) are covered; image-folder and map-file cancellations are not — [TODO-007](../TODOS.md) |
| PDF rendering | `pdfrx` opens and renders a real PDF on Linux (skips only where the PDFium native asset is missing); `pdfx` paths elsewhere are seam-tested with fakes |
| CI is green | The workflow runs analyze, test, and the Linux debug build on every push — [TODO-005](../TODOS.md) |
| No network or tiles | `TileCache` never hits HTTP in tests; failure paths are unit-tested only |
| No power-loss test | The rename order is checked, but `fsync` behaviour isn't proven — it's documented, not tested |

## Keeping documents honest

`test/readme_test.dart` isn't a feature test, it's a guard: it fails when the
README map or this folder's index drift from the code. It checks that

- every path in the repository map exists,
- every Dart file under `lib/` and `test/` shows up in the map,
- every guide linked from [`docs/README.md`](README.md) exists,
- every command quoted in the root `README.md` is documented in
  [development](development.md#the-commands).

So the three usual ways a doc goes wrong — a renamed file, a deleted file
left in the map, a command that no longer exists — fail the suite instead of
quietly misleading the next person.

The other half is habit, and it's the same everywhere:
**when behaviour changes, update the guide and the test together.**
