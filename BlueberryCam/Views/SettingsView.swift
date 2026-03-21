import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var cameraModel: CameraModel
    let resetShutterCount: () -> Void
    @State private var isShowingConfirmationAlert = false
    
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
                    Text("Defaults")
                } footer: {
                    Text("These are all used as startup defaults. To cycle through histograms, simply tap each histogram.")
                }
                
                Section {
                    LabeledContent("Geotag Location ") {
                        Toggle("", isOn: $cameraModel.shouldGeotagLocation)
                    }
                    
                    LabeledContent("Recognize Barcodes ") {
                        Toggle("", isOn: $cameraModel.recognizeBarcodes)
                    }
                    
                    LabeledContent("Show Grid ") {
                        Toggle("", isOn: $cameraModel.shouldShowGrid)
                    }
                    
                    LabeledContent("Show Level/Crosshair ") {
                        Toggle("", isOn: $cameraModel.shouldShowLevel)
                    }
                } header: {
                    Text("Customization")
                } footer : {
                    Text("This app supports lens smudge detection and is always enabled.")
                }
                
                Section("About") {
                    Text("This app supports LockedCameraCapture which enables the app to be opened from camera control, control centre and from the lock screen action buttons. However when the app is opened from the lock screen some features arent available, these include: Histograms, Zebras, Highlight Clipping, Focus Peaking, Level, Grid, Selfie Cameras, Embedding Location and Recognising Barcodes. Settings, Clean UI view and filters will also not be available as camera control isn't available. Additionally the default image format and resolution will not be applied, this required a paid Apple Developer account. The defaults used will be Efficient High Efficiency (HEIF 12MP). To open the full app click the app icon in the bottom left (left of the shutter).")
                    Text("Photos library usage is only required to search for the album to save photos taken with this app, you can set it to limited access and select no photos, the app still work.")
                    Text("With auto focus and auto exposure, tap sets focus and exposure at the selected point, and hold locks both focus and exposure. With auto focus and manual exposure, tap sets focus and hold locks focus. With manual focus and auto exposure, tap sets exposure at the selected point.")
                    Text("There is a bug in the photos access permission, when the app asks for permissions to save the photos to an album, the user can click keep add only, allow full access and limit access. Choosing limit access opens up a photo picker to selected the photos you wish to grant access to the app, however the picker freezes and so you can't submit. The fix is to click either other option, then in settings change it to limit access.")
                    Button("Reset Shutter Count") {
                        isShowingConfirmationAlert = true
                    }
                    .tint(.red)
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
                    Text("Contact")
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
            .alert("Are you sure you want to reset the shutter count, this cannot be undone.", isPresented: $isShowingConfirmationAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive, action: resetShutterCount)
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

#Preview {
    @Previewable @State var cameraModel = CameraModel()
    SettingsView(cameraModel: cameraModel) { }
}
