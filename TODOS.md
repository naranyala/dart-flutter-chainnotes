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

### TODO-003 — Flush the workspace when the app stops

- **Intent:** I1.3, I2.1
- **Priority:** P0
- **Work:** Today the engine writes on a 250 ms debounce and inside
  `WorkspaceApp.dispose`, which a desktop window close does not reliably reach:
  closing the window can discard the last burst of typing, and a
  `hasPendingSave` timer still in flight is cancelled by `dispose` without a
  final write. Register an `AppLifecycleListener` (or the platform-appropriate
  close hook) that calls `controller.flushNow()` on `paused`/`detached`, and
  make the pending debounce flush rather than drop when the app leaves.
- **Done when:** Typing a sentence and closing the window within the debounce
  window, then relaunching, shows the sentence — verified by a test that
  schedules a save and disposes the app object without waiting out the timer.

### TODO-004 — Make the save label truthful right after boot

- **Intent:** I2.3, I1.3
- **Priority:** P0
- **Work:** `WorkspacePersistence.mode` starts as `none`, so the status bar
  reads "not saved" on a fresh launch even when `hydrate` has just restored the
  workspace from disk. The label is answering "written this session" while the
  user reads "does it exist on disk". Set the mode from the hydrate result (a
  successful restore is `native`) and cover the three boot outcomes — restored,
  nothing to restore, restore failed — in a test.
- **Done when:** After a launch that restored a durable copy, the status bar
  says `saved to disk`; after a launch with no file it says `not saved`; after
  a rejected write it says `not saved` and the report pill carries the reason.

### TODO-006 — Run the real binary once on a display and keep it repeatable

- **Intent:** I4.1, I2.4, I0.1
- **Priority:** P0
- **Work:** `test/app_smoke_test.dart` mounts the shell headlessly, but nothing
  has executed `build/linux/x64/debug/bundle/chainnotes`: directory
  resolution, the first hydrate, the first tile request, and the first paint
  have never run. Add a script (for example `tool/smoke.sh`) that builds the
  Linux debug bundle, runs it under a virtual or real display for a bounded
  time, fails on a non-zero exit or a crash log line, and redirects
  `XDG_DATA_HOME`/`XDG_CACHE_HOME` into a temporary directory so a smoke run
  can never read or rewrite a real workspace.
- **Done when:** One documented command launches the actual application, exits
  0 within the timeout, and its absence of a display is reported as a precise
  remediation message rather than a hang.

## P1 — Make the workspace dependable

### TODO-005 — Run analyze, test, and the Linux build in CI

- **Intent:** I1.5, I4.1, I4.3
- **Priority:** P1
- **Work:** There is no `.github/workflows` (or equivalent) in the tree, so
  nothing enforces the three commands the README promises. Add a workflow that
  runs `flutter analyze`, `flutter test`, and `flutter build linux --debug` on
  a pinned Flutter version matching `pubspec.yaml` (`sdk: ^3.13.4`).
- **Done when:** A pull request that breaks a test or an analyzer rule is
  rejected by CI, and the badge/status matches a green run on a clean checkout.

### TODO-007 — Test the tools at the interaction level

- **Intent:** I4.1, I2.2
- **Priority:** P1
- **Work:** Only the shell smoke test exercises the views. Add widget tests
  for the paths users depend on: declaring, reordering, undoing, and
  exporting a section in the TOC Manager; the editor's draft binding to the
  active item; attaching a PDF page and importing headings; the lightbox
  keyboard navigation; saving, renaming, and removing a place; and the error
  sentences for a missing title, a non-outline import, and a denied location
  permission.
- **Done when:** Each of those flows has a test that fails when the flow
  breaks, and `flutter test` remains the single command that runs them.

### TODO-008 — Bound the tile client

- **Intent:** I1.6, I3.4, I3.2
- **Priority:** P1
- **Work:** `lib/core/map/tile_source.dart` fetches from one hardcoded host
  with no rate limit, no backoff on failure, and no size cap or eviction for
  the disk cache (it grows without bound), while the memory side is a
  512-tile LRU with no relationship to that disk usage. Add a bounded disk
  cache with eviction, a small concurrency/rate limit with backoff on
  429/5xx, and make the host list an explicit constant so adding a second
  source is a deliberate edit.
