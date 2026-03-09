# Blueberry Cam

## Project Overview
Blueberry Cam is a manual-control camera app built with SwiftUI and AVFoundation. It provides live preview, format selection (JPEG/HEIF/RAW), lens switching, manual exposure/focus controls, and a live histogram.

## Architecture Decisions
- `CameraModel` is the central state + camera control engine.
- AVFoundation capture session runs with a dedicated queue for session/config work.
- SwiftUI views are split by UI region (`TopBarView`, `BottomBarView`, `LensSelectorView`, etc.) and consume observable state from `CameraModel`.
- `AVCaptureVideoDataOutput` is used for live analysis data (histogram and overlays).

## Conventions
- SwiftUI views are small and composable.
- Camera state is surfaced as observable properties on `CameraModel`.
- Manual camera controls call explicit apply methods in the model.
- Use async/await and `Task` where practical; avoid Combine.

## Build / Run
- Open the Xcode project/workspace and run the `Blueberry Cam` app target on device.
- Camera and Photos permissions are required for full functionality.

## Quirks / Gotchas
- Lens and format capabilities vary by device.
- RAW capture availability is constrained by active lens/zoom conditions.
- Resolution options are generated from the active camera format’s supported dimensions.
