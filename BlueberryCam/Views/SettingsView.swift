import ConfettiSwiftUI
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) private var openURL
    
    @Bindable var cameraModel: CameraModel
    @Binding var appBackgroundColorIndex: Int
    @Binding var shutterCount: Int
    @Binding var shutterCountBurst: Int
    let resetToDefaults: () -> ()
    
    @State private var confettiCount = 0
    @State private var isShowingDefaultsResetAlert = false
    @State private var isShowingFileLocationImporter = false
    @State private var countResetTarget: ShutterCountResetTarget?
    
    var body: some View {
        NavigationStack {
            List {
                if !cameraModel.detectedCodes.isEmpty {
                    DetectedCodesSettingsSection(cameraModel: cameraModel)
                }
                
                Section {
                    LabeledContent("Save Location ") {
                        Picker("", selection: saveLocationSelection) {
                            ForEach(SaveLocation.allCases) { location in
                                Text(location.rawValue)
                                    .tag(location)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }
                    
                    if cameraModel.saveLocation == .files {
                        LabeledContent("Folder") {
                            HStack(spacing: 10) {
                                Button("Reset Folder", systemImage: "arrow.counterclockwise.circle.fill", action: cameraModel.resetFileSaveLocationToDefault)
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.red)
                                
                                Button {
                                    isShowingFileLocationImporter = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: cameraModel.isFileSaveLocationAvailable ? "folder" : "exclamationmark.triangle.fill")
                                            .foregroundStyle(cameraModel.isFileSaveLocationAvailable ? Color.secondary : Color.red)
                                        Text(cameraModel.fileSaveLocationName)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        
                        if !cameraModel.isFileSaveLocationAvailable, let issue = cameraModel.fileSaveLocationIssue {
                            Text(issue)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    
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
                            .symbolEffect(.bounce, options: .repeat(.periodic(delay: 1)).speed(0.7))
                    }
                } footer: {
                    Text("Used when the app starts.")
                }
                .animation(Animations.easeInOut, value: cameraModel.saveLocation)
                .animation(Animations.easeInOut, value: cameraModel.isFileSaveLocationAvailable)
                
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
                        Image(systemName: "camera.shutter.button")
                            .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1)).speed(0.7))
                    }
                } footer: {
                    Text("Faster burst capture prioritises speed over quality. Burst feedback shows a quick summary when a burst finishes. Precise Timer shows milliseconds instead of just seconds. Lens smudge detection is supported and always enabled.")
                }
                
                Section {
                    Toggle("Grid", isOn: $cameraModel.shouldShowGrid)
                    Toggle("Level/Crosshair", isOn: $cameraModel.shouldShowLevel)
                    Toggle("Recognize Barcodes", isOn: $cameraModel.recognizeBarcodes)
                    Toggle("Smart Selfie Framing", isOn: $cameraModel.isSmartSelfieFramingEnabled)
                        .disabled(!cameraModel.isSmartSelfieFramingAvailable)
                } header: {
                    HStack {
                        Text("Viewfinder")
                        Spacer()
                        Image(systemName: "scope")
                            .symbolEffect(.bounce, options: .repeat(.periodic(delay: 1)).speed(0.7))
                    }
                } footer: {
                    Text(cameraModel.isSmartSelfieFramingAvailable ? "Uses supported selfie cameras to enable Center Stage and apply recommended selfie aspect and zoom. RAW keeps recommended aspect only." : "Smart Selfie Framing is unavailable on this device.")
                }
                
                NavigationLink {
                    Form {
                        Text("Locked Capture opens Blueberry Cam from system surfaces like Control Centre and the Lock Screen. Some full-app features are unavailable there, including bursts, dualcam, capture celebrations, overlays such as histograms, zebras, highlight clipping, focus peaking, focus loupe, level and grid, as well as selfie cameras, geotagging location, recognising barcodes. Settings, clean UI and filters will also not be available. Any settings above which you have changed will not be read and so the defaults the app shipped with will be used. Photos captured will be saved to photos not files. The background color will be black.")
                        Text("You can open the full app from the locked session by clicking the icon in the bottom left.")
                        Text("Photos library usage is only required to search for the album to save photos taken with this app, you can set it to limited access and select no photos, the app still work.")
                        
                        Section("Features") {
                            Text("With auto focus and auto exposure, tap sets focus and exposure at the selected point, and hold locks both focus and exposure. With auto focus and manual exposure, tap sets focus and hold locks focus. With manual focus and auto exposure, tap sets exposure at the selected point.")
                            Text("With manual controls holding or double tapping will reset it to auto, with manual burst config, double tapping resets to auto.")
                            Text("Tap on a histogram to cycle through, long press to hide it. When both are hidden they can be reshown by tapping the histogram icon in the top left status bar.")
                            Text("Double tapping the camera preview will switch to selfie mode as an alternative to tapping the camera flip icon above the camera preview.")
                            Text("Applying a filter disables any overlays.")
                            Text("Dualcam disables overlays, filters, and manual controls.")
                            Text("Smart selfie framing is only available on iPhone 17 selfie cameras.")
                        }
                    }
                    .navigationTitle("About")
                } label: {
                    HStack {
                        Text("About")
                        Spacer()
                        Image(systemName: "info.circle")
                            .symbolEffect(.rotate.byLayer, options: .repeat(.periodic(delay: 1)).speed(0.7))
                    }
                }
                
                Section {
                    NavigationLink {
                        ZStack {
                            Color.black.ignoresSafeArea()
                                .overlay(backgroundColors[appBackgroundColorIndex].opacity(0.5))
                            Form {
                                ForEach(backgroundColors.indices, id: \.self) { index in
                                    Button {
                                        appBackgroundColorIndex = index
                                    } label: {
                                        HStack {
                                            Circle()
                                                .fill(.black)
                                                .overlay {
                                                    Circle()
                                                        .fill(backgroundColors[index])
                                                }
                                                .frame(width: 20, height: 20)
                                            
                                            Spacer()
                                            
                                            if appBackgroundColorIndex == index {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                            .scrollContentBackground(.hidden)
                        }
                        .environment(\.colorScheme, .dark)
                        .navigationTitle("App Background")
                        .toolbarColorScheme(.dark, for: .navigationBar)
                        .tint(.white)
                    } label: {
                        HStack {
                            Text("App Background")
                            Spacer()
                            Circle()
                                .fill(.black)
                                .overlay {
                                    Circle()
                                        .fill(backgroundColors[appBackgroundColorIndex])
                                }
                                .frame(width: 20, height: 20)
                        }
                    }
                    
                    // Text("Accent Color")
                    // Text("App Icon")
                } header: {
                    HStack {
                        Text("Customisation")
                        Spacer()
                        Image(systemName: "paintbrush.fill")
                            .symbolEffect(.bounce, options: .repeat(.periodic(delay: 1)).speed(0.7))
                    }
                }
                
                Section {
                    Button {
                        isShowingDefaultsResetAlert = true
                    } label: {
                        LabeledContent("Reset to Defaults") {
                            Image(systemName: "exclamationmark.arrow.trianglehead.counterclockwise.rotate.90")
                                .symbolEffect(.rotate.byLayer.counterClockwise, options: .repeat(.periodic(delay: 1)).speed(0.7))
                        }
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
                            .symbolEffect(.bounce, options: .repeat(.periodic(delay: 1)).speed(0.7))
                    }
                }
                
                Section {
                    Button {
                        openMail(subject: "Bug Report", description: "Enter your bug report with screenshots (recommended) below this line.")
                    } label: {
                        LabeledContent("Bug Report") {
                            Image(systemName: "mail")
                                .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1)).speed(0.7))
                        }
                        .tint(.red)
                    }
                    Button {
                        openMail(subject: "Feature Request", description: "Enter your feature request with any mockup sketches below this line. Describe your feature in detail to the best of your extent.")
                    } label: {
                        LabeledContent("Feature Request") {
                            Image(systemName: "mail")
                                .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1)).speed(0.7))
                        }
                        .tint(.blue)
                    }
                } header: {
                    HStack {
                        Text("Contact")
                        Spacer()
                        Image(systemName: "signpost.right.and.left.fill")
                            .symbolEffect(.bounce, options: .repeat(.periodic(delay: 1)).speed(0.7))
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
            .alert(Alerts.resetSettingsTitle, isPresented: $isShowingDefaultsResetAlert) {
                Button(Alerts.cancel, role: .cancel) { }
                Button(Alerts.reset, role: .destructive, action: resetToDefaults)
            }
            .alert(countResetTarget?.confirmationTitle ?? "", isPresented: Binding(get: {
                countResetTarget != nil
            }, set: { isPresented in
                if !isPresented {
                    countResetTarget = nil
                }
            })) {
                Button(Alerts.cancel, role: .cancel) { }
                Button(Alerts.reset, role: .destructive) {
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
            .fileImporter(
                isPresented: $isShowingFileLocationImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false,
                onCompletion: handleFileLocationImport
            )
            .onChange(of: cameraModel.shouldShowConfettiCannons) { _, new in
                if new {
                    confettiCount += 1
                }
            }
        }
        .overlay {
            VStack {
                Spacer()
                HStack {
                    ConfettiCannon(
                        trigger: $confettiCount,
                        num: 50,
                        confettis: ConfettiObjects.left,
                        confettiSize: 12,
                        rainHeight: 800,
                        openingAngle: .degrees(45),
                        closingAngle: .degrees(75),
                        radius: 350
                    )
                    
                    ConfettiCannon(
                        trigger: $confettiCount,
                        num: 50,
                        confettis: ConfettiObjects.right,
                        confettiSize: 12,
                        rainHeight: 800,
                        openingAngle: .degrees(105),
                        closingAngle: .degrees(135),
                        radius: 350
                    )
                }
                .padding()
            }
        }
    }
    
    private func handleFileLocationImport(_ result: Result<[URL], Error>) {
        switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                cameraModel.selectFileSaveLocation(url)
            case .failure(let error):
                cameraModel.fileSaveLocationIssue = error.localizedDescription
                cameraModel.isFileSaveLocationAvailable = false
                cameraModel.errorMessage = error.localizedDescription
                cameraModel.showError = true
        }
    }
    
    private var saveLocationSelection: Binding<SaveLocation> {
        Binding {
            cameraModel.saveLocation
        } set: { newValue in
            withAnimation(Animations.easeInOut) {
                cameraModel.saveLocation = newValue
            }
        }
    }
    
    private func openMail(subject: String, description: String) {
        let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "Unknown"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "?"
        let model = UIDevice.current.model
        let os = "\(ProcessInfo.processInfo.operatingSystemVersionString)"
        
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
            openURL(url)
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
    @Previewable @State var appBackgroundColorIndex = 2
    @Previewable @State var shutterCount = 0
    @Previewable @State var shutterCountBurst = 0
    SettingsView(
        cameraModel: cameraModel,
        appBackgroundColorIndex: $appBackgroundColorIndex,
        shutterCount: $shutterCount,
        shutterCountBurst: $shutterCountBurst) { }
}
