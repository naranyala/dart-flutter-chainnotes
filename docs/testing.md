# Testing guide

Testing is split by boundary so a failure points at the smallest relevant
layer. Nothing below the smoke test needs a display, a network, or a real
document on disk.

```sh
flutter test                                          # all suites, 107 functional + 8 guard
flutter test test/persistence_test.dart               # one suite
flutter test --reporter expanded                      # one line per test
flutter analyze                                       # must stay clean alongside
```

| Suite | Tests | What it proves |
| --- | ---: | --- |
| `test/workspace_test.dart` | 14 | The schema normalizes corrupt input into a safe record and round-trips |
| `test/persistence_test.dart` | 17 | The debounce, the write order, the boot merge rules, save modes, dispose-flush, and the post-hydrate mode |
| `test/workspace_store_test.dart` | 13 | The durable file: atomic rename, 4 MiB cap checked before reading, result codes |
| `test/boot_composition_test.dart` | 3 | The composition root wires the *boot cache* — not a fresh snapshot — into persistence |
| `test/metrics_test.dart` | 12 | The Welford engine: precision, rejected values never disturb state |
| `test/bridge_test.dart` | 11 | The request parser, the success payload, the error vocabulary and envelope |
| `test/tile_policy_test.dart` | 9 | The tile gate (concurrency, spacing, backoff) and oldest-first disk eviction |
| `test/tools_interaction_test.dart` | 12 | TOC declare/reorder/undo/filter, editor binding, PDF attach, outline transfers, places, lightbox stepping |
| `test/package_integration_test.dart` | 14 | Picker flows via fakes, locate denied/disabled/fix, pdf-package rendering, outline parsing, backend-seam open paths |
| `test/app_smoke_test.dart` | 2 | The shell mounts and walks all six views; the status bar menu button returns to the menu |

The running theme is that every layer is testable **without the one above
it**: the core suites need no widgets, the widget test needs no network or
filesystem writes, and no test needs a compiled desktop binary.

## The suites in detail

### Schema and normalization — `workspace_test.dart`

`normalizeWorkspace` is the only thing that turns bytes from disk into a
`WorkspaceRecord`, so it is the only place where "corrupt" has to become
"safe" rather than an exception. The suite covers an empty or garbage record
producing usable defaults, an unknown `view` being rejected while the session
clamp holds, remembered paths being trimmed, de-duplicated, and capped in
order, outline items without titles being dropped, a corrupt location reading
as no location, places keeping order with duplicate ids dropped and a 200 cap,
map and Google options degrading to defaults, a full round-trip through
normalize, a corrupt state still serializing to a valid record, plus
`countWords`, `clampLevel`, and id uniqueness.

### Persistence — `persistence_test.dart`

The behaviour with the highest blast radius, because a mistake here silently
loses work: **hydrate with the boot record, not with
`controller.snapshot()`.** The suite pins both merge directions (a newer
durable copy wins, an older one is ignored, a tie keeps durable, an empty
store keeps boot), the fact that user interaction short-circuits hydration, the
single debounced write, the cache-then-durable order, the three save modes
with their labels, the fallback when the durable path is broken, and a damaged
durable file reporting `INVALID_CONTENT`.

### The store — `workspace_store_test.dart`

Every `WorkspaceStoreResult` carries a message (there is no bare failure), a
missing file is an empty payload rather than an error, save/load round-trips
bytes, escapes, and UTF-8, an oversized payload is rejected *before* writing,
a payload exactly at the cap is accepted, an on-disk file over the cap is
rejected *before allocating*, the temp file is gone after a successful save,
and a missing directory or a directory-as-file fails with a message.

### The composition root — `boot_composition_test.dart`

Three tests, one bug. `readBootCache` and `startPersistence` are public
precisely so the wiring can be tested without a widget: a newer durable copy
is applied through the wiring, an older one leaves the boot state in place,
and a damaged boot cache degrades to an empty workspace. Reverting the
one-line fix in `main.dart` fails the first test — see
[TODO-001](../TODOS.md) for the defect this guards.

### Metrics — `metrics_test.dart`

Known values (`2, 4, 6` → count 3, sum 12, mean 4, variance `8/3`; the
documented example → population variance `6.125`), large values keeping
precision, a sum overflow leaving state untouched, a rejected non-finite value
never disturbing the running aggregate, reset cycles, bulk adds, and
reference values for `1..4`.

### Bridge protocol — `bridge_test.dart`

Every error code mapped to a non-empty message, whitespace and signed
exponents parsing, newlines as implicit separators, single and negative
arrays, `EMPTY_INPUT` for an empty inner array, the full success payload,
malformed and trailing data rejected, non-finite values reported as
`INVALID_VALUE`, a null request rejected, and the error envelope shape. The
contract itself is documented in
[bridge protocol](bridge-protocol.md#metrics-envelope).

### Shell smoke test — `app_smoke_test.dart`

The only test that instantiates widgets. It mounts the composition root,
asserts the menu, then walks **all six views** — menu, TOC, editor, PDF,
images, map — asserting each renders without a Flutter error and that no
widget overflows. That overflow assertion is not decoration: it is what caught
the `DropdownButtonFormField` inside a `Column` width bug on the first run
([TODO-002](../TODOS.md)).

## What is not tested

| Gap | Consequence |
| --- | --- |
| Interaction coverage is core-flows only | Picker, locate, and backend-seam paths are covered; picker cancel paths are thin — [TODO-007](../TODOS.md) |
| No native PDF rendering here | `pdfx` ships no Linux backend, so page rendering is backend-seam tested only, never with a real renderer — [TODO-017](../TODOS.md) |
| No observed green CI run | The workflow exists but has never been seen green on GitHub — [TODO-005](../TODOS.md) |
| No network, no tiles | `TileCache` is not exercised over HTTP; its failure paths are unit-tested only |
| No power-loss test for the store | The rename sequence is asserted structurally, not under `fsync` conditions — power-loss behaviour is stated, not proven |

## Keeping documents honest

`test/readme_test.dart` is a guard, not a feature test: it fails when the
README's repository map and this directory's index disagree with the tree.
Concretely it checks that

- every path named in the repository map exists,
- every Dart file under `lib/` and `test/` appears in the map,
- every guide linked from [`docs/README.md`](README.md) exists,
- every command quoted in the root `README.md` is one of the commands
  documented in [development](development.md#the-commands).

So the three things a stale document usually gets wrong — a renamed file, a
deleted file left in the map, and a command that no longer exists — fail the
suite instead of quietly misleading the next person.

The other half is procedural, and it is the same rule as everywhere else:
**when behaviour changes, update the guide and the test in the same change.**
