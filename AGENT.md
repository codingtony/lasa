# AGENT.md — working on Läsa

Läsa is a macOS (Apple Silicon, macOS 14+) PDF reader that reads Swedish text aloud. It is a SwiftPM package with no Xcode project. The build machine only has the Command Line Tools (no Xcode.app). Swift 6.3, language mode 5.

## Layout

| Path | Role |
|---|---|
| `Sources/LasaCore/Segmenter.swift` | Pure text → speech segments (`segments(of:startingAt:)`, `Segment`). Unit-tested. |
| `Sources/LasaCore/ReadingZone.swift` | Pure geometry: the part of each page that is read aloud, in display-normalized coordinates. Unit-tested. |
| `Sources/LasaCore/ReadingOrder.swift` | Pure geometry: OCR line boxes → reading order (recursive XY-cut, widest gap first, columns win ties, leaf = top→bottom). Unit-tested. |
| `Sources/Lasa/ReaderController.swift` | `@MainActor @Observable` singleton. Owns the document, the reading loop (page → segments → engine), pauses, highlights, follow, click-to-jump, go-to-page, and the resume offer. |
| `Sources/Lasa/PageTextProvider.swift` | Gets page text from the PDF text layer when it has ≥ 20 chars; otherwise runs Vision OCR (`sv-SE`) at 2.5× render and orders the lines with `ReadingOrder` (boxes in rendered-image pixels), so columns are read one after the other. Caches per page and prefetches the next page. With a reading zone set, `PageText.restricted` blanks out-of-zone lines with spaces (indices unchanged, so highlights and clicks still map); zoned pages are cached separately and dropped when the zone changes. |
| `Sources/Lasa/Speech/` | `SpeechEngine` protocol; `AppleSpeechEngine` (AVSpeechSynthesizer, word callbacks); `PiperSpeechEngine` (sherpa-onnx C API + AVAudioEngine); `VoiceCatalog` (`VoiceID` strings `apple:<id>` / `piper:<folder>`; `defaultPiperFolder` is Lisa, used when no voice was ever chosen). |
| `Sources/Lasa/PDFKitView.swift` | `ReaderPDFView` (click monitor, "Read from here" menu, reading-zone editor: while editing, the monitor consumes drags and `ReadingZoneOverlay` dims outside the zone on visible pages) and its coordinator (fit modes, auto-scroll timer, page-change persistence). |
| `Sources/Lasa/{ContentView,InspectorView,LasaApp,Settings,HighlightAnnotation}.swift` | UI, menus, UserDefaults keys (`SettingsKey`, `ResumeMode`), and the highlight annotation. |
| `Sources/CSherpaOnnx/include/c-api.h` | Vendored header, pinned to sherpa-onnx **1.13.8**. Must match `SHERPA_VERSION` in `scripts/fetch-vendor.sh`. |
| `scripts/fetch-vendor.sh` | Downloads `Vendor/sherpa-onnx` (osx-arm64-shared) and the Piper models `vits-piper-sv_SE-{alma,lisa,nst}-medium` (~80 MB each). `Vendor/` is gitignored. |
| `scripts/build-app.sh` | Runs `check-requirements.sh`, then release build → assembles `build/Läsa.app` and runs `package-app.sh`. The executable inside stays `Lasa` (SwiftPM target name); only the bundle and `CFBundleName` are `Läsa`. |
| `scripts/package-app.sh` | Takes an assembled `build/Läsa.app`: optional env `VERSION`/`BUILD` set `CFBundleShortVersionString`/`CFBundleVersion`, ad-hoc signs (dylibs, then bundle), writes `build/Läsa.zip` (ditto) + `build/Läsa.dmg`. `hdiutil create` is retried (it flakes with "Resource busy" on CI). Run on its own by CI to release an app built by an earlier run. |
| `scripts/check-requirements.sh` | Checks Apple silicon, macOS ≥ 14, Swift ≥ 6.0, build tools, ≥ 2 GB free, and GitHub reachability when `Vendor/` is incomplete. Lists every failure with a fix, exits 1. |
| `scripts/test.sh` | Runs `fetch-vendor.sh` (the test build also links the app target, which needs `Vendor/sherpa-onnx/lib`), then `swift test`, with the extra flags Swift Testing needs on CLT-only machines. Uses `${flags[@]+…}` because macOS's bash 3.2 errors on empty arrays under `set -u`. |
| `scripts/make-icon.swift` | Draws the app icon in CoreGraphics and writes `Packaging/AppIcon.icns` (committed; `build-app.sh` copies it) plus a 1024 px preview at `build/AppIcon.png`. Run `swift scripts/make-icon.swift` after changing the design. |
| `scripts/install.sh` | The README's `curl … \| bash` installer: checks the Mac, downloads `releases/latest/download/Lasa.zip` from `codingtony/lasa`, quits a running `Lasa` process, installs into `/Applications` (or `~/Applications`), opens it. All code is inside `main()` so a truncated download runs nothing. Test locally with `LASA_ZIP_URL=file:///…/Lasa.zip LASA_INSTALL_DIR=/tmp/x` (piped to `bash`, as users run it). Calls `/usr/bin/xattr` explicitly: Homebrew's Python `xattr` shadows it and lacks `-r`. |
| `.github/workflows/build.yml` | `macos-26` runner (Apple silicon, Xcode 26 / Swift 6.3). PRs: tests. Push to `main`: tests + build, DMG kept 7 days as an artifact, plus `Lasa.zip` as `app-<sha>` (a ditto zip, because `upload-artifact` drops permissions and symlinks). Tag `v*`: if the `main` run of the same commit succeeded and its `app-<sha>` is still there, unzip it and run `package-app.sh` with `VERSION` from the tag (no tests, no build); otherwise tests + full build. Then `gh release create` with `Lasa.dmg`/`Lasa.zip`. Pushes share a concurrency group per commit, so a tag run waits for the `main` run of its commit; only PR runs are cancelled when superseded. Release file names are ASCII and unversioned, because the installer relies on `releases/latest/download/Lasa.zip`. `Vendor/` is cached on the hash of `fetch-vendor.sh`. Free on a public repo. |

