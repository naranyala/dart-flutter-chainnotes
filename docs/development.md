# Development guide

## What you need

| Need | Version / notes |
| --- | --- |
| Flutter SDK | **3.47.x stable** (built and checked on 3.47.5, framework revision `6a19cca564`) |
| Dart SDK | **3.13.4**, from `environment: sdk: ^3.13.4` in `pubspec.yaml` |
| Linux desktop toolchain | CMake ≥ 3.13, Ninja or Make, a C++ compiler, GTK 3 dev files |
| Git | Any recent version |
| Network | Only for `flutter pub get`, and for map tiles while running |

Folders for Android, iOS, macOS, Windows, and Web are there, but only some
have actually been built.
**Built here:** Linux debug + release and Web release. Windows, macOS,
Android, and iOS were not built here (Windows needs a Windows machine,
macOS/iOS need Xcode, Android needs the SDK). Treat anything unbuilt as
unproven; see [testing](testing.md#what-is-not-tested).

```sh
flutter pub get
```

## Commands

Run these from the project root.

| Command | What it does |
| --- | --- |
| `flutter pub get` | Fetch packages (`path_provider`, `file_selector`, `http`, `pdf`, `pdfx`, `geolocator`) |
| `flutter analyze` | Static analysis with `analysis_options.yaml`. **Should come back clean** |
| `flutter test` | Run everything (107 feature tests, 115 total with the docs guard) |
| `flutter test test/bridge_test.dart` | Run a single suite while you're working |
| `flutter test --reporter expanded` | Same run, one line per test |
| `flutter run -d linux` | Run on your machine with hot reload |
| `flutter build linux --debug` | Make a debug bundle |
| `tool/smoke.sh --build --timeout=12` | Build then run the real app for 12 s with throwaway XDG folders; exit 124 (timeout) means it stayed up |
| `flutter build linux --release` | Make a release bundle |
| `flutter devices` | List available targets |
| `flutter config --enable-linux-desktop` | Turn desktop targets back on if they're missing |

### Where builds go

```text
build/linux/x64/debug/bundle/chainnotes        # debug app and assets (126 M bundle, 2026-10-07)
build/linux/x64/release/bundle/chainnotes       # release app and assets (25 M bundle, 2026-10-07)
build/web/                                      # web release (41 M, 2026-10-07)
build/                                          # ignored by git
```

The desktop entry point is `linux/`; widgets start at `lib/main.dart`.

## Layout

```text
lib/
  app/         controller, theme, file pickers
  core/        plain Dart: geo, map, metrics, pdf, workspace
  sessions/    per-tool state that isn't saved (pdf, image, map)
  ui/          views: shell, menu, toc, editor, pdf, images, map, widgets
  main.dart    startup: folders, boot cache, saving, runApp
test/          nine suites (feature tests + docs guard)
docs/          the guides you're reading
PYRAMID-OF-INTENTS.md   the rules a change should respect
TODOS.md                what's left, linked to those rules
```

The layering idea — views take input, core decides and saves — is explained
in [architecture](architecture.md).

## Usual workflow

1. Skim the intent pyramid before changing behaviour. If your change breaks a
   rule there, say so in the change instead of quietly bending it.
2. Add or extend a test in the matching `lib/core` suite first.
3. Make the change, keeping the direction (ui → sessions → app → core).
4. `flutter analyze` and `flutter test` should both pass before you call it
   done.
5. If behaviour changed, update the guide in `docs/` and any command or path
   in `README.md` in the same change.

## When something breaks

**`flutter analyze` complains about a view.** The common ones are already
fixed (awaiting `save()` results, `getSaveLocation` instead of `saveFile`,
`math.log(x)/math.ln2` for `log2`, missing imports). If a widget overflows
sideways, the fix is to stop squeezing a `Column` into an unbounded `Row`,
not to silence the warning — `test/app_smoke_test.dart` walks all six views
looking for exactly that.

**One test file fails.** Run just that file with
`flutter test test/<name>_test.dart`; the reporter names the case. If it only
fails with the full suite, look for state shared between tests.

**`flutter run -d linux` finds no devices.** Run
`flutter config --enable-linux-desktop`, and make sure the GTK dev packages
are installed.

**A plugin fails to build.** Delete `build/` and `.dart_tool/`, then run
`flutter pub get` again. Note that `pdfx` has no Linux backend (see the PDF
note in the README): the app builds and runs on Linux, but opening a page
says `PDF rendering is not available on this platform.` there. There's no
native code of ours in the build.

**Tiles don't load.** See [map sources](map-sources.md#troubleshooting): host,
user agent, and proxy/VPN notes are all there.

**Locate does nothing.** `MapSession.locate()` asks for permission through
`geolocator`; saying no shows up in the status line, it doesn't throw. The
Android manifest already has `INTERNET` plus coarse and fine location, and
the iOS `Info.plist` has `NSLocationWhenInUseUsageDescription`.

**You closed the app and lost a sentence.** Known issue: closing inside the
250 ms save window can drop what you just typed.
[TODO-003](../TODOS.md) tracks it.

## Things we don't do on purpose

- No globals that break hot reload: state hangs off the composition root in
  `main()`.
- No `setState` for something a controller should own: if two widgets need
  the same value, it belongs in `WorkspaceController`.
- No platform-specific code in `lib/`. `android/`, `ios/`, and friends are
  just there so Flutter can build, and weren't hand-edited apart from
  permissions.
