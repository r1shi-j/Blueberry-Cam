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

## 6) Engineer's Wisdom
- Make invalid states hard to represent: if mode/resolution isn’t supported, remove it from options.
- Keep UI reactive but hardware writes explicit.
- Treat camera config changes as transactional blocks (`beginConfiguration` / `commitConfiguration`).

## 7) If I Were Starting Over...
- I would define a formal capability model earlier (per lens/per format/per output).
- I would isolate image-analysis code paths behind strategy types for easier tuning/testing.
