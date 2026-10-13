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

TODO-028–TODO-030 closed with evidence below.

## P1 — Make the workspace dependable

TODO-031–TODO-033 closed with evidence below.

### TODO-034 — Fix tile cache LRU, UI-thread IO, backoff, dateline keys

- **Intent:** I1.6, I3.2, I3.4
- **Priority:** P1
- **Work:** `TileCache.tile()` (`lib/core/map/tile_source.dart:52-54`) never promotes in `_order` so eviction (`:71-78`) is FIFO not LRU; `_readBytes`/`_enforceDiskBounds` (`:103,151,162-176`) run `existsSync/listSync(recursive)/lengthSync/stat/deleteSync` on the UI isolate per tile; `TileRequestGate.onError (:64-66)` never touches backoff and `onResult` ignores non-429/5xx/200 so 404s poison the failure counter and timeouts never back off (`lib/core/map/tile_policy.dart:47-66`); tile key uses raw `x` instead of `wrappedX` (`lib/core/map/projection.dart:132-144`) → permanent dateline misses.
- **Done when:** Recently-used tiles survive eviction; disk bounds enforced off the UI thread (or bounded); timeouts back off and 404s don't escalate; dateline tiles hit cache. Locked by cache/policy unit tests.

### TODO-035 — Fix map/geo parsing and formatting

- **Intent:** I1.6, I2.3
- **Priority:** P1
- **Work:** `Polygon` GeoJSON (`lib/sessions/map_session.dart:637-640`) wraps `ring(coordinates)` one level shallow → every valid Polygon errors; CSV detector (`:513-514`) only `lat`+`lon|lng`, missing `latitude`/`longitude`/`long` and BOM (`\uFEFFlat`); `bearingDegrees(A,A)` returns 0 not null and `formatDistance(999.6)` → `1000 m` / `0.004` → `0 cm` (`lib/core/geo/geo.dart:92-111`); `normalizeLocation` accepts `lat=90` but renderer clamps to 85.05 with no warning (`geo.dart:55-61` + `projection.dart:42-51`); map flight (`lib/ui/map_view.dart:142-157`) lerps longitude linearly across the dateline.
- **Done when:** Valid Polygon draws; latitude/longitude/long+BOM CSVs import; coincident-point bearing is null, 999.6 m formats as km; pole places warn or clamp visibly; +179°→−179° flies 2° not 358°. Locked by session/geo tests.

### TODO-036 — Close persistence portability and writer gaps

- **Intent:** I1.3, I4.3
- **Priority:** P1
- **Work:** `WorkspaceStore.save` (`lib/core/workspace/workspace_store.dart:90-99`) uses `renameSync` over existing target (throws on Windows → every save after the first fails); `persist()/flush()` (`workspace_persistence.dart:137-175`) return cache result not durable result; `formatBridgeDouble` (`metrics_engine.dart:128-133`) calls `toInt()` for `|v|<1e21` but int64 max is ~9.2e18 (`summarize([1e20])` throws/wraps); outline writer (`outline_pdf_writer.dart:48-50,142-144`) exceeds its 120-char cap (124), overwrites silently, accepts `directory=''` → `/name` (fs root).
- **Done when:** Save overwrites atomically on Windows; flush return reflects durable outcome; 1e20 formats without throw; writer caps names, refuses overwrite or documents it, rejects empty dir. Locked by store/bridge/writer tests.

### TODO-037 — Fix picker error handling, permission forever, export names

- **Intent:** I2.2, I3.4, I3.3
- **Priority:** P1
- **Work:** `chooseFile/choosePath` (`lib/app/services.dart:32-55`) swallow platform exceptions as null (callers treat as silent cancel); `chooseDirectory (:12-14)` has no try (escapes `_combineToPdf`, try only around renderer); `MapSession` locate (`map_session.dart:298-302`) lumps `deniedForever` with transient deny (infinite retry, no settings guidance); `suggestFileName (:111-122)` allows trailing dot/space and leading-dot hidden files (`"My Report. "` → `"My Report..json"`).
- **Done when:** Picker errors surface a status sentence distinct from cancel; directory-picker throw is caught; deniedForever directs to settings; export names strip trailing dots/spaces and leading dots. Locked by widget/unit tests.