Reading zone: one display-normalized rect per PDF path (`SettingsKey.readingZones`), relative to each page's crop box and in the page's shown orientation, so it covers the same visible area on rotated pages. A line is kept when its center is inside. OCR line rects are mapped from Vision's (rotated) image space back to page space with `ReadingZone.pageRect`, for every rotation.

Localization (English + Swedish):
- Strings live in `Packaging/{en,sv}.lproj/Localizable.strings`; `build-app.sh` copies them into `Contents/Resources`, and `Info.plist` declares `CFBundleLocalizations` en/sv. Keys are the English text. `en.lproj` is intentionally empty.
- SwiftUI string literals (`Text("…")`, `Button("…")`, `.help("…")`…) are looked up automatically. A `String` value is shown verbatim, so ternaries need `LocalizedStringKey(cond ? "A" : "B")`, and strings built outside SwiftUI (alerts, `NSMenuItem`, voice labels) need `String(localized:)`.
- Interpolation becomes a format specifier in the key: `Int` → `%lld` in SwiftUI keys, `String` → `%@`.
- Language choice: `Settings.languageOverride` reads/writes `AppleLanguages` in the app's own defaults domain ("" = follow the system). macOS applies it at launch, so the sidebar offers **Restart Now** (relaunch via `NSWorkspace`, bundled app only). `swift run` has no `.lproj` and is always English.

## Commands

```sh
./scripts/fetch-vendor.sh                                  # once
./scripts/test.sh                                          # never plain `swift test` on a CLT-only machine (see below)
LASA_PIPER_DIR=$PWD/Vendor/piper swift run Lasa            # dev run; without the env var no Piper voices are listed
./scripts/build-app.sh                                     # app + zip + dmg
codesign --verify --deep --strict build/Läsa.app           # must exit 0
```

UserDefaults domains:
- The bundled app uses `local.lasa.reader`.
- `swift run` uses `Lasa`.
- A throwaway harness binary uses its own executable name.

Inspect with `defaults read local.lasa.reader`.

## Toolchain gotchas (all hit in practice)

- **Swift Testing on CLT only:**
  - `Testing.framework` lives in `/Library/Developer/CommandLineTools/Library/Developer/Frameworks`, and `lib_TestingInterop.dylib` in `.../Library/Developer/usr/lib`.
  - Target-level `unsafeFlags` are not enough. SwiftPM's generated `runner.swift` is guarded by `#if canImport(Testing)` and compiles without them, so plain `swift test` silently runs zero tests and exits 0.
  - `scripts/test.sh` passes `-Xswiftc -F` plus the two linker rpaths globally. XCTest is not available.
