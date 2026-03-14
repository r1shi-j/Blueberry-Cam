internal import AVFoundation
import LockedCameraCapture
import SwiftUI
import UIKit

// MARK: - LockedCaptureView
struct LockedCaptureView: View {
    let lockedSession: LockedCameraCaptureSession
    
    @State private var model = LockedCameraModel()
    @State private var selectedControl: ManualControl?
    
    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.ignoresSafeArea()
                
                CameraPreviewView(session: model.session) {
                    model.capturePhoto()
                }
                .ignoresSafeArea()
                
                // MARK: - UI Chrome
                VStack(spacing: 0) {
                    LockedTopBarView(model: model, selectedControl: $selectedControl)
                    
                    Spacer()
                    
                    if let selectedControl {
                        LockedManualControlsView(model: model, control: selectedControl)
                            .padding(.bottom, 8)
                    }
                    
                    LockedLensSelectorView(model: model)
                        .padding(.bottom, 23)
                    
                    LockedBottomBarView(model: model, lockedSession: lockedSession)
                        .padding(.bottom, 23)
                }
                
                // Capture flash
                if model.isCapturing {
                    Color.white.ignoresSafeArea().opacity(0.3)
                        .animation(.easeOut(duration: 0.15), value: model.isCapturing)
                }
            }
        }
        .environment(\.scenePhase, .active)
        .onAppear {
            model.configure(with: lockedSession)
        }
        .alert("Error", isPresented: $model.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage)
        }
    }
    
    private func makePreviewRect(in size: CGSize) -> CGRect {
        let aspect = model.captureAspectRatio
        let previewW: CGFloat = aspect < size.width / size.height ? size.height * aspect : size.width
        let previewH: CGFloat = aspect < size.width / size.height ? size.height : size.width / aspect
        return CGRect(x: (size.width - previewW) / 2, y: (size.height - previewH) / 2,
                      width: previewW, height: previewH)
    }
}

// MARK: - LockedTopBarView
// Matches main app TopBarView — tappable EXIF readouts open inline manual controls.
struct LockedTopBarView: View {
    @Bindable var model: LockedCameraModel
    @Binding var selectedControl: ManualControl?
    
    private func readoutColor(for control: ManualControl) -> Color {
        switch control {
            case .ev: .orange
            case .iso: .yellow
            case .ss: .white.opacity(0.8)
            case .f: .green
            case .wb: .cyan
        }
    }
    