### TODO-045 — Fill core model/store/persistence test gaps

- **Intent:** I4.1, I3.2
- **Priority:** P1
- **Work:** `workspace_test` misses `asZoom` NaN/Inf→1.1 + 0.6 floor, `asPage` truncation/Inf/string, `asString` limits, 64-image/80-label/4096-path caps, `normalizePlace` auto-id/`createdAt`/lon-wrap/1e6-rounding/`lon>180`, map sidebar/cursor/filter defaults, `version→1`; `store_test` has tautology message loop, ASCII-only cap, untested `path.isEmpty`/symlink/`ensureDirectory`/`parentOf('/f')`/TOCTOU growth; `persistence_test` never reaches `userInteracted` via engine (hardcoded false), `_lastDurablePayload` dedup, `onFailure` both-fail, `onChanged`, `clearSaveReport` scope, `WRITE/READ_FAILED` codes, `clock` injection, empty-string durable.
- **Done when:** Each branch above has a unit test; tautology loops assert real mappings. Locked by expanded suites.

### TODO-046 — Fill metrics/bridge/tile test gaps

- **Intent:** I4.1, I4.2
- **Priority:** P1
- **Work:** `metrics_test` misses `count==i64max`, `nextMean/M2` overflow (only sum path covered), tiny-negative `M2` clamp, `summarize` overflow→null, `writeSummaryJson/formatBridgeDouble` (incl. 1e20 `toInt` overflow); `bridge_test` misses `\r` separator, `ENGINE_FAILED` via overflow, lone `+/-/1e/.5`, `INF/NAN/+NaN`, `jsonString` escapes, whitespace-only tail; `tile_policy_test` misses `maxBackoffMs` cap, `onError`/underflow, non-429 4xx; `tile_cache_test` misses gate-closed miss, timeout→`onError`, empty-disk fallthrough, poisoned-disk refetch, `_inflight` dedup, UA/URL.
- **Done when:** Each branch above has a unit test. Locked by expanded suites.

### TODO-047 — Fill widget/integration path gaps

- **Intent:** I4.1, I2.2
- **Priority:** P1
- **Work:** `tools_interaction` has 1 editor + 1 PDF widget test, most map/attach/import controller-only; missing image-dir/map-file cancel widgets, export-failure (`writeTextFile==false` unrepresentable in `FakeFileService`), attach-failure/cap paths, editor cursor, lightbox zoom/pinch/keys, dateline/`Polygon`, CSV variants (quoted/headerless/`;`/caps); `package_integration` misses cancel variants, CSV aliases, GeoJSON-via-import, PDF null-render/zero-byte/passworded; `FakeFileService` falls through to real FS for unlisted paths and `FakeEnginePage.renderBytes` is always null.
- **Done when:** Cancel/failure/cap/CSV/GeoJSON/editor-cursor paths have widget tests; fakes support failure injection without real-FS fallthrough. Locked by expanded suites.

TODO-005, TODO-007, and TODO-016 closed with evidence below.

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

TODO-018–TODO-022 (frontend interaction polish) closed with evidence below.

### TODO-038 — Fix editor sync, lightbox zoom, badges, stale selections

