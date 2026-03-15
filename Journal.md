# Journal - Blueberry Cam

## 1) The Big Picture
Blueberry Cam is the camera app you open when the stock camera feels too automatic. Think of it as a pocket-sized manual camera body: you pick lens, format, exposure, and focus while seeing the results in real time.

## 2) Architecture Deep Dive
The app runs like a restaurant kitchen:
- `CameraModel` is the head chef: it coordinates ingredients (camera devices), stations (capture outputs), and final plating (saved photos).
- SwiftUI views are front-of-house: each view owns one slice of presentation and sends user intent back to the chef.
- AVFoundation is the stove line: it does the heavy lifting for session setup, sensor controls, and capture.

## 3) The Codebase Map
- `CameraModel.swift`: core session setup, controls, capture, save flow, and live analysis.
- `ContentView.swift`: root composition of preview + overlays + controls.
- `CameraPreviewView.swift`: SwiftUI-to-UIKit bridge for `AVCaptureVideoPreviewLayer`.
- `TopBarView.swift` / `BottomBarView.swift`: format/resolution/status and shutter/manual controls.
- `LensSelectorView.swift`: lens and camera-facing selection.
- `ManualControlsView.swift`: exposure + focus controls.
- `HistogramView.swift`: live luminance histogram UI.
- `CropOverlayView.swift`: framing mask and corner guides.

## 4) Tech Stack & Why
- SwiftUI: fast UI iteration and clear component boundaries.
- AVFoundation: direct camera hardware control and capture pipeline.
- Photos framework: persistence to user library.
- Swift Concurrency: clearer async flows and reduced callback nesting.

## 5) The Journey
- We intentionally centralized camera logic in one model to avoid scattered state.
- A recurring pitfall is device capability mismatch: not every lens/mode supports every capture option.
- Lesson learned: derive UI options from hardware capabilities every time lens/mode changes.
- Added live focus peaking and zebra overlays using the video output stream. The trick was to keep it fast: downsample first, then compute simple edge/highlight masks.
- Gotcha we avoided: doing expensive per-pixel work at full resolution can tank preview smoothness. A coarse analysis grid gives responsive overlays without choking the UI.
- Bug war story: overlays initially looked “haunted” (zebras in wrong places). Root causes were orientation mismatch at startup and drawing the analysis mask across the whole screen instead of the preview rect. Fixing rotation setup and constraining the overlay to the camera rect snapped indicators back into place.
- Added flash mode cycling (`OFF -> AUTO -> ON`) with AVFoundation safety checks. Key lesson: always gate requested flash mode against `photoOutput.supportedFlashModes` to avoid invalid capture requests.
- Added a hard rule for manual exposure mode: force format to RAW and force flash OFF, then disable both controls in UI. This prevents contradictory states where users set ISO/shutter manually but still request processed/flash capture paths.
- Added “pull focus peaking”: while manually adjusting focus, the app automatically shows peaking highlights (now green) and then fades them shortly after slider release. This mirrors how pro camera apps make focus pulls easier without forcing a persistent overlay.
- Refined peaking to look less “paint bucket” and more surgical: switched to Sobel-based edge scoring, adaptive thresholding, local-maximum filtering, and tiny dot rendering. Result: fewer false positives and much tighter in-focus indicators, closer to the Halide feel.
- Follow-up tuning after real-device feedback: peaking now stays visible for the full duration of manual-focus mode (not just slider drag), and thresholding was tightened again using stronger adaptive + relative-to-max gating to cut noisy “everywhere dots.”
- Additional real-world tuning for blur scenes: increased edge thresholding again and added a cluster filter that drops isolated peaks. This specifically targets false positive “sparkle dots” when the frame is broadly out of focus.
- Waveform bug war story: the large waveform looked like a picket fence because we were rendering an intermediate sampled grid instead of scaling the actual waveform field. The fix was two-part: use the full 512-column analysis buffer for the large view, then merge colors by density-weighted averaging instead of “winner takes all.” Same data, much less barcode energy.
- Signing war story: Xcode was tripping over two different classes of project plumbing problems at once. First, the app and extensions pointed at entitlements files that weren't present on disk. Second, the embedded targets used bundle identifiers with a different prefix shape than the parent app (`Blueberry-Cam` vs `blueberrycam`), which breaks extension embedding rules. Restoring the entitlements files and normalizing the bundle ID prefix cleared the project-level errors and exposed the remaining Apple account provisioning issue underneath.
- Photos permission war story: saving into a custom album is not just a "drop file in mailbox" operation. The app was requesting `.addOnly`, but then immediately browsing album collections like a librarian checking shelves. On devices using Limited Photos access, iOS interpreted that as "this app wants to look around the library" and surfaced the automatic "Select More Photos / Keep Current Selection" prompt after a cold launch capture. Setting `PHPhotoLibraryPreventAutomaticLimitedAccessAlert` to `YES` stopped the surprise popup so album support can be handled on the app's terms instead of iOS interrupting the shot flow.

## 6) Engineer's Wisdom
- Make invalid states hard to represent: if mode/resolution isn’t supported, remove it from options.
- Keep UI reactive but hardware writes explicit.
- Treat camera config changes as transactional blocks (`beginConfiguration` / `commitConfiguration`).

## 7) If I Were Starting Over...
- I would define a formal capability model earlier (per lens/per format/per output).
- I would isolate image-analysis code paths behind strategy types for easier tuning/testing.