    private func readoutTitle(for control: ManualControl) -> String {
        switch control {
            case .ev: String(format: "EV %+.1f", model.exposureBias)
            case .iso: "ISO \(Int(model.liveISO))"
            case .ss: model.liveShutter
            case .f: model.liveFocus
            case .wb: model.liveWB
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Row 1 — EXIF readouts
            HStack(alignment: .center, spacing: 22) {
                ForEach(ManualControl.allCases, id: \.self) { control in
                    Text(readoutTitle(for: control))
                        .padding(4)
                        .font(.system(size: 12,
                                      weight: selectedControl == control ? .black : .regular,
                                      design: .monospaced))
                        .underline(
                            (control == ManualControl.ev && model.exposureBias != 0.0) ||
                            (control == ManualControl.iso && !model.isAutoExposure) ||
                            (control == ManualControl.ss && !model.isAutoExposure) ||
                            (control == ManualControl.f && !model.isAutoFocus) ||
                            (control == ManualControl.wb && !model.isAutoWhiteBalance)
                        )
                        .foregroundColor(readoutColor(for: control))
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(duration: 0.5)) {
                                model.resetControl(for: control)
                            }
                        }
                        .onLongPressGesture {
                            withAnimation(.spring(duration: 0.5)) {
                                model.resetControl(for: control)
                            }
                        }
                        .disabled(control == ManualControl.ev && !model.isAutoExposure)
                        .disabled(control == ManualControl.iso && model.isAutoExposure)
                        .disabled(control == ManualControl.ss && model.isAutoExposure)
                        .disabled(control == ManualControl.f && model.isAutoFocus)
                        .disabled(control == ManualControl.wb && model.isAutoWhiteBalance)
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.5)) {
                                selectedControl = selectedControl == control ? nil : control
                            }
                        }
                }
            }
            .padding(.horizontal, 12)
            
            // Row 2 — controls strip
            HStack(alignment: .center, spacing: 10) {
                // GPS — shown but always disabled (not available in extension sandbox)
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(.capsule)
                
                // Flash
                Button {
                    withAnimation(.bouncy) { model.cycleFlashMode() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.flashLabel.systemImage)
                            .font(.system(size: 11, weight: .bold))
                        if !model.flashLabel.label.isEmpty {
                            Text(model.flashLabel.label)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                    }
                    .foregroundColor(model.flashMode == .off || !model.supportsFlash
                                     ? .white.opacity(0.7) : .black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(model.flashMode == .off || !model.supportsFlash
                                ? Color.white.opacity(0.15) : Color.yellow)
                    .clipShape(.capsule)
                }
                .opacity(model.supportsFlash ? 1.0 : 0.45)
                .disabled(!model.supportsFlash)
                
                // Resolution picker
                HStack(spacing: 0) {
                    ForEach(model.availableResolutions) { opt in
                        let isSelected = model.selectedResolution?.id == opt.id
                        Button {
                            withAnimation(.spring(.bouncy)) { model.selectResolution(opt) }
                        } label: {
                            Text(opt.label)
                                .font(.system(size: 11, weight: .medium))
                                .fontWidth(.expanded)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(isSelected ? Color.yellow : Color.white.opacity(0.15))
                                .foregroundColor(isSelected ? .black : .white)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1))
                
                // Format picker
                HStack(spacing: 0) {
                    ForEach(model.availableFormats) { mode in
                        Button {
                            withAnimation(.spring(.bouncy)) { model.captureMode = mode }
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .fontWidth(.expanded)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(model.captureMode == mode ? Color.yellow : Color.white.opacity(0.15))
                                .foregroundColor(model.captureMode == mode ? .black : .white)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .padding(.horizontal, 8)
        }
        .padding(.top, 8)
    }
}

// MARK: - LockedManualControlsView
// Mirrors ManualControlsView from main app, adapted for LockedCameraModel.
struct LockedManualControlsView: View {
    @Bindable var model: LockedCameraModel
    let control: ManualControl
    
    var body: some View {
        VStack {
            switch control {
                case .ev:
                    HStack {
                        Text("EXPOSURE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(2)
                        Spacer()
                        Toggle("Auto", isOn: $model.isAutoExposure)
                            .labelsHidden().tint(.yellow)
                            .onChange(of: model.isAutoExposure) { _, auto in
                                if auto { model.setAutoExposure() }
                                else {
                                    model.exposureBias = 0.0
                                    model.applyManualExposure()
                                }
                            }
                        Text(model.isAutoExposure ? "AUTO" : "MANUAL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(model.isAutoExposure ? .yellow : .white)
                    }
                    .padding(.horizontal, 20)
                    
                    if model.isAutoExposure {
                        HStack {
                            Text("EV")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5)).tracking(2)
                                .frame(width: 60, alignment: .leading)
                            Slider(value: $model.exposureBias, in: -4.0...4.0, step: 0.1)
                                .onChange(of: model.exposureBias) { _, _ in model.applyExposureBias() }
                                .tint(.yellow)
                            Text(String(format: "%+.1f", model.exposureBias))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.yellow).frame(width: 50, alignment: .trailing)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                case .iso:
                    HStack {
                        Text("EXPOSURE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5)).tracking(2)
                        Spacer()
                        Toggle("Auto", isOn: $model.isAutoExposure)
                            .labelsHidden().tint(.yellow)
                            .onChange(of: model.isAutoExposure) { _, auto in
                                if auto { model.setAutoExposure() }
                                else {
                                    model.exposureBias = 0.0
                                    model.applyManualExposure()
                                }
                            }
                        Text(model.isAutoExposure ? "AUTO" : "MANUAL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(model.isAutoExposure ? .yellow : .white)
                    }
                    .padding(.horizontal, 20)
                    
                    if !model.isAutoExposure {
                        HStack {
                            Text("ISO")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5)).tracking(2)
                                .frame(width: 60, alignment: .leading)
                            Slider(value: $model.iso, in: model.minISO...model.maxISO, step: 1)
                                .onChange(of: model.iso) { _, _ in model.applyManualExposure() }
                                .tint(.yellow)
                            Text("\(Int(model.iso))")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.yellow).frame(width: 50, alignment: .trailing)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                case .ss:
                    HStack {
                        Text("EXPOSURE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5)).tracking(2)
                        Spacer()
                        Toggle("Auto", isOn: $model.isAutoExposure)
                            .labelsHidden().tint(.yellow)
                            .onChange(of: model.isAutoExposure) { _, auto in
                                if auto { model.setAutoExposure() }
                                else {
                                    model.exposureBias = 0.0
                                    model.applyManualExposure()
                                }
                            }
                        Text(model.isAutoExposure ? "AUTO" : "MANUAL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(model.isAutoExposure ? .yellow : .white)
                    }
                    .padding(.horizontal, 20)
                    
                    if !model.isAutoExposure {
                        HStack {
                            Text("SHUTTER")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5)).tracking(2)
                                .frame(width: 60, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { Double(model.shutterIndex) },
                                    set: { model.shutterIndex = Int($0); model.applyManualExposure() }
                                ),
                                in: 0...Double(max(0, model.shutterSpeeds.count - 1)),
                                step: 1
                            )
                            .tint(.yellow)
                            Text(model.shutterSpeeds.indices.contains(model.shutterIndex)
                                 ? LockedCameraModel.formatShutter(model.shutterSpeeds[model.shutterIndex])
                                 : "--")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.yellow).frame(width: 65, alignment: .trailing)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                case .f:
                    HStack {
                        Text("FOCUS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5)).tracking(2)
                        Spacer()
                        Toggle("", isOn: $model.isAutoFocus)
                            .labelsHidden().tint(.yellow)
                            .disabled(!model.supportsManualFocus)
                            .onChange(of: model.isAutoFocus) { _, auto in
                                if auto { model.setAutoFocus() } else { model.applyManualFocus() }
                            }
                        Text(model.isAutoFocus ? "AUTO" : "MANUAL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(model.isAutoFocus ? .yellow : .white)
                    }
                    .padding(.horizontal, 20)
                    
                    if !model.isAutoFocus {
                        HStack {
                            Text("").frame(width: 60, alignment: .leading)
                            Slider(value: $model.lensPosition, in: 0...1,
                                   onEditingChanged: { editing in
                                if editing { model.beginManualFocusAdjustment() }
                                else       { model.endManualFocusAdjustment() }
                            })
                            .onChange(of: model.lensPosition) { _, _ in model.applyManualFocus() }
                            .tint(.yellow)
                            Text(String(format: "%.2f", model.lensPosition))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.yellow).frame(width: 50, alignment: .trailing)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                case .wb:
                    HStack {
                        Text("WHITE BALANCE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5)).tracking(2)
                        Spacer()
                        Toggle("", isOn: $model.isAutoWhiteBalance)
                            .labelsHidden().tint(.yellow)
                        Text(model.isAutoWhiteBalance ? "AUTO" : "MANUAL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(model.isAutoWhiteBalance ? .yellow : .white)
                    }
                    .padding(.horizontal, 20)
                    
                    if !model.isAutoWhiteBalance {
                        HStack {
                            Text("").frame(width: 60, alignment: .leading)
                            Slider(value: $model.whiteBalanceTargetKelvin, in: 2000...10000, step: 100)
                                .tint(.yellow)
                            Text("\(Int(model.whiteBalanceTargetKelvin))K")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.yellow).frame(width: 65, alignment: .trailing)
                        }
                        .padding(.horizontal, 20)
                    }
            }
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.65))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
        .padding(.horizontal, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - LockedLensSelectorView
// Back cameras only — front cameras are unavailable on the lock screen.
struct LockedLensSelectorView: View {
    @Bindable var model: LockedCameraModel
    @State private var count = 0
    
    private let lenses: [Lens] = [.ultraWide, .wide, .tele2x, .tele4x, .tele8x]
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(lenses, id: \.self) { lens in
                let isActive = model.activeLens == lens
                Button {
                    model.switchLens(to: lens)
                    count += 1
                } label: {
                    Text(lens.label)
                        .font(.system(size: 14, weight: isActive ? .bold : .regular, design: .monospaced))
                        .foregroundColor(isActive ? .yellow : .white.opacity(0.7))
                        .frame(minWidth: 36, minHeight: 36)
                        .background(isActive ? Color.white.opacity(0.15) : Color.clear)
                        .clipShape(.circle)
                }
                .sensoryFeedback(.selection, trigger: count)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.4))
        .clipShape(.capsule)
    }
}

// MARK: - LockedBottomBarView
struct LockedBottomBarView: View {
    @Bindable var model: LockedCameraModel
    let lockedSession: LockedCameraCaptureSession
    @State private var count = 0
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Open full app — replaces the applelogo placeholder.
            // lockedSession.openApplication() is the approved way to launch
            // the main app from a LockedCameraCaptureExtension.
            Button {
                Task {
                    let activity = NSUserActivity(activityType: "com.jansari.rishi.Blueberry-Cam.opencamera")
                    try? await lockedSession.openApplication(for: activity)
                }
            } label: {
                VStack(spacing: 4) {
                    Image("camera.blueberry")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.black, Color.blue, Color.green)
                        .padding()
                        .clipShape(.circle)
                        .glassEffect(.regular.interactive().tint(.white.mix(with: .teal, by: 0.4)), in: .circle)
                    Text("OPEN")
                        .font(.caption)
                        .fontWidth(.expanded)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.top)
            }
            .frame(maxWidth: .infinity)
            
            // Shutter button — same style as main app
            ZStack {
                Circle()
                    .frame(width: 82, height: 82)
                    .glassEffect(.regular.tint(model.captureMode == .raw ? .blue.mix(with: .mint, by: 0.5).opacity(0.4) : .white.opacity(0.2)).interactive())
                Button {
                    model.capturePhoto()
                    count += 1
                } label: {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 69, height: 69)
                }
                .glassEffect(.regular.interactive())
                .sensoryFeedback(.selection, trigger: count)
            }
            .frame(maxWidth: .infinity)
            
            // Right side placeholder — keeps shutter centred
            Button {
                
            } label: {
                Image(systemName: "applelogo")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .disabled(true)
        }
    }
}
