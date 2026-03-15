import SwiftUI

struct SettingsView: View {
    @Bindable var cameraModel: CameraModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Format ") {
                        Picker("", selection: $cameraModel.selectedFileFormat) {
                            ForEach(CaptureMode.allCases, id: \.self) { format in
                                Text(format.rawValue)
                                    .tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }
                    
                    LabeledContent("Resolution ") {
                        Picker("", selection: $cameraModel.preferredResolution) {
                            ForEach(ResolutionPreference.allCases, id: \.self) { pref in
                                Text(pref.rawValue)
                                    .tag(pref)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }
                    
                    LabeledContent("Geotag Location ") {
                        Toggle("", isOn: $cameraModel.shouldGeotagLocation)
                    }
                } header: {
                    Text("Image Defaults")
                } footer: {
                    Text("Preferred format and resolution will be applied automatically when supported by the lens.")
                }
                
                Section {
                    LabeledContent("Show Grid ") {
                        Toggle("", isOn: $cameraModel.shouldShowGrid)
                    }
                    
                    LabeledContent("Show Level/Crosshair ") {
                        Toggle("", isOn: $cameraModel.shouldShowLevel)
                    }
                    
                    LabeledContent("Histogram ") {
                        Picker("", selection: $cameraModel.selectedHistogram) {
                            ForEach(HistogramDefault.allCases, id: \.self) { format in
                                Text(format.rawValue)
                                    .tag(format)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Text("User Interface")
                } footer : {
                    Text("Tap the histogram to cycle through all histograms.")
                }
                
                Section {
                    Text("This app supports LockedCameraCapture which enables the app to be opened from camera control, control centre and from the lock screen action buttons. However when the app is opened from the lock screen some features arent available, these include: Histograms, Zebras, Highlight Clipping, Focus Peaking, Level, Grid, Selfie Cameras and Embedding Location. Additionally the default image format and resolution will not be applied, this required a paid Apple Developer account. The defaults used will be RAW Efficiency.")
                } header: {
                    Text("About")
                } footer: {
                    Text(" Rishi Jansari © 2026")
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
        }
    }
}

#Preview {
    @Previewable @State var cameraModel = CameraModel()
    SettingsView(cameraModel: cameraModel)
}
