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
- Focus peaking got a more serious brain transplant after the first LiDAR attempt proved too literal. The old version tried to translate `lensPosition` into real-world meters, which is a bit like guessing a subject’s address from how far you turned a steering wheel. The new pipeline treats depth as a soft hint instead of gospel: it converts depth maps properly to `DepthFloat32`, downsamples them with bilinear filtering, estimates the center subject plane, and only nudges the peaking score toward that plane instead of hard-masking everything else into oblivion.
- The peaking detector itself now behaves less like confetti and more like a tool. We moved to denser sampling, combined Scharr-style gradients with a Laplacian/local-contrast score, added directional non-maximum suppression, and introduced a short temporal decay so highlights stop flickering frame-to-frame. Translation: edges that are genuinely crisp hang around long enough to be useful, while random sensor sparkle gets told to sit down.
- Rendering changed too. Tiny green dots were cute, but they made strong edges look weak. The overlay now uses intensity-weighted rounded cells, so stronger focus energy reads as a brighter continuous highlight instead of a sparse constellation.
- Then came the classic “well, that fixed one problem and revealed the real one” moment: broad object borders were still glowing even when the subject was soft. The fix was to stop rewarding plain contrast and start rewarding narrow, high-frequency contrast. The peaking score now subtracts a wider-radius gradient/ring contrast from the fine-detail response, which is a fancy way of saying: a soft silhouette should not win just for existing.
- Performance lesson from the next round of tuning: the expensive part was not one algorithmic sin, it was death by enthusiasm. We were still computing histogram, waveform, zebra, clipping, and peaking paths for every frame regardless of what the user could actually see. The fix was simple and unglamorous: cache the UI analysis state, skip entire branches when overlays are hidden, and throttle peaking to every other frame. Less heroics, more triage.
- Another important correction came straight from Apple’s docs: `lensPosition` is not a physical distance, but its direction still matters, and the old intuition about near/far travel was too loose to be useful. The new version estimates a focus plane from `minimumFocusDistance` plus a diopter-style curve over lens position, then uses LiDAR to strongly suppress edges that sit well outside that plane. In short: depth finally answers “is this edge near the plane I’m focused on?” instead of “is this edge somewhere in the middle of the scene?”
- Waveform bug war story: the large waveform looked like a picket fence because we were rendering an intermediate sampled grid instead of scaling the actual waveform field. The fix was two-part: use the full 512-column analysis buffer for the large view, then merge colors by density-weighted averaging instead of “winner takes all.” Same data, much less barcode energy.
- Signing war story: Xcode was tripping over two different classes of project plumbing problems at once. First, the app and extensions pointed at entitlements files that weren't present on disk. Second, the embedded targets used bundle identifiers with a different prefix shape than the parent app (`Blueberry-Cam` vs `blueberrycam`), which breaks extension embedding rules. Restoring the entitlements files and normalizing the bundle ID prefix cleared the project-level errors and exposed the remaining Apple account provisioning issue underneath.
- Photos permission war story: saving into a custom album is not just a "drop file in mailbox" operation. The app was requesting `.addOnly`, but then immediately browsing album collections like a librarian checking shelves. On devices using Limited Photos access, iOS interpreted that as "this app wants to look around the library" and surfaced the automatic "Select More Photos / Keep Current Selection" prompt after a cold launch capture. Setting `PHPhotoLibraryPreventAutomaticLimitedAccessAlert` to `YES` stopped the surprise popup so album support can be handled on the app's terms instead of iOS interrupting the shot flow.
- Picker UX lesson: hiding unsupported format and resolution buttons made the camera feel like it was rearranging the dashboard every time you touched macro or a crop lens. The fix was to split capability logic into two layers: what the current back camera can ever show, and what the current shooting state can actually use right now. In practice that means the top bar keeps a stable list of options and simply greys out the ones that are temporarily off-limits.
- Another sneaky UI bug turned out not to be an animation bug at all. Switching from selfie back to a rear camera made the resolution picker come back late, which looked like the flip animation was holding the control hostage. The real culprit was state timing: the picker was waiting for capture-session reconfiguration to finish before it learned what the destination camera supported. Precomputing the target camera's resolution options as soon as the lens switch starts made the control reappear on time, while the hardware caught up in the background.
- The camera flip animation had a sibling problem: the return trip from selfie to rear looked glitchy because the second half of the flip was running on a fixed timer while the hardware camera swap was still negotiating backstage. That meant the UI could finish the flourish before the new feed was actually live, so the old feed peeked through and then popped. The fix was to tie the flip completion to a lens-switch completion signal from the model instead of guessing with a delay. Moral of the story: when hardware is involved, "0.1 seconds ought to be enough" is usually famous last words.

## 6) Engineer's Wisdom
- Make invalid states hard to represent, but do not confuse that with making the UI mysterious. Sometimes the better move is to keep the option visible and disable it so the user can see the rule instead of guessing why a control vanished.
- Keep UI reactive but hardware writes explicit.
- Treat camera config changes as transactional blocks (`beginConfiguration` / `commitConfiguration`).

## 7) If I Were Starting Over...
- I would define a formal capability model earlier (per lens/per format/per output).
- I would isolate image-analysis code paths behind strategy types for easier tuning/testing.
