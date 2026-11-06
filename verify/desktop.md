# Verifying the release packaging paths

## Windows (verified on this machine)

Environment: Flutter 3.47.9, Visual Studio 2026 18.10, Flutter SDK
`D:\sdks\flutter_versions\flutter_3.47.5`, Inno Setup 6.7.3 (per-user),
Tesseract 5 (UB-Mannheim), NuGet feed pinned by the repository `NuGet.config`.

| Check | Result |
| --- | --- |
| `flutter build windows --release` on a clean `build/windows` tree | Built `build\windows\x64\runner\Release\mindpocket.exe` |
| Bundled native libraries | `libmpv-2.dll` (media_kit), `sqlite3.dll` (code asset), `sherpa-onnx-c-api.dll`, `onnxruntime.dll`, and the four plugin DLLs are all in the release bundle |
| Release launch | The release executable stayed resident for 12 s and logged `package:media_kit_libs_windows_audio registered` |
| Automatic screenshot import without any UI action | 37 memories created by scanning the real `Pictures\Screenshots` folder; no manual import step |
| OCR dispatch on this platform | Jobs recorded `Text extraction needs the Tesseract OCR component, which is missing from this installation.` with type `ocr`, status `failed` while Tesseract was absent — the honest error, not a silent empty success |
| Windows package format | `mode=ro` reads of `mindpocket.db` show `memories`, `processing_jobs`, `memory_fts` and the schema-v3 tables, so the packaged SQLite (not the OS copy) is in use |
| Packaged artifacts | `tool/release/windows.ps1` produced `MindPocket-1.0.0+1-windows-installer.exe` (65.7 MB, Inno Setup) and `MindPocket-1.0.0+1-windows-x64.zip` (92.8 MB, portable), then launched the portable build for 15 s without it exiting |
| Bundled OCR runtime | `portable\tesseract\tesseract.exe` reports `tesseract v5.4.0.20240606` and `tessdata` holds exactly `eng.traineddata` |
| OCR through the app | After installing Tesseract, 3 jobs completed and `extractions` holds real text (`Director General / Gambling Regulatory Authority of Kenya`), so the platform dispatch, isolate hop and `Process.run` path all work |
| Desktop UI | Captured the real release window at 1280×720 (`shots/windows_desktop_timeline.png`): sidebar Home/Collections/Settings, search field, filter chips, the screenshot grid with thumbnails and honest "Text extraction failed" badges, and the Capture action |
| Artifact verification | `python tool/release/package.py windows` accepts the produced installer and portable archive and rejects a bundle without them |

Four real Windows-only defects surfaced here and were fixed:

1. `permission_handler_windows` (CMake → NuGet) failed on a machine whose
   user-level `nuget.config` has no package sources. The repository now pins
   `NuGet.config` with `<clear/>` plus nuget.org, which NuGet picks up from
   `build/windows/x64` by walking up.
2. A stale `build/windows` CMake cache kept `CMAKE_INSTALL_PREFIX` at
   `C:/Program Files/mindpocket`, so the install step tried to write into
   Program Files. Removing `build/windows` regenerates the bundle-relative
   prefix; CI always starts from a fresh checkout.
3. `Process.run` decoded Tesseract's stdout with the Windows ANSI code page, so
   `—` became `â€”` and `¥` became `Â¥` in the stored OCR text. The service now
   requests raw bytes (`stdoutEncoding: null`) and decodes UTF-8 itself;
   `test/ocr_desktop_test.dart` pins this against the real engine.
4. `windows.ps1` only looked for Tesseract under `Program Files`, but winget
   installs per-user under `LOCALAPPDATA\Programs`. It now checks the
   per-machine, per-user and x86 locations before failing.

## Linux

`lib/core/services/screenshots/screenshot_source.dart` selects
`_DesktopScreenshotLibrary` on Linux and reads `XDG_PICTURES_DIR`/
`XDG_DESKTOP_DIR` (including `user-dirs.dirs`), scanning
`Pictures/Screenshots`, `Pictures/screenshots`, and `Pictures`/`Desktop` by
filename pattern. `test/desktop_screenshot_test.dart` exercises real filesystem
workers for those rules, bounded paging, revision keys, byte-exact copying, and
symlink refusal.

`tool/release/package.py linux` was run inside WSL Debian 13 against a synthetic
bundle: it produced `mindpocket_1.0.0+1_amd64.deb` and
`MindPocket-1.0.0+1-linux-amd64.tar.gz` with the expected `/opt/mindpocket`
payload, desktop entry, 512×512 icon and `Installed-Size`. `apt-get install -s`
resolves the declared dependencies on Debian 13, which is why they name the
64-bit-time packages (`libgtk-3-0t64`, `libsecret-1-0t64`) with the old names as
alternatives.

The Flutter Linux binary itself could not be built on this workstation: the SDK
download and the GTK/libmpv development packages did not finish over this
connection. CI covers it — the `linux` job compiles the release, packages the
Debian and tarball artifacts, and smoke-launches the installed binary under
`xvfb-run`/`dbus-run-session` on Ubuntu 24.04.

## macOS and iOS

macOS OCR runs through the `mindpocket/ocr` channel implemented in
`macos/Runner/MainFlutterWindow.swift` (Apple Vision); the Windows/Linux
Tesseract path and the mobile ML Kit path are the ones exercised locally.
Compilation, packaging and the release itself were verified by running
`native.yml`: all six build jobs succeeded and the `release` job published tag
`v1.0.0` with eleven assets. The iOS asset is
`MindPocket-1.0.0+1-ios-unsigned.ipa`, a `Payload/Runner.app` archive with no
code signature; the pipeline never loads Apple signing material, so installing
it requires signing with your own certificate and provisioning profile.

Three defects were found by those CI runs and fixed:

1. macOS had no `Podfile`, so no plugin would have linked. Added, using
   CocoaPods because every Apple plugin here ships a podspec and none ships a
   Swift package.
2. `xcodebuild` failed with an empty `PODS_ROOT`, resolving
   `Pods-Runner-frameworks-Release-input-files.xcfilelist` against `/`.
   CocoaPods cannot assign the Runner target's base configuration because
   Flutter's xcconfig already owns it, and Flutter's macOS xcconfig — unlike its
   iOS one — never included the Pods settings. `Flutter-Debug.xcconfig` and
   `Flutter-Release.xcconfig` now include them with `#include?`, so a build
   without pods still configures.
3. Those comments were written with `#`, which xcconfig reads as a preprocessor
   directive, so the next run failed with "unsupported preprocessor directive
   'CocoaPods'". xcconfig comments are `//`.

The Android job had two separate failures of the same kind: `setup-android`
installs the removed `tools` package, and the image's `cmdline-tools` are not on
`PATH`, so `sdkmanager` was "command not found". The workflow now resolves
`sdkmanager` from `ANDROID_HOME` and exports `ANDROID_SDK_ROOT`. The platform it
installs is `android-37.0`; plain `android-37` is not published.
