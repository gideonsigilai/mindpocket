# MindPocket

Screenshots and voice notes, kept in one offline, searchable pocket.

Imported images, recordings, typed notes, and extracted text stay on the device.
No account is required. Cloud analysis and AI grouping upload text only when
configured; speech-model downloads need a connection. On iOS, Photos may
download an iCloud-only screenshot's original before it can be imported.

## What works

| Area | Behavior |
| --- | --- |
| Capture | System image picker, Android share intent (cold/warm start), recording with pause/resume, typed notes, and attachments |
| Screenshots | Launch/resume scans use Android MediaStore, iOS PhotoKit, or the real OS screenshot folders on desktop. A one-time permission request follows onboarding; limited access is supported. Durable receipts copy/process only unseen screenshots, including equal-date items and older images added later |
| AI grouping | NVIDIA NIM files imported screenshots into collections by their extracted text (never the image bytes), reusing existing collection names, batching 25 items per request, one collection link per item, and reporting backend/parse failures without touching what is already filed |
| Timeline | Filters (all / images / voice / notes / starred), newest or oldest first, paginated, skeletons, empty and error states |
| Detail | Image-first preview (~75% of viewport), reduced-motion-aware parallax, original-image zoom, collapsed **Text from image**, tag-chip dialog, audio/transcript editing, and related-image previews; completed/canceled processing is hidden |
| OCR | On device through a background Dart isolate: ML Kit's bundled Latin recognizer on Android/iOS, Apple Vision on macOS, Tesseract on Windows/Linux (bundled on Windows, a declared dependency on Linux). No Play Services, no first-use model download, no cloud fallback |
| Search | Isolate-backed SQLite FTS5 over titles, notes, tags, OCR, and transcripts; BM25 snippets and off-thread lexical relatedness; stale query responses are discarded |
| Transcription | Optional sherpa-onnx Whisper (tiny.en ~103 MB, tiny multilingual), downloaded to app storage, SHA-256 verified, run in a background isolate |
| Jobs | Persisted queue, one job at a time, interrupted jobs requeued on launch, retry/cancel; parked transcription never blocks screenshot OCR |
| Cloud AI | Provider-neutral interface, explicit action, structured output validated before saving; disabled unless you configure a proxy URL |
| Deletion | Removes rows, files, thumbnails, extractions, jobs, embeddings, suggestions, and search entries; speech models are kept |

## Requirements

