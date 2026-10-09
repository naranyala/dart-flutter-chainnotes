# TODOs

This is the implementation backlog for the intents in
[`PYRAMID-OF-INTENTS.md`](./PYRAMID-OF-INTENTS.md). Every item has an intent
reference, a priority, and a definition of done. Items closed during the port
are kept at the bottom **with evidence** and should be moved to a changelog
when this backlog is next re-baselined.

Priority levels:

- **P0** — blocks the intended happy path or makes the project misleading.
- **P1** — important for a dependable project.
- **P2** — improves maintainability, portability, or teaching value.
- **P3** — optional polish or a future extension.

## P0 — Make the documented product work end to end

No open P0 items. TODO-003, TODO-004, and TODO-006 closed with evidence
below.

## P1 — Make the workspace dependable

No open P1 items. TODO-005, TODO-007, and TODO-016 closed with evidence
below.

## P2 — Keep it maintainable and portable

### TODO-010 — Build the remaining declared platforms

- **Intent:** I4.3, I3.3, I4.4
- **Priority:** P2
- **Work:** Linux debug + release and web release build here, the macOS
  `Info.plist` carries the location usage string, and the README names the
  supported set. Still unbuilt here: Windows (needs a Windows host),
  macOS/iOS (need Xcode), and location exercised on
  a real device. Android was attempted on 2026-10-09: an SDK exists at
  `~/Android/Sdk` (build-tools 36.0.0, platform android-37) but its NDK
  `28.2.13676358` directory is empty (no `source.properties`, so AGP fails
  with CXX1101) and there are no `cmdline-tools` to repair it with — fixing
  the host SDK is out of scope, so the APK stays unbuilt. Build each
  remaining target that ships and record it.
- **Done when:** Every platform listed as supported builds from a clean
  checkout, and the README names exactly those.

## P3 — Optional polish and open decisions

No open P3 items. TODO-015 closed with evidence below.

## Closed (with evidence)

### TODO-015 — Measure release first-run latency — DONE

- **Intent:** I0.1, I2.4
- **Priority:** P3
- **Evidence:** `flutter build linux --release` then launched the bundle three
  times on a display (temporary first-frame probe, reverted after measuring):
  ~3.5 s cold, ~3.5 s, ~3.2 s warm from launch to first frame, including
  reopening the remembered PDF. Numbers and the grown bundle size (33 M, was
  25 M before the PDFium renderer) recorded in the README Platforms note.

### TODO-007 — Cover the remaining interaction flows — DONE

- **Intent:** I4.1, I2.2
- **Priority:** P1
- **Work:** picker *cancel* paths (user dismisses the dialog) had no widget
  coverage.
- **Evidence:** `test/tools_interaction_test.dart` gains four cancel-path
  widget tests — TOC JSON import leaves the outline alone, TOC JSON export
  writes nothing, combine-to-PDF reports `No folder chosen.`, and PDF open
  leaves the reader closed — all driven through the shared `FakeFileService`
  (moved to `test/fakes.dart` so both suites use it). Full suite: 128/128,
  `flutter analyze` clean.

### TODO-005 — See a green CI run for analyze, test, and the Linux build — DONE