- **Intent:** I2.1, I2.3
- **Priority:** P2
- **Work:** Editor post-frame sync (`lib/ui/editor_view.dart:68-86`) applies stale `wantText` and forces cursor to end, queuing multiple callbacks; lightbox `_zoom` (`lib/ui/images_view.dart:429-499`) never resets on step (next image opens zoomed); menu badges (`lib/ui/menu_view.dart:89-90` vs `:73,79,85`) listen to controller only, missing session notifies; unknown image group (`image_session.dart:63-83`) shows All with stale badge; `removePlace/clearPlaces` (`workspace_controller.dart:558-561`) leave dangling `MapSession.selectedPlaceId`; TOC row `_iconButton` is 40×40 vs shared 48×44 (`toc_view.dart:734-750`); TOC Preview (`toc_view.dart:328-336`) pre-writes `pdf.path/name` before `openAt` overwrites.
- **Done when:** Typing during section switch isn't clobbered and cursor preserved; lightbox step resets zoom; badges update without view switch; unknown group resets to All; remove clears selection; row buttons meet 44px; preview drops redundant pre-write. Locked by widget tests.

### TODO-042 — Broaden CI, lint, smoke, and docs guard

- **Intent:** I4.1, I4.3
- **Priority:** P2
- **Work:** CI (`.github/workflows/ci.yml:29-35`) runs only analyze+test+linux-debug (no release, no web, single runner, no smoke); `analysis_options.yaml` is default lints, excludes platform dirs, bare `flutter analyze`; `tool/smoke.sh:18` `shift` inside `for` ignores `--timeout 12` space form, timeout docs disagree (=12 vs =10), log deleted on success, 40-line tail, `grep failed` false-positives; `readme_test.dart:104-108` only guards lines starting with `flutter ` (inline release/web builds + smoke flags bypass).
- **Done when:** CI covers release + web or documents why not; lint set tightened or exclusion justified; smoke space-form timeout works and log preserved on success; guard covers inline commands or known exceptions listed.

### TODO-043 — Fill coverage and platform-doc gaps

- **Intent:** I4.1, I3.3
- **Priority:** P2
- **Work:** No direct `geo`/`projection` tests (only indirect via sessions/views); `FakeLocations` duplicated in `package_integration_test.dart:32` instead of shared `fakes.dart`; `theme_test.dart` skips Fuchsia though `theme.dart:38-44` maps it; permission tables (`development.md:109-110`, `map-sources.md:130-132`) list Android+iOS only, omitting macOS present in both `Info.plist`s and README.
- **Done when:** Direct geo/projection cases exist; location fakes shared; Fuchsia pinned or explicitly out of scope; permission tables include macOS.

### TODO-048 — Harden smoke/boot/theme/docs-guard suites

- **Intent:** I4.1
- **Priority:** P2
- **Work:** `app_smoke` mounts empty workspace only, switches via `selectView` not nav taps, no per-tool content/failure pill/resize cases; `boot_reopen` has no widgets and misses `supported:false`/corrupt-bytes/empty-between-boots/page-beyond-count/dual-failure; `theme_test` pins splash-factory only (no colors/type/contrast/widget conformance); `readme_test` misses prose/version/flag drift, non-`flutter ` commands, extra `development.md` commands, external URLs, section placement; timing hazards (`persistence` 330ms vs 250ms debounce, `tile_cache` 150ms vs 100ms gate, map `pump(100ms)` == spacing, lightbox 300ms decode, dialog 100/300ms magic numbers, zero `pumpAndSettle`) rely on wall-clock margins; widget tests doing real async I/O (e.g. `PdfSession.openAt` in the chip test) deadlock in the fake-async zone unless wrapped in `tester.runAsync` — no test or doc states this rule.
- **Done when:** Smoke covers one per-tool content + failure pill; reopen covers corrupt/unsupported/dual-failure; theme pins tokens or scopes out; guard covers inline commands or lists exceptions; timing-sensitive tests use fake clocks/settle or document margins; async-I/O widget tests use `runAsync` (and `docs/testing.md` says so). Locked by expanded suites.

### TODO-049 — Fix editor ListTile without a Material ancestor

