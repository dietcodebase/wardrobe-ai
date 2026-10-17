import SwiftUI
import UniformTypeIdentifiers

@main
struct QualificationApp: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

struct ProbeView: View {
    @State private var mode: ProbeMode = .text
    @State private var mtp = false
    @State private var e4b = false
    @State private var importing = false
    @State private var running = false
    @State private var status = "Choose a capability and a folder containing verified models and synthetic fixtures."
    @State private var report: URL?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Capability", selection: $mode) {
                    ForEach(ProbeMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("MTP (separate on/off runs)", isOn: $mtp)
                Toggle("E4B (optional, after E2B)", isOn: $e4b)
                Button(mode == .switching ? "Select folder and run 10 switching cycles" : "Select folder and run 20 operations") { importing = true }
                Text(status)
                if let report { ShareLink("Export measurements", item: report) }
            }
            .disabled(running)
            .navigationTitle("M01 Qualification")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { selection in
                switch selection {
                case .failure(let error): status = error.localizedDescription
                case .success(let folder):
                    running = true
                    status = "Running. Keep the app foreground. Capture peak memory with Instruments."
                    let selectedMode = mode, selectedMTP = mtp, selectedE4B = e4b
                    Task {
                        guard folder.startAccessingSecurityScopedResource() else {
                            status = "Folder access denied."; running = false; return
                        }
                        defer { folder.stopAccessingSecurityScopedResource(); running = false }
                        let id = UUID().uuidString
                        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        let output = documents.appendingPathComponent("probe-\(id).json")
                        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("probe-\(id)")
                        let probe = RuntimeProbe(output: output, cache: cache)
                        do {
                            try await probe.run(folder: folder, mode: selectedMode, e4b: selectedE4B, mtp: selectedMTP)
                            status = "Run finished. Inspect outputs and Instruments before assigning a pass."
                        } catch { status = "Run stopped: \(error). Completed samples are preserved." }
                        report = FileManager.default.fileExists(atPath: output.path) ? output : nil
                        try? FileManager.default.removeItem(at: cache)
                    }
                }
            }
        }
    }
}
