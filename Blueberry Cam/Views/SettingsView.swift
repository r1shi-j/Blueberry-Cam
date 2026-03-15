import SwiftUI

struct SettingsView: View {
    @Bindable var cameraModel: CameraModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Geotag Location ") {
                        Toggle("", isOn: $cameraModel.shouldGeotagLocation)
                    }
                } header: { Text("Defaults") } footer: {
                    VStack(alignment: .leading) {
                        Text("If geotag location is on, the location will be automatically captured")
                    }
                }
                
                Section("User Interface") {
                    LabeledContent("Show Grid ") {
                        Toggle("", isOn: $cameraModel.shouldShowGrid)
                    }
                    
                    LabeledContent("Show Level/Crosshair ") {
                        Toggle("", isOn: $cameraModel.shouldShowLevel)
                    }
                }
                
                Section {
                    Text("Some things that arent available in the LockedCaptureView")
                    Text("Histograms, Zebras, Highlight Clipping, Focus Peaking, Level, Grid, Selfie Cameras, Embedding Location")
                } header: {
                  Text("Help")
                } footer: {
                    Text("Rishi Jansari")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
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