- Flutter 3.47+ (Dart 3.13+)
- Android SDK with **platform 37** and build-tools 37 (two plugins declare
  `compileSdk 37`; on this machine the SDK ships it as the minor-version
  platform `android-37.0`, which is why `android/app/build.gradle.kts` pins
  `compileSdk = 37` instead of inheriting Flutter's default)
- AGP 9.3.1 + Gradle 9.6.1 (set in `android/settings.gradle.kts` and the
  wrapper; AGP 9.1 cannot resolve minor-version platforms)
- minSdk 24, arm64 device for on-device Whisper
- Desktop: Windows 10+ (x64), Linux with GTK 3 (`libmpv2`, `ffmpeg`,
  `pulseaudio-utils`, `tesseract-ocr`), macOS 13+ (Apple Silicon or Intel).
  Desktop OCR uses Tesseract on Windows/Linux and Apple Vision on macOS;
  there is no cloud fallback.
- iOS 15.5+, macOS/Xcode and signing credentials to build/run on an iPhone.

## Build and run

```sh
flutter pub get
flutter analyze
flutter test
flutter run --release      # or: flutter build apk --debug
```

For a smaller Android device-install artifact:

```sh
flutter build apk --debug --split-per-abi --target-platform android-arm64
```

### iOS

The `ios/` runner includes the screenshot PhotoKit channel, Photos/microphone
usage descriptions, app icons, keychain entitlements, and CocoaPods/Swift
Package Manager integration. From the project root on macOS:

```sh
flutter pub get
flutter build ios --debug --no-codesign
open ios/Runner.xcworkspace
```

Select the Runner signing team in Xcode before installing on a physical iPhone.
Prefer hardware: the bundled ML Kit dependency does not support every Apple
Silicon simulator configuration. This Windows workstation cannot compile,
sign, or run iOS; project structure checks are not device verification.

If opening Xcode directly rather than building through Flutter, the current
`permission_handler_apple` Swift package needs its Info.plist discovery override:

```sh
launchctl setenv PERMISSION_HANDLER_INFO_PLIST "$PWD/ios/Runner/Info.plist"
```

Relaunch Xcode after setting it. No iOS share extension is registered; use
automatic screenshot import or the system picker.

### Desktop

```sh
flutter build windows --release   # needs Visual Studio with C++ desktop workload
flutter build linux --release     # needs libgtk-3-dev, libsecret-1-dev, libmpv-dev
flutter build macos --release     # needs Xcode command line tools
```

Desktop screenshot intake reads the real OS folders (`Pictures\Screenshots` and
OneDrive on Windows, XDG `user-dirs.dirs` entries on Linux, the
`com.apple.screencapture` location and Desktop on macOS). Files that are not
screenshots are never imported: dedicated folders take every image, while shared
folders such as `Desktop` and `Pictures` require a screenshot-style filename.
Access failures are reported; a missing folder is an empty library.

Windows releases bundle Tesseract next to the executable, so OCR works without a
separate install. Linux packages declare their OCR, audio and video runtime
packages as Debian dependencies instead of embedding them.

### Release pipeline

`.github/workflows/native.yml` runs analyze/tests once (`quality`), then builds
Android, Windows, Linux, macOS and iOS on their own runners and uploads one
artifact per platform. Every packaging step goes through
`tool/release/package.py`, which names assets
`MindPocket-<semver>+<build>-<platform>-<arch>.<ext>` from `pubspec.yaml`, so a
release can never advertise a version the source does not declare.

Pushing a `v*` tag additionally runs the `release` job: it downloads every
platform artifact, refuses to continue if any platform is missing, writes
`SHA256SUMS`, creates the release as a draft, attaches all assets, and only then
publishes. Unsigned or debug-signed outputs are labelled as such in the release
notes rather than presented as installable.

| Platform | Assets |
| --- | --- |
| Android | `MindPocket-<version>-android-<abi>.apk` per ABI, plus `…-android-release.aab` |
| Windows | `MindPocket-<version>-windows-installer.exe` (Inno Setup, bundled Tesseract) and `…-windows-x64.zip` (portable) |
| Linux | `mindpocket_<version>_amd64.deb` and `MindPocket-<version>-linux-amd64.tar.gz` |
| macOS | `MindPocket-<version>-macos-<arch>.zip` holding the ad-hoc signed `.app` |
| iOS | `MindPocket-<version>-ios-unsigned-app.zip`, or `…-ios-signed.ipa` when Apple secrets exist |

Signing material is only ever loaded for `v*` tag pushes; these repository
secrets change what gets built:

| Secret | Effect when set |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Release-signed APKs and App Bundle on tag pushes; otherwise debug-signed |
| `IOS_CERTIFICATE_BASE64`, `IOS_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`, `IOS_EXPORT_OPTIONS_PLIST_BASE64` | Signed installable IPA; otherwise an explicitly unsigned compilation archive |

Signing material is never decoded for pull requests or branch pushes, and a
partial Android configuration fails the Gradle build instead of silently
falling back.


## Why bundled SQLite

Android's system SQLite has no FTS5 module (verified on the test device:
`FTS5 FAIL`, `FTS4 OK`), so search uses `sqflite_common_ffi` over the bundled
`sqlite3` build via code assets. The same migrations run in tests, so schema
drift cannot hide behind a mock.

The default FFI factory owns a dedicated `SqfliteIsolate`: connection open,
SQL reads/writes, migration statements, FTS work, and close execute there.
Schema v3 preserves user rows, adds query-shaped indexes, and maintains FTS
with transactional triggers. Bounded optimizer statistics refresh after opening
the database so SQLite can use the ordered timeline index without a temporary
sort. Disk databases use WAL, foreign keys, a busy timeout, and
`synchronous=FULL`; there is no claim of database encryption.

