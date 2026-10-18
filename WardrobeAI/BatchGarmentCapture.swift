import Foundation
import SwiftUI
import UIKit

enum BatchClassificationState: Equatable, Sendable {
    case pending
    case classifying
    case succeeded(ClassificationProvenance)
    case failed(String)
    case cancelled
}

struct BatchClassificationEntry: Identifiable, @unchecked Sendable {
    let candidate: GarmentCaptureCandidate
    var state: BatchClassificationState

    var id: UUID { candidate.id }

    init(candidate: GarmentCaptureCandidate, state: BatchClassificationState = .pending) {
        self.candidate = candidate
        self.state = state
    }
}

/// Runs a batch one crop at a time so Vision or a future qualified model never
/// has multiple image requests resident concurrently.
actor BatchGarmentClassificationQueue {
    private let classifier: GarmentClassificationCoordinator

    init(classifier: GarmentClassificationCoordinator = GarmentClassificationCoordinator()) {
        self.classifier = classifier
    }

    func classify(
        _ entries: [BatchClassificationEntry],
        onUpdate: @escaping @Sendable (Int, BatchClassificationState) async -> Void
    ) async -> [BatchClassificationEntry] {
        var updated = entries
        for index in updated.indices {
            guard !Task.isCancelled else {
                for remainingIndex in index..<updated.endIndex where updated[remainingIndex].state == .pending {
                    updated[remainingIndex].state = .cancelled
                    await onUpdate(remainingIndex, .cancelled)
                }
                break
            }

            updated[index].state = .classifying
            await onUpdate(index, .classifying)
            do {
                let result = try await classifier.classify(imageData: updated[index].candidate.data)
                try Task.checkCancellation()
                updated[index].state = .succeeded(result)
            } catch is CancellationError {
                updated[index].state = .cancelled
            } catch {
                updated[index].state = .failed(error.localizedDescription)
            }
            await onUpdate(index, updated[index].state)
            if Task.isCancelled { break }
        }
        if Task.isCancelled {
            for index in updated.indices where updated[index].state == .pending {
                updated[index].state = .cancelled
                await onUpdate(index, .cancelled)
            }
        }
        return updated
    }
}

enum BatchGarmentDraftFactory {
    static func draft(for entry: BatchClassificationEntry, ordinal: Int) -> GarmentDraft {
        switch entry.state {
        case let .succeeded(provenance):
            let suggestion = provenance.suggestion
            return GarmentDraft(name: "\(suggestion.category) \(ordinal)", category: suggestion.category, color: suggestion.color, tags: suggestion.tags, classification: provenance)
        case .pending, .classifying, .failed, .cancelled:
            return GarmentDraft(name: "Garment \(ordinal)", category: GarmentTaxonomy.categories[0])
        }
    }
}

struct BatchGarmentCaptureSheet: View {
    @ObservedObject var store: WardrobeStore
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [BatchClassificationEntry] = []
    @State private var selectedIDs = Set<UUID>()
    @State private var isPreparing = false
    @State private var isClassifying = false
    @State private var classificationTask: Task<Void, Never>?
    @State private var errorMessage: String?
    private let queue = BatchGarmentClassificationQueue()

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("Add a batch photo", systemImage: "rectangle.3.group")
                    } description: {
                        Text("Choose a photo with two or three separated garments. Select only useful cutouts before saving.")
                    } actions: {
                        GarmentPhotoSource(onImage: prepare)
                    }
                } else {
                    List {
                        Section("Selected cutouts") {
                            ForEach($entries) { $entry in
                                Toggle(isOn: selectionBinding(for: entry.id)) {
                                    HStack(spacing: 12) {
                                        Image(uiImage: entry.candidate.image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entryTitle(entry.state))
                                            Text(entrySubtitle(entry.state)).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .disabled(isClassifying)
                                .accessibilityLabel("Select cutout: \(entryTitle(entry.state))")
                            }
                        }
                        Section {
                            GarmentPhotoSource(onImage: prepare)
                        } footer: {
                            Text("Cutouts are optional suggestions. Overlapping or non-garment masks can be left unselected; an empty result leaves the original single-photo flow available.")
                        }
                    }
                }
            }
            .overlay { if isPreparing || isClassifying { ProgressView(isPreparing ? "Finding cutouts…" : "Classifying one cutout at a time…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .navigationTitle("Batch capture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancelClassification(); dismiss() } }
                if !entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        if isClassifying { Button("Stop", role: .cancel) { cancelClassification() } }
                        else { Button("Classify") { classifySelected() }.disabled(selectedIDs.isEmpty) }
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Save selected") { saveSelected() }.disabled(selectedIDs.isEmpty || isClassifying) }
                }
            }
            .alert("Couldn’t save batch", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
        .onDisappear { cancelClassification() }
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(get: { selectedIDs.contains(id) }, set: { selected in if selected { selectedIDs.insert(id) } else { selectedIDs.remove(id) } })
    }

    private func prepare(_ image: UIImage) {
        cancelClassification()
        isPreparing = true
        Task {
            defer { isPreparing = false }
            let candidates = await Task.detached(priority: .userInitiated) { () -> [GarmentCaptureCandidate] in
                guard let original = try? GarmentImagePreparation.originalCandidate(from: image) else { return [] }
                return (try? GarmentImagePreparation.foregroundCandidates(from: original)) ?? []
            }.value
            entries = candidates.map(BatchClassificationEntry.init)
            selectedIDs = Set(entries.map(\.id))
            if entries.isEmpty { errorMessage = "No separate foreground masks were found. Try a clearer photo or add garments one at a time." }
        }
    }

    private func classifySelected() {
        let selected = entries.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        isClassifying = true
        classificationTask = Task {
            let results = await queue.classify(selected) { _, _ in }
            let states = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0.state) })
            entries = entries.map { entry in
                var entry = entry
                if let state = states[entry.id] { entry.state = state }
                return entry
            }
            isClassifying = false
            classificationTask = nil
        }
    }

    private func cancelClassification() {
        classificationTask?.cancel()
        classificationTask = nil
        isClassifying = false
    }

    private func saveSelected() {
        var failed: [UUID] = []
        for (offset, entry) in entries.filter({ selectedIDs.contains($0.id) }).enumerated() {
            do { try store.create(BatchGarmentDraftFactory.draft(for: entry, ordinal: offset + 1), imageData: entry.candidate.data) }
            catch { failed.append(entry.id); errorMessage = error.localizedDescription }
        }
        selectedIDs = Set(failed)
        if failed.isEmpty { dismiss() }
    }

    private func entryTitle(_ state: BatchClassificationState) -> String {
        switch state {
        case let .succeeded(provenance): provenance.suggestion.category
        case .pending: "Ready to classify"
        case .classifying: "Classifying…"
        case .failed: "Manual details will be used"
        case .cancelled: "Classification stopped"
        }
    }

    private func entrySubtitle(_ state: BatchClassificationState) -> String {
        switch state {
        case let .succeeded(provenance): "Suggested locally — review after saving"
        case let .failed(message): message
        case .pending: "Select this crop only if it is a garment"
        case .classifying: "This is the only active request"
        case .cancelled: "You can retry classification or save manually"
        }
    }
}
