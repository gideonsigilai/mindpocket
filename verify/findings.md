# Device sweep findings — MindPocket

Device: 1080x2340 Android 15. Every result below comes from driving the real
APK over adb (uiautomator dumps, screenshots, logcat, and direct SQLite
inspection of the app's own database), not from reading code.

## Defects found and fixed

| # | Area | Symptom | Root cause | Fix |
|---|---|---|---|---|
| 1 | Settings → Speech models | Full red screen: "improper use of a GetX" | Outer `Obx` wrapped `_ModelCard`, whose builder reads no observable in that scope | Removed the wrapper; the card owns its `Obx` |
| 2 | Settings | `setState() during build` on opening the tab | Two observable writes ran synchronously inside `initState` via `dependencies()` | Deferred to `addPostFrameCallback` |
| 3 | Home → Notes filter | Every screenshot listed under Notes | Filter matched generated titles | Filter on "has no attachments" (list + count query) |
| 4 | Memory detail | System back discarded unsaved edits silently | Guard only on the AppBar button | `PopScope` with the same confirm dialog |
| 5 | Capture → save | Saved memory had a dead Back button | `offAllNamed(memory)` left detail as the only route | `offNamed` |
| 6 | Memory detail → delete | Blank screen after delete | No navigation | Pop, else fall back to home |
| 7 | Memory detail | "Transcription · queued" never cleared while open | No signal on job completion | `ProcessingService.onJobFinished` → revision bump |
| 8 | Transcript edit | RenderFlex overflow; Save button off-screen and untappable | Engine label + buttons in one unbounded `Row` | `Wrap` + min-size inner `Row` |
| 9 | Capture | Half-typed note / staged images dropped on Back | Guard only covered active recordings | `hasDraft` guard |
| 10 | Related memories | Tapping a suggestion re-opened the current memory | GetX reused the untagged controller singleton | Per-route `tag: id`, id captured at route creation |
| 11 | Collection detail | Same controller-reuse bug | as above | per-id tag |
| 12 | Capture → image import | Timeline froze on "1 item being processed" and never showed the new import | `offAllNamed(home)` rebuilt the shell, so the timeline rendered under a discarded controller while a fresh one did the refreshes | `Get.back()` to the existing timeline |
| 13 | Capture → image import | Duplicate import deleted the *existing* memory | `outcome.memoryId` is the original on a duplicate | Report the duplicate, delete nothing |
| 14 | Capture → image import | Picker import outcome never surfaced | `lastImportMessage` written but never watched or rendered | Report through `ShareImportService.lastMessage`, now watched by the timeline |
| 15 | Home → after import | Timeline stayed scrolled down, hiding the import banner and the new card | No scroll reset after an import | `requestScrollToTop()` tick → `HomePage` now stateful with a `ScrollController`, animates to 0 |
| 16 | *(retracted)* Collections tag chip | Chip tap looked dead | Driver artifact: chip was full-width in the dump; tapping its left edge select tags correctly | none |
| 17 | *(retracted)* Settings toggles | Auto-transcribe / auto-OCR read as off | My own earlier blind coordinate taps had flipped them | restored both |
| 18 | Settings → Speech models | "Verify files" appeared to do nothing | Result notice rendered below both model cards, off-screen | Notice/error block moved above the cards |
| 19 | Memory detail → voice note on a clean install | "Transcription · queued" forever, no explanation | `pm clear` removes installed models; the queue correctly parks, but the UI never said why and nothing resumed the queue after a model was installed | `transcriptionPossible` now checks model readiness; the Processing card explains the wait with an **Install** button; downloading a model calls `resumeQueue()` |

## Verified working this run
- Onboarding: 4 pages, skip/finish, photo permission gate
- Home: All/Images/Voice/Notes/Starred filters, sort toggle, star, delete (+confirm), pull-to-refresh, processing banner
- Capture: written note + tags, voice record/pause/resume/stop/play, image picker import, draft discard guard (button and system back)
- Offline transcription: Whisper Tiny download (98.8 MB), "Verify files", offline transcript, live completion refresh
- Transcript edit → Save persisted to `extractions.edited_text` and re-indexed
- Search: query, OCR/tag/title coverage, no-results state, clear
- Collections: create, assign, open, related strip, search link
- Settings: theme switch, toggles, interests dialog, maintenance, delete-all guard, cloud page + NIM key dialog
- Memory detail: star, related suggestions, dismiss, attach image, retry, delete guard, system-back guard, image viewer open/close, transcript edit with "Edited" badge
- Delete-all: confirm + cancel, wipes DB and media, keeps installed speech models (99 MB)
- Autopilot screenshots: fresh install imported 4/4 without a manual step; a new screenshot device-side imported itself on resume
- Collections: chip tag filter (`#onechurch` → "Tagged #onechurch"), remove-from-collection keeps the memory
- Light theme, empty states, upload-after-wipe note creation with tags

## Regression tests added
- `test/home_timeline_test.dart` — pending counter after a job, star/delete mutation, revision worker
- `test/home_render_test.dart` — real timeline widget: banner text and star state redraw
- `test/persistence_test.dart` — job completion notifies observers

## Verified working (final pass, newest build)
- Speech models page: loads, "Verify files" reports inline ("All 3 files match their published checksums.")
- Cloud page: "Send test request" → "Add your backend URL first."; "Save URL" validates
- Voice playback: position advances in real time (0:03 @3 s, 0:08 @7 s measured in one adb round trip; earlier "instant 100%" readings were adb dump latency)
- Settings maintenance: "Index rebuilt for 18 memories. Nothing to clean up."
- Filters after reinstall: Images → screenshot, Notes → typed note, Voice → "No voice notes yet"
- Sort toggle both directions, star/unstar, delete keeps vs deletes correctly

## 2026-11-06 — screenshot, detail and isolate cutover

Android 17 / lancelot, final arm64 debug APK. Original app data was preserved.

- Temporarily revoked photo access, then launched: the system Photos prompt
  appeared automatically. Granted **Allow all** through the actual dialog.
- Startup imported one new travel screenshot and completed native ML Kit OCR
  from the Dart worker; a generated thumbnail was stored.
- Added a second screenshot while backgrounded: resume imported it automatically.
  Searching `coast` returned exactly both new OCR-backed screenshots.
- Restart preserved the saved `trip-check` tag; tag search returned one result.
  Database contained 10 memories / 10 attachments / 8 extractions / 8 completed
  jobs: the original 8 memories plus exactly 2 verification captures, not duplicates.
- Viewed the actual image-first page, scrolled its parallax preview, opened and
  closed **Text from image**, saved a tag through its focused dialog, navigated a
  related-image thumbnail to the distinct memory, and opened/closed its image viewer.
  Completed **Processing** was absent. Runtime error sweep returned no exceptions.
- Schema upgraded 2 → 3; all original memory IDs survived. Integrity returned
  `ok`, foreign-key check was empty, journal mode was `wal`.
- Full Flutter suite: 95 passing. Static analysis: no issues. Final detail
  interactions and 320×700 at 1.8× text / 1024×1366 layouts passed; rendered with
  bundled Manrope and Material icons and visually inspected.
- iOS static validation: 47 project objects, 19 correctly sized icons, valid
  property lists/schemes/storyboards and resolved target references. No macOS,
  Xcode or iPhone was available; no iOS build/signing/runtime claim.

Evidence: `shots/automatic_startup_permission.png`, `shots/search_worker_ocr.png`,
`shots/memory_image_first.png`, `shots/memory_parallax_scroll.png`,
`shots/memory_collapsed_controls.png`, `shots/memory_tag_dialog.png`,
`shots/memory_expanded_text.png`, `shots/related_image_destination.png`,
`shots/tag_search_after_restart.png`, `shots/tablet_detail_light.png`,
`shots/compact_detail_large_text.png`.

Final native optimizer check: the original query used `idx_memories_updated`
and `USE TEMP B-TREE FOR ORDER BY`; after the bounded on-open statistics refresh,
the same query used `SCAN m USING INDEX idx_memories_timeline`, without a
temporary sort. Integrity remained `ok` and foreign-key check remained empty.
The two generated memories and their gallery source PNGs were removed; the
remaining memory IDs exactly matched the original eight.
