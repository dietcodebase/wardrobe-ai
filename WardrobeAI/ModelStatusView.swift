import SwiftUI
import UniformTypeIdentifiers
import Iconoir

struct ModelStatusView: View {
    @ObservedObject var manager: ModelManager
    @ObservedObject var store: WardrobeStore
    @State private var importingDescriptor: ModelDescriptor?
    @State private var showingImporter = false

    var body: some View {
        List {
            Section {
                IconoirLabel(title: "Manual wardrobe is available without a model.", icon: .checkCircle)
                    .accessibilityIdentifier("manual-wardrobe-status")
                IconoirLabel(title: "Imported and downloaded models are verified before they are stored.", icon: .shieldCheck)
                    .foregroundStyle(.secondary)
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

            Section("How this affects suggestions") {
                Text("Today uses owned-item outfit rules. Gemma refinement remains unavailable until the iPhone 17 runtime and memory checks pass.")
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.data]) { result in
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
            if isConnecting(status) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for the model host to start sending data…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if isCancelling(status) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Saving resume point…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if isVerifying(status) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Verifying model file…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if case let .downloading(progress) = status {
                ProgressView(value: progress)
                    .accessibilityLabel("Download progress")
            }
            HStack {
                Button("Import") {
                    importingDescriptor = descriptor
                    showingImporter = true
                }
                    .disabled(isBusy(status))
                Button(downloadTitle(status, descriptor: descriptor)) { downloadAction(descriptor, status: status) }
                    .disabled(isBusy(status) || isInstalled(status))
                if isActiveTransfer(status) {
                    Button("Cancel", role: .cancel) { manager.downloads?.cancel(descriptor) }
                        .disabled(isCancelling(status))
                }
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
        case .connecting: "Preparing download…"
        case let .downloading(progress): "Downloading \(Int(progress * 100)) percent"
        case .cancelling: "Saving a resume point…"
        case .verifying: "Verifying model file…"
        case .interrupted: "Download interrupted; resume is available"
        case .available: "Verified and ready for a configured runtime"
        case let .failed(message): "Model transfer failed: \(message)"
        }
    }

    private func downloadTitle(_ status: ModelTransferStatus, descriptor: ModelDescriptor) -> String {
        switch status {
        case .connecting: "Connecting…"
        case .downloading: "Downloading…"
        case .cancelling: "Cancelling…"
        case .verifying: "Verifying…"
        case .interrupted: "Resume"
        case .available: "Installed"
        case .failed: manager.downloads?.hasResumeData(for: descriptor) == true ? "Resume" : "Retry"
        case .notPresent: "Download"
        }
    }

    private func isInstalled(_ status: ModelTransferStatus) -> Bool {
        if case .available = status { return true }
        return false
    }

    private func isDownloading(_ status: ModelTransferStatus) -> Bool {
        if case .downloading = status { return true }
        return false
    }

    private func isConnecting(_ status: ModelTransferStatus) -> Bool {
        if case .connecting = status { return true }
        return false
    }

    private func isActiveTransfer(_ status: ModelTransferStatus) -> Bool {
        isConnecting(status) || isDownloading(status) || isCancelling(status)
    }

    private func isCancelling(_ status: ModelTransferStatus) -> Bool {
        if case .cancelling = status { return true }
        return false
    }

    private func isVerifying(_ status: ModelTransferStatus) -> Bool {
        if case .verifying = status { return true }
        return false
    }

    private func isBusy(_ status: ModelTransferStatus) -> Bool {
        isActiveTransfer(status) || isVerifying(status)
    }

    private func downloadAction(_ descriptor: ModelDescriptor, status: ModelTransferStatus) {
        switch status {
        case .interrupted:
            manager.downloads?.resume(descriptor)
        case .failed where manager.downloads?.hasResumeData(for: descriptor) == true:
            manager.downloads?.resume(descriptor)
        default:
            manager.downloads?.download(descriptor)
        }
    }

    // Styling happens in Today, where suggestion context belongs.

}
