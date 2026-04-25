import SwiftUI

// iOS 15-compatible replacement for LabeledContent
private struct SettingsRow<Content: View>: View {
    let label: String
    let content: Content
    
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.primary)
            Spacer()
            content
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var cameraModel: CameraModel
    let resetShutterCount: () -> Void
    @State private var isShowingConfirmationAlert = false
    
    var body: some View {
        NavigationView {
            List {
                // MARK: - Defaults
                Section {
                    SettingsRow("Format") {
                        Picker("", selection: $cameraModel.defaultFileFormat) {
                            ForEach(cameraModel.availableFormats) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 150)
                    }
                    
                    if cameraModel.availableResolutions.count > 1 {
                        SettingsRow("Resolution") {
                            Picker("", selection: $cameraModel.defaultResolution) {
                                ForEach(ResolutionPreference.allCases, id: \.self) { pref in
                                    Text(pref.rawValue).tag(pref)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 150)
                        }
                    }
                    
                    SettingsRow("Small Histogram") {
                        Picker("", selection: $cameraModel.defaultHistogramSmall) {
                            ForEach(HistogramMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    SettingsRow("Large Histogram") {
                        Picker("", selection: $cameraModel.defaultHistogramLarge) {
                            ForEach(HistogramMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Text("Defaults")
                } footer: {
                    Text("These are startup defaults. Tap a histogram to cycle modes.")
                }
                
                // MARK: - Customization
                Section {
                    SettingsRow("Geotag Location") {
                        Toggle("", isOn: $cameraModel.shouldGeotagLocation)
                            .labelsHidden()
                    }
                    
                    SettingsRow("Recognize Barcodes") {
                        Toggle("", isOn: $cameraModel.recognizeBarcodes)
                            .labelsHidden()
                    }
                    
                    SettingsRow("Show Grid") {
                        Toggle("", isOn: $cameraModel.shouldShowGrid)
                            .labelsHidden()
                    }
                    
                    SettingsRow("Show Level/Crosshair") {
                        Toggle("", isOn: $cameraModel.shouldShowLevel)
                            .labelsHidden()
                    }
                } header: {
                    Text("Customization")
                } footer: {
                    Text("Clean UI hides all overlays and controls, leaving just the viewfinder and shutter. Double-tap the viewfinder to switch cameras.")
                }
                
                // MARK: - About
                Section {
                    Text("With auto focus and auto exposure, tap sets focus/exposure at that point; hold locks both. With auto focus and manual exposure, tap sets focus; hold locks it. With manual focus and auto exposure, tap sets exposure at that point.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text("Photos library access is only needed to save photos. You can set it to limited with no photos selected; the app still works.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Button("Reset Shutter Count") {
                        isShowingConfirmationAlert = true
                    }
                    .foregroundColor(.red)
                } header: {
                    Text("About")
                }
                
                // MARK: - Contact
                Section {
                    Button {
                        openMail(
                            subject: "Bug Report",
                            description: "Enter your bug report with screenshots (recommended) below this line."
                        )
                    } label: {
                        HStack {
                            Text("Bug Report").foregroundColor(.red)
                            Spacer()
                            Image(systemName: "mail").foregroundColor(.red)
                        }
                    }
                    Button {
                        openMail(
                            subject: "Feature Request",
                            description: "Enter your feature request below this line."
                        )
                    } label: {
                        HStack {
                            Text("Feature Request").foregroundColor(.blue)
                            Spacer()
                            Image(systemName: "mail").foregroundColor(.blue)
                        }
                    }
                } header: {
                    Text("Contact")
                } footer: {
                    Text("© 2026 Rishi Jansari. All Rights Reserved.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Close") { dismiss() })
            .alert(
                "Are you sure you want to reset the shutter count? This cannot be undone.",
                isPresented: $isShowingConfirmationAlert
            ) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive, action: resetShutterCount)
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private func openMail(subject: String, description: String) {
        let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "Unknown"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "?"
        let model = UIDevice.current.model
        let os = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        
        let body = """
    ————————————————————
    App: \(appName) \(version) (\(build))
    Device: \(model), \(os)
    \(description)
    ————————————————————
    """
        
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedSubject = "Blueberry Camera App: \(subject)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        if let url = URL(string: "mailto:rishi_j@icloud.com?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(cameraModel: CameraModel()) { }
    }
}