- **Intent:** I2.3, I4.1
- **Priority:** P2
- **Work:** `EditorView` renders outline rows as bare `ListTile` inside the card `Container` (`lib/ui/editor_view.dart:206-234`). Pumping the bare `WorkspaceShell` with a TOC item throws the framework's "ListTile background color or ink splashes may be invisible" assertion (found via the TODO-033 back-cancel test, which had to drop `EditorView` from its view list to pass). In release the assertion strips and ink splashes paint invisibly; in debug it blocks any widget test that mounts the editor with items outside a `Scaffold`.
- **Done when:** Pumping the bare shell with a TOC item throws no framework assertion (wrap the list in an explicit `Material` or replace `ListTile` with a custom row); ink ripples remain visible on touch platforms. Locked by restoring `EditorView` to the back-cancel smoke test's view list.

## P3 — Optional polish and open decisions

TODO-015, TODO-023, TODO-025–TODO-027, TODO-039–TODO-041, TODO-044 closed
with evidence below; TODO-024, TODO-038, TODO-042, TODO-043, TODO-048,
TODO-049 are the open polish items.

### TODO-024 — Label the interface for screen readers

- **Intent:** I2.2
- **Priority:** P3
- **Work:** The only `Semantics` in the app is `StatusLine`. Images have no
  `semanticLabel`, icon-only buttons lean on tooltips mobile readers often
  skip, and canvas markers expose nothing. Add image labels,
  `Semantics(button:)` on markers, and header semantics — incrementally,
  tool by tool.
- **Done when:** Each tool's main regions and actions announce a name; no
  behavior changes.

## Closed (with evidence)

### TODO-028 — Fix PDF reader page-state loss and scroll crash — DONE

- **Intent:** I2.1, I2.3, I3.1
- **Priority:** P0
- **Evidence:** `_onScroll`/`_goToPage` persist only through `navigateToPage` (direct record writes removed); `_scrollToPage` guards `hasClients`; `_openText` merged into `_openPdf` (single open path); init clamps to the open page count; `_PdfPage` takes the document id and refreshes on doc change; `renderPage` cache keys page+pixel size; failed opens reset to fully closed. Six new tests (failed-open reset, size-keyed cache, scroll persists incl. `hasPendingSave`, no-crash open, no-jump on status notify, doc-switch re-render via `getPageCalls`). Full suite: 189/189, `flutter analyze` clean.

### TODO-029 — Fix PDF outline parser truncation and DoS fan-out — DONE

- **Intent:** I3.2, I4.1
- **Priority:** P0
- **Evidence:** Siblings share the depth budget, both walks carry a `visited` set, keys match only outside literals with boundary checks (compact `/Type/Outlines` still parses), `dictValue` returns full `N G R` refs (previously truncated to `N`, so outlines never resolved), `titleValue` drops the opening paren, explicit `/Dest` arrays and indirect `/Kids` arrays resolve. New `test/pdf_outline_test.dart` (6 tests: 40 siblings, cycle, two literal traps, compact dicts, page numbers `One@1,Two@2`). Full suite: 189/189, `flutter analyze` clean.

### TODO-030 — Fix snapshot aliasing, duplicate TOC ids, attach round-trip — DONE

- **Intent:** I1.3, I3.1, I3.2
- **Priority:** P0
- **Evidence:** New `copy()` on `TocItem`/`Place`/session-data classes; `snapshot()` and `apply()` deep-copy both directions; `normalizeTocItems` dedups by id and imports rebuild colliding ids; `attachPdfPage` clamps to ≥1 and `attachLocation` stores the normalized form. Five new tests (snapshot isolation both directions, crafted-id import, page-0 round-trip, location normalization round-trip, toc dedup). Full suite: 189/189, `flutter analyze` clean.

### TODO-031 — Fix image open failures leaving stale grids — DONE

- **Intent:** I2.2, I2.1
- **Priority:** P1
- **Evidence:** `ImageSession.openAt` bad-folder path now calls `controller.forgetImageDirectory(path)` (status via `setStatus` already notifies); empty-folder path now resets to an explicitly empty grid (`images/groups` cleared, folder name kept) instead of leaving the previous folder's grid. Two new tests in `test/package_integration_test.dart` (missing folder prunes the remembered entry; empty folder clears a previous grid). Full suite: 172/172, `flutter analyze` clean.