File copying/hashing, receipt journals, model integrity checks, storage scans,
OCR, transcription, and relatedness ranking use Dart workers. Screenshot
enumeration/copying additionally use native worker queues. UI state, permission
prompts, and Flutter engine image-codec dispatch remain on the root isolate;
pixel decoding itself is engine work. Jobs remain app-process scoped, not an
always-running OS service.


## Speech models

Download from **Settings → Offline transcription**. Each file is fetched to a
`.part` file, hash-checked against the published SHA-256, and only then moved
into place, so a partial download can never be used.

| Model | Size | License |
| --- | --- | --- |
| Whisper Tiny (English) | ~103 MB | MIT (model), sherpa-onnx conversion |
| Whisper Tiny (99 languages) | ~110 MB | MIT (model), sherpa-onnx conversion |

Without a model, recordings stay playable and their transcription job waits in
the queue instead of failing. Nothing falls back to cloud transcription.

## OCR language coverage

The bundled ML Kit model covers Latin script. Chinese, Devanagari, Japanese,
and Korean would require additional Gradle dependencies that are not shipped
here. OCR returns text only; it is never presented as understanding an image.

## Tests

`flutter test` exercises the real SQLite schema and the real file store against
a throwaway directory, with deterministic OCR/ASR fakes:

- typed notes persist and are searchable
- timeline filters (all / images / voice / notes / starred)
- image import copies bytes into app storage and queues OCR
- identical bytes are reported as a duplicate, not copied twice
- empty files are rejected while the memory is kept
- OCR completes, records extractions, and makes text searchable
- images without text complete with an honest empty record
- failed OCR is recorded with the reason and retries the same job row
- job enqueue is idempotent for active and completed jobs
- interrupted jobs are requeued exactly once
- transcription parks without a model and completes once installed
- user edits survive reprocessing; raw engine output is replaced
- tags and collections are queryable and cleaned up
- deletion removes rows, files, jobs, and search entries
- removing one attachment keeps the memory and its other files
- search snippets keep FTS markers so the matched term is emphasised
- processing switches rebuild from reactive state instead of stale getters
- detail edits persist, drafts survive background refresh, favorite/tags/
  collections write through, attachment removal is surgical, retry requeues the
  same job, a deleted memory reports an honest error, transcript edits leave the
  recording untouched
- screenshot import: first pass takes everything with device capture times,
  later passes take only new items, a full rescan skips already-saved copies
  without leaving empty rows, a denied permission imports nothing, one
  unreadable file does not abort the pass, importing kicks the OCR queue
- "last import" reports the run time, not the newest screenshot's capture time
- NIM grouping: creates and reuses collections, links each item once, a backend
  failure changes nothing, omitted items keep their current collections, fenced
  JSON is parsed, unknown ids are dropped, a missing key fails before any request
- desktop screenshot filesystem intake: a missing folder is an empty library,
  unrelated images in a shared folder are ignored, pages resume after a cursor,
  an edited file gets a new revision key, copies are byte-exact, a moved source
  is refused, symlinks are never followed out of the folder
- desktop OCR: a missing engine is reported as `ocr_unavailable` rather than an
  empty success, an empty image is rejected, and real Tesseract output keeps
  non-ASCII characters (the em dash in the fixture) intact

## Latest verification

- Full Flutter suite: **105 passing** (including desktop screenshot and OCR
  coverage), static analysis: **no issues**.
- Windows: clean `flutter build windows --release`, then `windows.ps1` produced a
  66 MB Inno Setup installer and a 93 MB portable ZIP; the packaged build was
  launched from its portable folder and stayed resident. See `verify/desktop.md`.
- Windows OCR, end to end: the packaged app discovered the real
  `Pictures\Screenshots` folder, imported 37 screenshots with no manual action,
  and Tesseract extracted genuine text from them. This run also caught two real
  defects, both fixed: stdout decoded with the ANSI code page (mojibake in
  non-ASCII text) and Tesseract looked up only under `Program Files` while winget
  installs per-user.
- Android release: `flutter build apk --release --split-per-abi` produced three
  ABIs; `apksigner` confirms the debug certificate when no keystore secrets are
  set, which the release notes state explicitly.
- Android device: automatic startup Photos prompt; new screenshot imported,
  OCR completed and thumbnail persisted without manual import.