- **Intent:** I1.5, I4.1, I4.3
- **Priority:** P1
- **Evidence:** four consecutive green runs on `main`, latest
  [run 37877115162](https://github.com/naranyala/dart-flutter-chainnotes/actions/runs/37877115162)
  (`7d635ab`, success) running exactly `flutter analyze`, `flutter test`,
  and `flutter build linux --debug` on Flutter 3.47.5; a failing step fails
  its job, so a breaking change fails the run. Status badge added at the top
  of the README.

### TODO-016 — Reopen the remembered document and folder on restart — DONE

- **Intent:** I2.1, I1.1
- **Priority:** P1
- **Work:** `reopenRemembered()` in `lib/main.dart` runs after the sessions
  are built and before `runApp`: the remembered PDF reopens at its recorded
  page/zoom, the remembered image folder rescans with its recorded group put
  back when it still exists. A remembered path whose file is gone is
  forgotten with a `…is gone — pick it again…` sentence in that tool's
  status line.
- **Evidence:** `test/boot_reopen_test.dart` (5 tests) — PDF reopens with its
  recorded page, gone PDF forgotten with a sentence, folder reopens with its
  recorded group, gone folder reports without crashing, nothing remembered
  means nothing happens. Full suite: 133/133, `flutter analyze` clean.

### TODO-017 — Decide the Linux PDF rendering story — DONE

- **Intent:** I4.4, I4.3
- **Priority:** P2
- **Decision:** adopted a renderer with a Linux backend — `pdfrx` (PDFium via
  native assets) on Linux, `pdfx` everywhere else. The `PdfOpener` seam
  (`lib/sessions/pdf_backend.dart`) now hides engine-neutral
  `PdfEngineDocument`/`PdfEnginePage` handles behind per-platform openers
  picked by `platformPdfOpener()`; `PdfSession` renders through them, so no
  view code changed.
- **Evidence:** `test/package_integration_test.dart` gains a real open +
  render test (a `pdf`-package PDF opened and rendered to PNG bytes through
  `PdfrxOpener`); on-device run opened a 3-page sample (`Page 1 of 3`) and
  rendered page 1 to a 14 KB PNG with visible content. Full suite: 128/128,
  `flutter analyze` clean.

### TODO-001 — Hydrate from the boot cache record, not a fresh snapshot — DONE

- **Intent:** I1.3, I2.1, I3.2
- **Priority:** P0
- **Work:** The composition root passed `controller.snapshot()` to
  `WorkspacePersistence.hydrate`, and `snapshot()` stamps `savedAt` with the
  current time — so the durable copy was always strictly older than the
  "boot" record and was always skipped. A restart therefore restored nothing
  while every merge-rule test still passed, because they call `hydrate` with
  the record they mean. Boot reading and persistence start-up are now the
  named functions `readBootCache` and `startPersistence` in `lib/main.dart`,
  both taking the cache record as the boot half of the merge.
- **Done when:** The wiring, not just the rule, is covered by a test that
  fails against the previous code.
- **Evidence:** `test/boot_composition_test.dart` (3 tests) — a newer durable
  copy is applied, an older one is ignored, a damaged cache degrades to an
  empty workspace. Reverting `startPersistence` to
  `hydrate(controller.snapshot())` fails the first test and passes the other
  two; with the fix all pass. Full suite: 67 tests, `flutter analyze` clean.

### TODO-002 — Fix the dropdown widths that overflowed the toolbars — DONE

- **Intent:** I2.2, I4.1
- **Priority:** P0
- **Work:** The first run of the shell smoke test failed with RenderFlex
  overflows of 87, 43, and 86 pixels: `DropdownButtonFormField` sizes its
  inner `Row` from untruncated content, and the fixed-width toolbars in the
  TOC Manager and PDF Reader could not hold it. Every dropdown now sets
  `isExpanded: true` so the label ellipsizes inside the width it was given.
- **Done when:** The smoke test mounts the shell and walks all six views with
  no layout exception.
- **Evidence:** `test/app_smoke_test.dart` passes; the overflow was found by
  that test, which is the reason it exists.

### TODO-012 — Port the documentation the original keeps in `docs/` — DONE

- **Intent:** I1.5, I4.3
- **Priority:** P2
- **Work:** Covered by the seven guides now in `docs/`: architecture layering
  (`architecture.md`), bridge request/response and error table
  (`bridge-protocol.md`), map tile sources and usage policy
  (`map-sources.md`), and per-suite testing notes (`testing.md`).
- **Done when:** A contributor can answer "what shape goes over the bridge and
  what comes back" from a document, and the document names the file that
  implements it.
- **Evidence:** `docs/bridge-protocol.md` documents the `[[number, …]]`
  envelope and error codes naming
  `lib/core/metrics/summarize_bridge.dart`; `test/readme_test.dart` guards
  the `docs/README.md` index.

### TODO-003 — Flush the workspace when the app stops — DONE

- **Intent:** I1.3, I2.1
- **Priority:** P0
- **Evidence:** `AppLifecycleListener` (pause/hide/detach) in
  `lib/main.dart` calls `controller.flushNow()`; `WorkspacePersistence.dispose()`
  flushes a pending debounce instead of cancelling it. Locked by the
  dispose-flush test in `test/persistence_test.dart` (schedule, dispose without
  waiting, durable file exists). Full suite: 100/100, `flutter analyze` clean.

### TODO-004 — Make the save label truthful right after boot — DONE

- **Intent:** I2.3, I1.3
- **Priority:** P0
- **Evidence:** `hydrate()` sets `mode = PersistenceMode.native` on a
  successful restore. Locked by three tests in `test/persistence_test.dart`:
  restored → `saved to disk`, nothing to restore → `not saved` with no report,
  damaged file → `not saved` + `INVALID_CONTENT`.

### TODO-006 — Run the real binary once on a display and keep it repeatable — DONE

- **Intent:** I4.1, I2.4, I0.1
- **Priority:** P0
- **Evidence:** `tool/smoke.sh --build --timeout=10` builds the Linux debug
  bundle and runs it with isolated `XDG_DATA_HOME`/`XDG_CACHE_HOME`; verified
  2026-10-07 on display `:0` → `Smoke OK (exit=124)`. No-display case exits 3
  with a remediation message. Documented in `docs/development.md`.

### TODO-008 — Bound the tile client — DONE

- **Intent:** I1.6, I3.4, I3.2
- **Priority:** P1
- **Evidence:** `TileCache.tileHosts` is an explicit host list; `TileRequestGate`
  (`lib/core/map/tile_policy.dart`) caps 4 concurrent fetches with 100 ms
  spacing and exponential backoff on 429/5xx; disk cache capped at 2000 files /
  64 MiB with oldest-first eviction. Locked by 9 tests in
  `test/tile_policy_test.dart` and documented in `docs/map-sources.md`.

### TODO-009 — Close the durability gap against the C store — DONE

- **Intent:** I1.3, I4.3
- **Priority:** P1
- **Evidence:** Documented the weaker guarantee instead of implementing fsync
  (`dart:io` exposes neither file nor directory fsync): explicit power-loss
  statement in `lib/core/workspace/workspace_store.dart` and the README
  (crash-safe, power-loss may lose the last write). No document claims fsync
  durability — verified by grep over `docs/` and `README.md`.

### TODO-011 — Give the metrics core a surface or state it has none — DONE

- **Intent:** I1.4, I1.2
- **Priority:** P2
- **Evidence:** Decision recorded: portable library code with no UI caller.
  Stated in the README Notes, `docs/overview.md`, and `docs/bridge-protocol.md`;
  pyramid I1.4 marks it decided.

### TODO-013 — Decide the Google Maps viewer's fate — DONE

- **Intent:** I1.1, I4.4
- **Priority:** P3
- **Evidence:** Decision recorded: no view; the `googleMap` section is
  normalized and persisted for import compatibility only. Stated in the README,
  `docs/tools.md`, `docs/map-sources.md`, and pyramid I1.1.

### TODO-014 — Decide the Map Explorer's two open features — DONE

- **Intent:** I1.6, I1.1
- **Priority:** P3
- **Evidence:** Decision recorded: one basemap with a colour filter and no
  place search (a geocoder would be a second network client). Stated in the
  README Notes and pyramid I1.6; no UI claims either feature.