### TODO-032 — Surface attach failures instead of silent no-ops — DONE

- **Intent:** I2.2, I1.1
- **Priority:** P1
- **Evidence:** `attachPin/PlaceToSection` set `could not be attached` on save failure; PDF `_attachPage` reports `Open a PDF to attach its page` when closed and `could not be attached` on save failure; `attachCurrentToSection` reports `Select an outline item…` with no target and `could not be attached` on save failure. Two new tests in `test/tools_interaction_test.dart` (failed map attach reports; image attach without target explains itself). Full suite: 172/172, `flutter analyze` clean.

### TODO-033 — Reconcile link-target fallback, editor chips, back behavior — DONE

- **Intent:** I1.1, I2.3, I2.2
- **Priority:** P1
- **Evidence:** All three attach dropdowns show `linkTarget?.id` (the effective target) instead of `linkTargetId`; `EditorView` takes optional `pdf`/`map` sessions (wired in `main.dart`) and its chips `navigateToPage`/`flyTo` like the TOC chips, falling back to view-switch without sessions; place-rename flag moved from view-local state to `MapSession.renamingPlaceId` and `WorkspaceShell` takes an optional `mapSession` so back cancels TOC edit then place rename before leaving the tool. Two new tests (`PDF chip jumps to the linked page`, also locking `tester.runAsync` for real async I/O in widget tests; `back cancels inline edits before leaving the tool`). Full suite: 172/172, `flutter analyze` clean.

### TODO-039 — Defer reopen work off first frame — DONE

- **Intent:** I2.4, I2.1
- **Priority:** P2
- **Evidence:** `main()` now calls `runApp` first then `unawaited(reopenRemembered(...))`; `reopenRemembered` splits into `_reopenPdf`/`_reopenImages` run via `Future.wait` (independent sessions/fields) instead of sequential awaits. Same restore/gone-file semantics; existing `test/boot_reopen_test.dart` (5) passes unchanged. Full suite: 166/166, `flutter analyze` clean.

### TODO-040 — Resolve docs that contradict closed work — DONE

- **Intent:** I1.5, I2.4
- **Priority:** P2
- **Evidence:** README Known gaps drops TODO-003/004 bullets; `tools.md` quirk rewritten as implemented (`saved to disk` after restore), TODO-016 marked closed, TODO-013 marked closed decision; `map-sources.md` TODO-013 marked closed; `development.md` TODO-003 marked closed; pyramid gaps list replaced (TODO-007/016/017 removed, TODO-028–044 referenced). `readme_test.dart` 8/8 green.

### TODO-041 — Fix test-count and bundle-size drift in docs — DONE

- **Intent:** I1.5, I4.1
- **Priority:** P2
- **Evidence:** `tools_interaction` 34→36 (after 2 new TODO-044 tests), `workspace_store` 13→14, `boot_composition` 3→4, `overview` 125→158 feature, `development` nine→thirteen suites and 25M/10-07→33M/10-09 with PDFium note, testing table adds `tile_cache` (5), pyramid 164→166. Verified by `grep -c test(` (36 file, 166 total). `readme_test.dart` green.

### TODO-044 — Fix place-label and heading-dedup data loss — DONE

- **Intent:** I2.3, I1.1
- **Priority:** P2
- **Evidence:** `addPlace` re-top now adopts new non-empty label (clamped to 80); `importPdfHeadings` dedup includes `pdfName`. Two new tests in `test/tools_interaction_test.dart` (same headings from a.pdf vs b.pdf both import; re-save adopts New). Full suite: 166/166, `flutter analyze` clean.

### TODO-023 — Use one feedback channel for input errors — DONE

