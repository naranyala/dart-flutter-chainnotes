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

### TODO-016 — Reopen the remembered document and folder on restart

- **Intent:** I2.1, I1.1
- **Priority:** P1
- **Work:** A restart restores the record (PDF path, page, zoom, remembered
  lists; image folder, selected group, lightbox index; map viewport and
  places) but reopens neither the PDF document nor the image folder — the
  reader shows a `REMEMBERED` list instead. Either reload the remembered
  document/folder automatically (with the recorded page/zoom/group applied and
  a clear sentence when the file is gone), or record the decision to keep the
  manual pick and stop implying an automatic restore.
- **Done when:** After a restart with a remembered PDF and folder, the same
  document page and folder group are showing without a manual pick — or the
  README, the pyramid snapshot, and the views all state that the pick is
  manual, and the status lines say so.

### TODO-005 — See a green CI run for analyze, test, and the Linux build

- **Intent:** I1.5, I4.1, I4.3
- **Priority:** P1
- **Work:** `.github/workflows/ci.yml` already runs `flutter analyze`,
  `flutter test`, and `flutter build linux --debug` on Flutter 3.47.5, but it
  has never been observed green on GitHub. Push it, watch one run go green,
  and add the status badge (or a recorded run URL) to the README.
- **Done when:** A pull request that breaks a test or an analyzer rule is
  rejected by CI, and the badge/status matches a green run on a clean checkout.

### TODO-007 — Cover the remaining interaction flows

- **Intent:** I4.1, I2.2
- **Priority:** P1
- **Work:** `test/tools_interaction_test.dart` (12 tests) covers TOC, editor,
  links, places, and lightbox; `test/package_integration_test.dart` (14
  tests) covers picker flows via `FakeFileService` (TOC export/import, editor
  import/export, image directory, places CSV), locate via `FakeLocations`
  (denied, disabled, fix), and the PDF backend seam. Still thin: picker
  *cancel* paths (user dismisses the dialog) have no widget coverage.
- **Done when:** Cancel-path tests exist for at least the TOC import/export
  and PDF open flows, and `flutter test` remains the single command.

## P2 — Keep it maintainable and portable

### TODO-010 — Build the remaining declared platforms

- **Intent:** I4.3, I3.3, I4.4
- **Priority:** P2
- **Work:** Linux debug + release and web release build here, the macOS
  `Info.plist` carries the location usage string, and the README names the
  supported set. Still unbuilt here: Windows (needs a Windows host),
  macOS/iOS (need Xcode), and location exercised on
  a real device. The Android APK build was skipped (long, unattended); if it
  ships, build it and record it. Build each remaining target that ships and
  record it.
- **Done when:** Every platform listed as supported builds from a clean
  checkout, and the README names exactly those.

## P3 — Optional polish and open decisions

### TODO-015 — Measure release first-run latency
- **Intent:** I0.1, I2.4
- **Priority:** P3
- **Work:** The Linux release bundle builds (25 M) and its size is recorded in
  the README, but tree/shader warm-up behaviour on first launch was never
  measured. Launch the release bundle on a display, note startup behaviour,
  and record it.
- **Done when:** First-run latency of the release bundle is recorded in the
  README alongside the size.

### TODO-017 — Decide the Linux PDF rendering story

- **Intent:** I4.4, I4.3
- **Priority:** P2
- **Work:** `pdfx` ships native backends for Android, iOS, macOS, and Windows
  only — no Linux — and its `openFile` fires an unawaited platform assert that
  no caller-side `try/catch` can contain. `PdfSession` now goes through the
  `PdfOpener` seam (`lib/sessions/pdf_backend.dart`): unsupported platforms
  get `PDF rendering is not available on this platform.` without touching
  `pdfx`, outline parsing stays pure Dart everywhere, and fakes cover the
  open paths in `test/package_integration_test.dart`. Decide the product
  story for the primary platform: adopt a renderer with a Linux backend,
  shell out to a system viewer, or keep document-closed-on-Linux (headings and
  TOC import still work from parsed bytes) as the stated position.
- **Done when:** The README, the pyramid snapshot, and the PDF Reader agree on
  what opening a document does on Linux, and the chosen path has a test.

## Closed (with evidence)

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