- **Linking sherpa-onnx:**
  - `Package.swift` links with `-L <pkg>/Vendor/sherpa-onnx/lib` and two rpaths: `@executable_path/../Frameworks` for the bundle, and the Vendor lib dir for `swift run`.
  - The release dylibs already use `@rpath` install names, and the c-api dylib already has an `@loader_path` rpath. `build-app.sh` still normalises them, and `package-app.sh` **must re-sign** (`codesign --force -s -`) after `install_name_tool` or an `Info.plist` edit, otherwise arm64 refuses to load them.
- **Bundle independence check:** `mv Vendor Vendor.off && open build/Läsa.app`. The app must start and list the Piper voices from `Contents/Resources/piper`. Restore Vendor afterwards.

## Speech facts

- **Piper / sherpa-onnx:** model load ≈ 0.8 s, synthesis ≈ 0.2–0.3 s per sentence, 22 050 Hz mono.
  - `SherpaOnnxGenerationConfig.speed` scales sub-linearly (2.0 → only ~1.56× faster; 1.5 → ~76 % duration). So audio is always synthesized at speed 1.0, and `AVAudioUnitTimePitch.rate` applies the exact speed.
  - Pitch = `timePitch.pitch = 1200·log2(p)` cents (live).
  - Synthesis runs on one serial queue (the TTS handle is not shared across threads). A one-entry prefetch cache holds the next sentence, and a generation counter discards stale completions.
- **Apple voices:** speed maps onto `AVSpeechUtterance.rate` around `AVSpeechUtteranceDefaultSpeechRate`, and pitch uses `pitchMultiplier`. Delegate callbacks are matched to the current utterance by `ObjectIdentifier`. Premium/Enhanced Swedish voices (Alva, Klara, Oskar) are downloaded by the user in System Settings → Accessibility → Spoken Content.
- **Pauses** live in `ReaderController.segmentFinished()`, not in the engines:
  - After a segment with `endsBlock == true`: `linePause / speed`.
  - Otherwise: `linePause × Settings.sentencePauseFraction (0.35) / speed`.
  - Pausing during the gap sets `advanceOnResume`.
- **Per-voice speed/pitch:**
  - The current values live in the `speed`/`pitch` keys.
  - `InspectorView.onChange(of: voiceID)` stores the old voice's values in `voiceSettings` and loads the new voice's (default 1.0/1.0).
  - Never overwrite a saved `voiceID` just because the voice list does not contain it yet; the picker shows it as "(unavailable)".

## Segmenter rules (`Segmenter.swift`, covered by `Tests/LasaCoreTests`)

1. Split lines into blocks at:
   - empty lines,
   - lines ending with `:`,
   - or short lines (< 60 % of the longest line on the page) that don't end in `-`, when the next line starts uppercase, with a digit, or with a bullet.
2. Within a block:
   - `-` at a line end followed by a lowercase letter joins the word (`läke-\nmedel` → `läkemedel`);
   - other line breaks become one space;
   - `spokenToRaw` maps every UTF-16 index back to the page string. All highlighting depends on it.
3. Sentence-split with `NLTokenizer` (Swedish). `endsBlock` is true for the last sentence of a block or a sentence ending exactly at a line end.
4. A start offset trims the first segment back to the start of its word.

Multiple-choice pages ("Välj ett alternativ:" + options) must keep every option as its own segment with `endsBlock == true`. A test pins this.

## PDFKit gotchas (each caused a real bug)

