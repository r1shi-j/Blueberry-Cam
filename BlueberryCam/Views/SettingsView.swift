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
                    
                    LabeledContent("Recognize Barcodes ") {
                        Toggle("", isOn: $cameraModel.recognizeBarcodes)
                    }
                } header: {
                    Text("Image Defaults")
                } footer: {
                    Text("Preferred format and resolution will be automatically selected when supported by the lens.")
                }
                
                Section {
                    LabeledContent("Show Grid ") {
                        Toggle("", isOn: $cameraModel.shouldShowGrid)
                    }
                    
                    LabeledContent("Show Level/Crosshair ") {
                        Toggle("", isOn: $cameraModel.shouldShowLevel)
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
                    Text("User Interface Defaults")
                } footer : {
                    Text("Tap the histogram to cycle through all histograms.")
                }
                
                Section {
                    Text("This app supports LockedCameraCapture which enables the app to be opened from camera control, control centre and from the lock screen action buttons. However when the app is opened from the lock screen some features arent available, these include: Histograms, Zebras, Highlight Clipping, Focus Peaking, Level, Grid, Selfie Cameras, Embedding Location and Recognising Barcodes. Settings, Clean UI view and filters will also not be available as camera control isn't available. Additionally the default image format and resolution will not be applied, this required a paid Apple Developer account. The defaults used will be RAW Efficiency. To open the full app click the app icon in the bottom left (left of the shutter).")
                    Text("Photos library usage is only required to search for the album to save photos taken with this app, you can set it to limited access and select no photos, the app still work.")
                    Text("With auto focus and auto exposure, tap sets focus and exposure at the selected point, and hold locks both focus and exposure. With auto focus and manual exposure, tap sets focus and hold locks focus. With manual focus and auto exposure, tap sets exposure at the selected point.")
                    Button("Reset Shutter Count") {
                        isShowingConfirmationAlert = true
                    }
                    .tint(.red)
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
            .alert("Are you sure you want to reset the shutter count, this cannot be undone.", isPresented: $isShowingConfirmationAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive, action: resetShutterCount)
            }
        }
    }
}

#Preview {
    @Previewable @State var cameraModel = CameraModel()
    SettingsView(cameraModel: cameraModel) { }
}