- **Done when:** A burst pan cannot exceed the configured request rate, a
  failing host is retried with backoff instead of hammered, and the disk cache
  stays under its cap with the oldest tiles evicted.

### TODO-009 — Close the durability gap against the C store

- **Intent:** I1.3, I4.3
- **Priority:** P1
- **Work:** `WorkspaceStore.save` writes the temp file, `flushSync`s it, and
  renames it — but does not `fsync` the file before the rename nor the
  directory after it, which is what the original `src/workspace_store.c`
  guarantees. Either implement the stronger ordering (platform `fsync` on the
  file and on the parent directory) or document, in the code and the README,
  the weaker guarantee the Dart store actually provides.
- **Done when:** Either a test or a documented statement makes the power-loss
  behaviour of a save explicit, and no document claims fsync durability the
  store does not perform.

## P2 — Keep it maintainable and portable

### TODO-010 — Build and verify the platforms that are declared

- **Intent:** I4.3, I3.3, I4.4
- **Priority:** P2
- **Work:** Only `flutter build linux --debug` has been run. Windows, macOS,
  Android, and iOS targets exist in the tree with plugin dependencies
  (`file_selector`, `geolocator`, `pdfx`, `path_provider`) that are unverified
  there, and macOS ships no location usage string at all. Build each target,
  add the macOS `Info.plist` usage descriptions if that target ships, and
  record which platforms are actually supported in the README.
- **Done when:** Every platform listed as supported builds from a clean
  checkout, and the README names exactly those.

### TODO-011 — Give the metrics core a surface or state it has none

- **Intent:** I1.4, I1.2
- **Priority:** P2
- **Work:** The Welford engine and the bridge envelope are ported and tested
  (`test/metrics_test.dart`, `test/bridge_test.dart`) but no view calls them —
  the same gap the original records for `summarize`. Either expose the engine
  through a small tool in the menu grid, or state in the README that it is
  portable library code carried for parity with the original.
- **Done when:** A reader can tell from the documentation whether the metrics
  engine is a product feature, and the answer matches the tree.

### TODO-012 — Port the documentation the original keeps in `docs/`

- **Intent:** I1.5, I4.3
- **Priority:** P2
- **Work:** The original documents its architecture, bridge protocol, map
  sources, and testing strategy under `docs/`; this project has a README plus
  these two documents, so the bridge envelope and error codes are only
  discoverable by reading `lib/core/metrics/summarize_bridge.dart`. Write the
  equivalent notes (architecture layering, bridge request/response and error
  table, map tile sources and usage policy, how to run each test suite).
- **Done when:** A contributor can answer "what shape goes over the bridge and
  what comes back" from a document, and the document names the file that
  implements it.

## P3 — Optional polish and open decisions

### TODO-013 — Decide the Google Maps viewer's fate

- **Intent:** I1.1, I4.4
- **Priority:** P3
- **Work:** The `googleMap` section of the record is normalized and persisted
  but has no view. Decide whether to port the viewer (which in the original
  uses an unlicensed tile endpoint — see the source project's own warning),
  to keep the field purely for import compatibility, or to drop it from the
  schema in a versioned way.
- **Done when:** The README and the schema agree, and a workspace from the
  original either loads as intended or says why it cannot.

### TODO-014 — Decide the Map Explorer's two open features

- **Intent:** I1.6, I1.1
- **Priority:** P3
- **Work:** The Explorer has a colour filter over one basemap, not a basemap
  switcher, and there is no place search anywhere in the tree — deliberately,
  because a geocoder would be a second network client behind a new seam. Record
  the decision: keep as is, or specify the transport for search and the source
  list for a switcher before any UI is written.
- **Done when:** The pyramid entry for I1.6 and the README state the decision,
  and no UI claims a feature that does not exist.

### TODO-015 — Release build and size pass

- **Intent:** I0.1, I2.4
- **Priority:** P3
- **Work:** Only a debug Linux bundle has been built. Produce a release build,
  note the bundle size and startup behaviour, and check that the tree/shader
  warm-up path does not regress first-run latency.
- **Done when:** A release bundle is built by a documented command and its
  size and first-run behaviour are recorded in the README.

## Closed during the port

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
