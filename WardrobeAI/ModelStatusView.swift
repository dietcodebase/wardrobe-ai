import SwiftUI
import UniformTypeIdentifiers

struct ModelStatusView: View {
    @ObservedObject var manager: ModelManager
    @State private var importingDescriptor: ModelDescriptor?

    var body: some View {
        List {
            Section {
                Label("Manual wardrobe is available without a model.", systemImage: "checkmark.circle")
                if !ModelRuntimePolicy.deviceQualificationPassed {
                    Label("Model provisioning is disabled until M01 qualifies this device/runtime combination.", systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Local AI status")
            }

            Section("Pinned candidates") {
                ForEach(ModelDescriptor.qualifiedCandidates) { descriptor in
                    modelRow(descriptor)
                }
            }

            if let message = manager.provisioningMessage {
                Section { Text(message).foregroundStyle(.secondary) }
            }
        }
        .fileImporter(isPresented: Binding(
            get: { importingDescriptor != nil },
            set: { if !$0 { importingDescriptor = nil } }
        ), allowedContentTypes: [.data]) { result in
            guard let descriptor = importingDescriptor else { return }
            importingDescriptor = nil
            switch result {
            case let .success(url): manager.importModel(at: url, descriptor: descriptor)
            case let .failure(error): manager.reportProvisioningFailure(error)
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ descriptor: ModelDescriptor) -> some View {
        let status = manager.downloads?.statusByModel[descriptor.id] ?? .notPresent
        VStack(alignment: .leading, spacing: 8) {
            Text(descriptor.id.rawValue.uppercased()).font(.headline)
            Text(ByteCountFormatter.string(fromByteCount: descriptor.expectedBytes, countStyle: .file))
                .font(.caption).foregroundStyle(.secondary)
            Text(statusDescription(status)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Import") { importingDescriptor = descriptor }
                Button(downloadTitle(status)) { downloadAction(descriptor, status: status) }
                if case .downloading = status { Button("Cancel", role: .cancel) { manager.downloads?.cancel(descriptor) } }
            }
            .buttonStyle(.bordered)
            .disabled(!ModelRuntimePolicy.deviceQualificationPassed || manager.downloads == nil)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(descriptor.id.rawValue) model: \(statusDescription(status))")
    }

    private func statusDescription(_ status: ModelTransferStatus) -> String {
        switch status {
        case .notPresent: "Not installed"
        case let .downloading(progress): "Downloading \(Int(progress * 100)) percent"
        case .interrupted: "Download interrupted; resume is available"
        case .available: "Verified and ready when the runtime is qualified"
        case let .failed(message): "Download failed: \(message)"
        }
    }

    private func downloadTitle(_ status: ModelTransferStatus) -> String {
        if case .interrupted = status { return "Resume" }
        return "Download"
    }

    private func downloadAction(_ descriptor: ModelDescriptor, status: ModelTransferStatus) {
        if case .interrupted = status { manager.downloads?.resume(descriptor) }
        else { manager.downloads?.download(descriptor) }
    }
}