- Live schema upgrade 2 → 3 preserved all 8 existing memories; database
  integrity check returned `ok`.
- Memory-detail interactions and compact/large-text/tablet layouts exercised
  through real widgets; device evidence is recorded in `verify/findings.md`.
- iOS and macOS: no Xcode exists on this workstation. Property lists, project
  references, schemes, storyboards, icon dimensions and the `mindpocket/ocr`
  Vision channel were reviewed statically; compilation and signing happen only
  in `.github/workflows/native.yml` and remain unverified here.

## Previous verification results

Run on this machine (Flutter 3.47.9, Android SDK 37, AGP 9.3.1, Gradle 9.6.1):

| Check | Result |
| --- | --- |
| `flutter analyze` | No issues |
| `flutter test` | 47/47 passing |
| `flutter build apk --debug` | Built |
| `flutter build apk --release` | Built, 171 MB |
| On-device install + launch (Redmi Note 9 / lancelot) | Launched with no Dart exceptions; typed note persisted, FTS matched it, `PRAGMA integrity_check` = ok |

Verified off-device by driving the real widgets against the real SQLite schema:

- Home timeline on a 390×844 phone and a 1024-wide tablet, plus 1.5× text
- Search results with highlighted matches
- Collections overview and Settings (storage facts, honest "not configured"
  cloud state)
- Composer save action staying reachable while the keyboard is open

Fixes found during that verification, all covered above:

1. `fontFamily: 'Manrope'` was referenced but never declared, so every screen
   silently fell back to the platform font.
2. The note composer's save button was pushed below the keyboard.
3. Fixed-height timeline grid cells overflowed at enlarged text.
4. The reduce-motion and processing switches wrapped plain getters in `Obx`,
   so they never updated after a tap.
5. Search snippets repeated the title and rendered no match emphasis.
6. `ProcessingService.schedule()` deferred work behind a 50 ms timer, so a
   retried job could be missed by an awaited drain; `drain()` now absorbs the
   pending kick.

### Screenshot import and AI grouping, verified on the device

| Check | Result |
| --- | --- |
| First run after `pm clear` | Android prompt for photos, then all 3 screenshots imported with their real capture times (`1 Nov`, `3 Nov`, `4 Nov`) |
| OCR without any UI action | 3/3 jobs completed by the bundled ML Kit recognizer, text stored and indexed |
| Search over OCR text | query `Equitel` returned the 11/3 screenshot with the matched word emphasised |
| NVIDIA NIM grouping | one request over the 3 extracted texts produced `Money`, `Media`, `Phone apps`, and the Collections tab listed all three |
| New screenshot while backgrounded | resume imported exactly 1 file, ran OCR, sorted it, and reported it in a banner |
| Restart | 3 memories, 3 collections, 3 completed jobs, no duplicates |

Grouping sends extracted text only. The API key is stored with
`flutter_secure_storage`, never in preferences and never in the APK.

## Not verified here

- Share-intent import from another app (needs a second app on a live device).
  The cold- and warm-start paths themselves were verified in the previous round.
- Real sherpa-onnx transcription output on hardware; it is exercised through its
  interface with fakes in tests.
- Airplane-mode transcription after a real model download (requires the
  ~103 MB fetch and an arm64 device).
- NIM behaviour under rate limiting or when the model returns prose instead of
  JSON beyond the parser cases covered by tests.

## Known limitations

- Background execution is app-process scoped on Android and iOS. A killed or
  suspended app cannot promise unrestricted continuous processing; unfinished
  jobs resume when it returns to the foreground.
- Screenshot import runs while the app is in the foreground or on resume; there
  is no always-on media observer.
- AI grouping needs a NVIDIA NIM key entered in `Settings → AI grouping`. It
  sends extracted text, so a screenshot whose OCR produced nothing is grouped by
  its title alone.
- Cloud analysis requires your own proxy (`Settings → Cloud analysis`). No
  provider key is bundled in the APK.
- Related matching is lexical, including OCR/transcripts, not image understanding
  or embedding-based semantic search. Suggestions name their comparison context
  and are not calibrated confidence scores.
