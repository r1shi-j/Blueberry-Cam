import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var cameraModel: CameraModel
    @Binding var shutterCount: Int
    @Binding var shutterCountBurst: Int
    let resetToDefaults: () -> ()
    @State private var isShowingDefaultsResetAlert = false
    @State private var countResetTarget: ShutterCountResetTarget?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Format ") {
                        Picker("", selection: $cameraModel.defaultFileFormat) {
                            ForEach(CaptureMode.allCases, id: \.self) { format in
                                Text(format.rawValue)
                                    .tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }
                    
                    LabeledContent("Resolution ") {
                        Picker("", selection: $cameraModel.defaultResolution) {
                            ForEach(ResolutionPreference.allCases, id: \.self) { pref in
                                Text(pref.rawValue)
                                    .tag(pref)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }
                    
                    LabeledContent("Filter ") {
                        Picker("", selection: $cameraModel.defaultPhotoFilter) {
                            ForEach(PhotoFilter.allCases, id: \.self) { filter in
                                Text(filter.rawValue)
                                    .tag(filter)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    LabeledContent("Small Histogram ") {
                        Picker("", selection: $cameraModel.defaultHistogramSmall) {
                            ForEach(HistogramMode.allCases, id: \.self) { format in
                                Text(format.rawValue)
                                    .tag(format)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    LabeledContent("Large Histogram ") {
                        Picker("", selection: $cameraModel.defaultHistogramLarge) {
                            ForEach(HistogramMode.allCases, id: \.self) { format in
                                Text(format.rawValue)
                                    .tag(format)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    HStack {
                        Text("Capture Defaults")
                        Spacer()
                        Image(systemName: "pencil.and.list.clipboard")
                    }
                } footer: {
                    Text("Used when the app starts.")
                }
                
                Section {
                    Toggle("Geotag Location", isOn: $cameraModel.shouldGeotagLocation)
                    Toggle("Faster Burst Capture", isOn: $cameraModel.shouldPrioritizeBurstSpeed)
                    Toggle("Burst Feedback", isOn: $cameraModel.shouldShowBurstFeedback)
                    Toggle("Precise Timer", isOn: $cameraModel.detailedCountdownTimer)
                    Toggle("Hide UI When Counting Down", isOn: $cameraModel.shouldHideUIWhileCountingDown)
                    Toggle("Capture Celebration", isOn: $cameraModel.shouldShowConfettiCannons)
                } header: {
                    HStack {
                        Text("Capture Behaviour")
                        Spacer()
                        Image(systemName: "paintbrush.fill")
                    }
                } footer: {
                    Text("Faster burst capture prioritises speed over quality. Burst feedback shows a quick summary when a burst finishes. Precise Timer shows milliseconds instead of just seconds. Lens smudge detection is supported and always enabled.")
                }
                
                Section {
                    Toggle("Grid", isOn: $cameraModel.shouldShowGrid)
                    Toggle("Level/Crosshair", isOn: $cameraModel.shouldShowLevel)
                    Toggle("Recognize Barcodes", isOn: $cameraModel.recognizeBarcodes)
                } header: {
                    HStack {
                        Text("Viewfinder")
                        Spacer()
                        Image(systemName: "scope")
                    }
                }
                                
                NavigationLink {
                    Form {
                        Text("Locked Capture opens BLueberry Cam from system surfaces like Control Centre and the Lock Screen. Some full-app features are unavailable there, including bursts, capture celebrations, overlays such as historgrams, zebras, highlight clipping, focus peaking, focus loupe, level and grid, as well as selfie cameras, geotagging location, recognising barcodes. Settings, clean UI and filters will also not be available. Any settings above which you have changed will not be read and so the defaults the app shipped with will be used.")
                        Text("You can open the full app from the locked session by clicking the icon in the bottom left.")
                        Text("Photos library usage is only required to search for the album to save photos taken with this app, you can set it to limited access and select no photos, the app still work.")
                        
                        Section("Features") {
                            Text("With auto focus and auto exposure, tap sets focus and exposure at the selected point, and hold locks both focus and exposure. With auto focus and manual exposure, tap sets focus and hold locks focus. With manual focus and auto exposure, tap sets exposure at the selected point.")
                            Text("With manual controls holding or double tapping will reset it to auto, with manual burst config, double tapping resets to auto.")
                            Text("Tap on a histogram to cycle through, long press to hide it. When both are hidden they can be reshown by tapping the histogram icon in the top left status bar.")
                            Text("Double tapping the camera preview will switch to selfie mode as an alternative to tapping the camera flip icon above the camera preview.")
                        }
                    }
                    .navigationTitle("About")
                } label: {
                    HStack {
                        Text("About")
                        Spacer()
                        Image(systemName: "info.circle")
                    }
                }
                
                Section {
                    Button {
                        isShowingDefaultsResetAlert = true
                    } label: {
                        LabeledContent("Reset to Defaults") { Image(systemName: "exclamationmark.arrow.trianglehead.counterclockwise.rotate.90") }
                            .tint(.red)
                    }
                    
                    // TODO: Reset tips
                    
                    LabeledContent {
                        Text(shutterCount.formatted())
                    } label: {
                        Button("Reset Shutter Count") {
                            countResetTarget = .standard
                        }
                        .tint(.red)
                    }
                    
                    LabeledContent {
                        Text(shutterCountBurst.formatted())
                    } label: {
                        Button("Reset Burst Shutter Count") {
                            countResetTarget = .burst
                        }
                        .tint(.red)
                    }
                } header: {
                    HStack {
                        Text("Danger Zone")
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                }
                
                Section {
                    Button {
                        openMail(subject: "Bug Report", description: "Enter your bug report with screenshots (recommended) below this line.")
                    } label: {
                        LabeledContent("Bug Report") { Image(systemName: "mail") }
                            .tint(.red)
                    }
                    Button {
                        openMail(subject: "Feature Request", description: "Enter your feature request with any mockup sketches below this line. Describe your feature in detail to the best of your extent.")
                    } label: {
                        LabeledContent("Feature Request") { Image(systemName: "mail") }
                            .tint(.blue)
                    }
                } header: {
                    HStack {
                        Text("Contact")
                        Spacer()
                        Image(systemName: "signpost.right.and.left.fill")
                    }
                } footer: {
                    Text("© 2026 Rishi Jansari . All Rights Reserved.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Are you sure you want to reset all custom settings?", isPresented: $isShowingDefaultsResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive, action: resetToDefaults)
            }
            .alert(countResetTarget?.confirmationTitle ?? "", isPresented: Binding(get: {
                countResetTarget != nil
            }, set: { isPresented in
                if !isPresented {
                    countResetTarget = nil
                }
            })) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    switch countResetTarget {
                        case .standard:
                            shutterCount = 0
                        case .burst:
                            shutterCountBurst = 0
                        case nil:
                            break
                    }
                    countResetTarget = nil
                }
            }
        }
    }
    
    private func openMail(subject: String, description: String) {
        let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "Unknown"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "?"
        let model = UIDevice.current.model
        let os = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        
        let body = """
    ————————————————————————
    App: \(appName) \(version) (\(build))
    Device: \(model), \(os)
    \(description)
    ————————————————————————
    """
        
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedSubject = "Blueberry Camera App: \(subject)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        if let url = URL(string: "mailto:rishi_j@icloud.com?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }
}

private enum ShutterCountResetTarget {
    case standard
    case burst
    
    var confirmationTitle: String {
        switch self {
            case .standard:
                "Are you sure you want to reset the shutter count, this cannot be undone."
            case .burst:
                "Are you sure you want to reset the burst shutter count, this cannot be undone."
        }
    }
}

#Preview {
    @Previewable @State var cameraModel = CameraModel()
    @Previewable @State var shutterCount = 0
    @Previewable @State var shutterCountBurst = 0
    SettingsView(
        cameraModel: cameraModel,
        shutterCount: $shutterCount,
        shutterCountBurst: $shutterCountBurst) { }    
}