- **Intent:** I2.2
- **Priority:** P3
- **Evidence:** `_declare()` in `lib/ui/toc_view.dart` no longer shows a
  `SnackBar`; the toolbar `StatusLine` (`toc-manager-status`) is the only
  channel. `test/tools_interaction_test.dart` asserts an empty declare leaves
  `tocItems` empty, sets the `heading title` status sentence, finds no
  `SnackBar`, and finds the status line. Full suite: 164/164,
  `flutter analyze` clean.

### TODO-025 — Unify icon glyph sizes — DONE

- **Intent:** I0.1
- **Priority:** P3
- **Evidence:** all small action glyphs set to 16 px (`toc`, `editor`,
  `pdf`, `images`, `map`, `menu`, `widgets` menu-grid `iconSize` 20→16,
  explicit 16 on previously unsized icons). Intentional display exceptions
  kept: 56 px TOC empty-state, 26 px map pin, 36 px lightbox chevrons.
  Verified with `rg "size:|iconSize:" lib/ui lib/app` — no 13/15/18 remains.
  Full suite: 164/164, `flutter analyze` clean.

### TODO-026 — Floor small type at 12 px on narrow windows — DONE

- **Intent:** I0.1
- **Priority:** P3
- **Evidence:** raised every 10.5/11/11.5 px style (TOC chips/levels/hints,
  editor badges/status, shell save-mode/view-label/report pill, map
  attribution/readouts/scale-bar/leg/coords, images counts/names, `Eyebrow`)
  to 12 px, so `rg "fontSize: 10.5|fontSize: 11" lib/` is clean and no text
  below 12 px can render at any width. Full suite: 164/164,
  `flutter analyze` clean.

### TODO-027 — Lift muted-text contrast — DONE

- **Intent:** I0.1
- **Priority:** P3
- **Evidence:** `WorkspaceColors.textMuted` `#8B919C` → `#9AA0AB` in
  `lib/app/theme.dart`. Measured contrast: 5.15:1 → 6.21:1 on `#1D2026`
  (4.79→5.77 on `#22262E`, 4.98→6.0 on `#1F232A`), so ≥4.5:1 on all
  surfaces while still reading as secondary. Full suite: 164/164,
  `flutter analyze` clean.

### TODO-018 — Restore press feedback on touch screens — DONE

- **Intent:** I2.2
- **Priority:** P2
- **Evidence:** `lib/app/theme.dart` gates `splashFactory` on the platform
  (`InkSparkle` on Android/iOS/Fuchsia, `NoSplash` on desktop); new
  `test/theme_test.dart` pins ripple on touch and flat on Linux/macOS/
  Windows.

### TODO-019 — Bring small touch targets up to 44 px — DONE

- **Intent:** I2.2
- **Priority:** P2
- **Evidence:** map markers gained a 44 px minimum height (anchor recentered
  on the point) and place-row title buttons a `Size(48, 44)` minimum; a
  widget test measures both at ≥44 px tall. Full suite green.

### TODO-020 — Set mobile keyboard actions on every field — DONE

- **Intent:** I2.2
- **Priority:** P2
- **Evidence:** Done on the TOC title/rename fields, Search on the TOC
  filter, Next/Done on the latitude/longitude pair (keys added where
  missing); widget tests read each action off the keyed fields.

### TODO-021 — Swipe between lightbox images — DONE

- **Intent:** I2.2
- **Priority:** P2
- **Evidence:** a raw-pointer `Listener` (opaque, non-competing) steps past
  a 60 px single-finger drag unless zoomed or pinching, via the unit-tested
  `lightboxSwipeStep`; a fling widget test steps 0→1. The work also fixed a
  real layout bug the test caught: `InteractiveViewer` collapsed to 0×0
  under the dialog's loose constraints, so the viewer now owns a fixed
  viewport-relative box with the image fitted (`contain`).

### TODO-022 — Guard bulk destructive actions — DONE

- **Intent:** I2.2, I3.2
- **Priority:** P2
- **Evidence:** `Clear` places and `Clear` layers ask first (`Cancel` keeps
  everything, `Clear` empties); widget tests drive both paths. Single-item
  removes stay one tap.

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