- `PDFPage.characterIndex(at:)` snaps to a nearby character (often the previous word or line). Use `selectionForWord(at:)` and check that its bounds contain the point.
- Mouse events go to PDFKit's internal `PDFPageView`, which runs its own tracking loop. Overriding `mouseDown` on the `PDFView` subclass, or adding an `NSClickGestureRecognizer`, never fires. The working approach is a local `NSEvent` monitor (`addLocalMonitorForEvents`), then judging the click asynchronously after PDFKit has handled it: button up, moved < 4 pt, and no text selection.
- Assigning `pdfView.document` posts `PDFViewPageChanged` for page 1, which overwrites the saved page. So read `Settings.lastPage` in `ReaderController.open` **before** the view loads the document.
- A new document can inherit the previous scroll offset. After assigning a document, always `go(to:)` a page (pending resume page via `takePendingPage()`, or 0), dispatched async so layout and fit scaling have happened.
- The document view is not flipped (larger y = earlier pages).
- Highlights are an in-memory `PDFAnnotation` subclass that fills its bounds (multiply blend). Never write the document back.
- Follow-reading scrolls only when the current line leaves the middle 70 % of the view.
- `PDFPage.characterBounds(at:)` drifts from `page.string` indices around line breaks (a footer digit reported the previous line's position, some characters report `.zero`). Use `selection(for:)`/`selectionsByLine()` bounds, which match `page.string` like the highlighting does.

## Verifying UI changes without GUI automation

There are no Accessibility or Screen Recording permissions: `osascript` System Events and `screencapture` fail. Synthetic `NSEvent`s do not reach PDFKit either (even a synthetic drag doesn't select text). What works is a throwaway harness:

1. Compile `Sources/Lasa/*.swift` and `Sources/Lasa/Speech/*.swift` (minus `LasaApp.swift`) together with `.build/arm64-apple-macosx/debug/LasaCore.build/{Segmenter,ReadingZone,ReadingOrder}.swift.o`, `-I .build/.../debug/Modules`, `-I Sources/CSherpaOnnx/include`, and the sherpa `-L`/`-rpath` flags. Use `-swift-version 5`. Alternative: temporarily add `"Lasa"` to the test target's dependencies and `@testable import Lasa` from a throwaway test (run via `scripts/test.sh`); `NSApp.postEvent` + pumping `nextEvent` does reach the local `NSEvent` monitors.
2. Host `ContentView(controller: ReaderController.shared)` in an `NSHostingView` inside an `NSWindow`. Drive the controller directly (`open`, `play`, `wordClicked`, `goToPage`, setting UserDefaults keys) and pump `RunLoop.main`.
3. Observe:
   - `HighlightAnnotation`s on pages;
   - `pdfView.currentPage`;
   - audio via `pmset -g assertions` (a coreaudiod `audio-out` assertion while speaking);
   - visuals by drawing a page with `page.draw(with:to:)` into a bitmap. `cacheDisplay` does not capture the PDF scroll position or the inspector.
4. Delete the harness afterwards. Real mouse clicks and dialogs still need a human test.

Checking the shipped bundle's UI text (e.g. translations): the app is ad-hoc signed without hardened runtime, so a throwaway dylib loaded with `DYLD_INSERT_LIBRARIES` can dump `NSApp.mainMenu` titles and the window's in-process accessibility labels to a file, then terminate. Launch `build/Läsa.app/Contents/MacOS/Lasa -AppleLanguages '(sv-SE, en-US)'` to simulate a Swedish system. Menus are reliable; the window's accessibility tree is sometimes not populated yet, so retry or wait longer. The run uses the real `local.lasa.reader` defaults: restore any key you write.

Real screenshots (`docs/screenshot.png`): `screencapture` needs Screen Recording permission, but a process may capture its own windows without it. The same injected dylib can size the window, post Space key events with `NSApp postEvent` (they reach the Play/Pause menu shortcut), and capture the window with `CGWindowListCreateImage(…, kCGWindowListOptionIncludingWindow, windowNumber, kCGWindowImageBestResolution)`. Look the function up with `dlsym`: it is deprecated in current SDKs, but still works. Run a copy of the bundle with a different `CFBundleIdentifier` (re-sign with `codesign --force --deep -s -`), and seed that domain's defaults (`lastFilePath`, `lastPages`, `resumeMode=always`, `readingZones`, `voiceID`) with typed values from Swift; `-key value` arguments arrive as strings. Delete the domain afterwards. The README screenshot is page 21 of *Framtidens friluftsliv* (Prop. 2009/10:238, regeringen.se), zone `[0.05, 0.08, 0.70, 0.88]`, at a 1280×820 window.

Test fixtures: use one PDF with a text layer and one image-only (scanned) PDF, which goes through OCR.

## Conventions

- UI text is English with Swedish translations; spoken content is Swedish. Every new UI string needs an entry in `Packaging/sv.lproj/Localizable.strings` (same key, same format specifiers).
- New settings go in `SettingsKey` + `Settings.registerDefaults()`. Views use `@AppStorage` and the controller reads through `Settings`.
- Never name, quote, or reproduce a PDF the user shares (file name, title, page text, screenshots) in code, comments, tests, fixtures, docs, or commit messages: it may not be shareable. Describe it generically ("a two-column scanned page") and build synthetic test data.
- Run `./scripts/test.sh` and `./scripts/build-app.sh` before handing over; the README describes user-visible behaviour.
