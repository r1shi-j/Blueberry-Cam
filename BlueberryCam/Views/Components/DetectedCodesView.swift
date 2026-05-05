import SwiftUI

extension SettingsView {
    struct DetectedCodesSettingsSection: View {
        let cameraModel: CameraModel
        
        private var codeCountText: String {
            cameraModel.detectedCodes.count.formatted()
        }
        
        var body: some View {
            Section {
                NavigationLink {
                    DetectedCodesView(cameraModel: cameraModel)
                } label: {
                    LabeledContent {
                        Text(codeCountText)
                    } label: {
                        Label("Session Codes", systemImage: "barcode.viewfinder")
                            .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 1)).speed(0.7))
                    }
                }
            } header: {
                Text("Detected Codes")
            } footer: {
                Text("Codes are kept only until the app closes. Tap a code to copy its content.")
            }
        }
    }
    
    private struct DetectedCodesView: View {
        @Environment(\.openURL) private var openURL
        
        let cameraModel: CameraModel
        
        @State private var copiedCodeID: DetectedCode.ID?
        @State private var copyMessageTask: Task<Void, Never>?
        
        var body: some View {
            List {
                ForEach(cameraModel.detectedCodes) { code in
                    Button {
                        copy(code)
                    } label: {
                        DetectedCodeRow(code: code, isCopied: copiedCodeID == code.id)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if let linkURL = code.linkURL {
                            Button("Open Link", systemImage: "safari") {
                                openURL(linkURL)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Detected Codes")
            .onDisappear {
                copyMessageTask?.cancel()
            }
        }
        
        private func copy(_ code: DetectedCode) {
            UIPasteboard.general.string = code.content
            copiedCodeID = code.id
            copyMessageTask?.cancel()
            copyMessageTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                if !Task.isCancelled, copiedCodeID == code.id {
                    copiedCodeID = nil
                }
            }
        }
    }
    
    private struct DetectedCodeRow: View {
        let code: DetectedCode
        let isCopied: Bool
        
        var body: some View {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: code.isLink ? "link" : "barcode")
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(code.content)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    
                    Text(code.detectedAt, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(isCopied ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(.rect)
            .animation(Animations.bouncy, value: isCopied)
        }
    }
}
