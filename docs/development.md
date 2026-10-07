# Development guide

## Prerequisites

| Need | Version / notes |
| --- | --- |
| Flutter SDK | **3.47.x stable** (the project was built and verified on 3.47.5, framework revision `6a19cca564`) |
| Dart SDK | **3.13.4**, pinned by `environment: sdk: ^3.13.4` in `pubspec.yaml` |
| Desktop toolchain for `linux` | CMake ≥ 3.13, Ninja or Make, a C++ compiler, GTK 3 development files |
| Git | Any recent version |
| Network | Only for `flutter pub get`, and for tiles at runtime |

Android, iOS, macOS, Windows, and Web scaffolding directories exist — they
were generated with the project — but **Linux desktop is the only target
this project has been built and verified on.** Treat the others as unproven;
see [testing](testing.md#what-is-not-tested).

```sh
flutter pub get
```

## The commands

Run everything from the repository root.

| Command | What it does |
| --- | --- |
| `flutter pub get` | Install dependencies (`path_provider`, `file_selector`, `http`, `image`, `pdf`, `pdfx`, `geolocator`) |
| `flutter analyze` | Static analysis with `analysis_options.yaml`. **Must be clean — no warnings, no infos** |
| `flutter test` | Run all seven suites (67 tests) |
| `flutter test test/bridge_test.dart` | Run one suite while iterating |
| `flutter test --reporter expanded` | Same run, one line per test |
| `flutter run -d linux` | Launch on a display with hot reload |
| `flutter build linux --debug` | Bundle a debug build |
| `flutter build linux --release` | Bundle a release build |
| `flutter devices` | List connected targets |
| `flutter config --enable-linux-desktop` | Re-enable desktop targets if they are missing |

### Where the output lands

```text
build/linux/x64/debug/bundle/chainnotes        # debug binary and assets
build/linux/x64/release/bundle/chainnotes       # release binary and assets
build/                                          # git-ignored
```

The desktop entry point is `linux/`; the widget tree starts at
`lib/main.dart`.

## Project layout

```text
lib/
  app/         controller, theme tokens, file services
  core/        widget-free domain code: geo, map, metrics, pdf, workspace
  sessions/    per-tool transient state (pdf, image, map)
  ui/          views: shell, menu, toc, editor, pdf, images, map, widgets
  main.dart    composition root: directories, boot cache, persistence, runApp
test/          seven suites
docs/          the guides you are reading
PYRAMID-OF-INTENTS.md   the constraints a change must respect
TODOS.md                the backlog, linked to those intents
```

The layering rule — views own input, core owns validation, state, and
persistence — and the reasoning behind it are in
[architecture](architecture.md).

## Typical workflow

1. Read the intent pyramid before changing behaviour. If your change breaks an
   intent, say so in the change rather than bending the intent silently.
2. Write or extend a test in `lib/core`'s matching suite first.
3. Make the change, keeping the dependency direction (ui → sessions → app →
   core) intact.
4. `flutter analyze` and `flutter test` must both be clean before you consider
   the change done.
5. If behaviour changed, update the guide in `docs/` and any command or path
   quoted in `README.md` in the same change.

## Troubleshooting

**`flutter analyze` reports errors in a view.** Most of the common ones are
fixed already (async `save()` results, `getSaveLocation` instead of
`saveFile`, `math.log(x)/math.ln2` for `log2`, missing imports). If a widget
overflows horizontally, the fix is to stop constraining it with a `Column`
inside an unbounded `Row`, not to ignore the warning — `test/app_smoke_test.dart`
catches those on all six views.

**A test fails only in one file.** Run that file alone with
`flutter test test/<name>_test.dart`; the reporter names the case. If it fails
only when the whole suite runs, look for shared state between tests.

**`flutter run -d linux` reports no devices.** Run
`flutter config --enable-linux-desktop`, and confirm the GTK dev packages are
installed.

**The build fails inside a plugin.** Delete `build/` and `.dart_tool/`, then
`flutter pub get`. All six dependencies are pure Dart or have Linux support;
there is no native code of ours in the build.

**Tiles do not load.** See [map sources](map-sources.md#troubleshooting): the
host, the user agent, and the proxy/VPN case are all documented there.

**Location does nothing.** `MapSession.locate()` requests permission through
`geolocator`; a denial is reported in the tool status, not thrown. The Android
manifest already carries `INTERNET` plus coarse and fine location permissions,
and the iOS `Info.plist` carries `NSLocationWhenInUseUsageDescription`.

**The app closed and something was unsaved.** Known issue: nothing flushes on
window close, so edits made inside the 250 ms debounce window can be lost.
[TODO-003](../TODOS.md) tracks it.

## Things this project deliberately does not do

- No hot-reload-sensitive global singletons: state hangs off `runApp`'s
  composition root in `main()`.
- No `setState` that a controller could do: if two widgets need the same value,
  it belongs in `WorkspaceController`.
- No platform-specific code in `lib/`. `android/`, `ios/`, and friends exist to
  let Flutter build there, and were not hand-edited beyond permissions.
