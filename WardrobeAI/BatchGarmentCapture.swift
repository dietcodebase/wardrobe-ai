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
    var name = ""
    var category = GarmentTaxonomy.categories[0]
    var color = ""
    var tags = ""
    var materialGuess = ""
    var isReviewed = false

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
    static func draft(for entry: BatchClassificationEntry, ordinal: Int) -> GarmentDraft? {
        switch entry.state {
        case let .succeeded(provenance):
            guard entry.isReviewed,
                  let suggestion = try? GarmentClassificationSuggestion(
                    category: entry.category,
                    color: entry.color,
                    tags: entry.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                    materialGuess: entry.materialGuess
                  ) else { return nil }
            var reviewedProvenance = provenance
            reviewedProvenance.wasEditedBeforeSave = provenance.wasEditedBeforeSave
                || suggestion != provenance.suggestion
            reviewedProvenance = ClassificationProvenance(
                modelID: provenance.modelID,
                modelRevision: provenance.modelRevision,
                route: provenance.route,
                classifiedAt: provenance.classifiedAt,
                suggestion: suggestion,
                wasEditedBeforeSave: reviewedProvenance.wasEditedBeforeSave
            )
            return GarmentDraft(name: entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\(suggestion.category) \(ordinal)" : entry.name, category: suggestion.category, color: suggestion.color, tags: suggestion.tags, classification: reviewedProvenance)
        case .pending, .classifying, .failed, .cancelled:
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedColor = entry.color.trimmingCharacters(in: .whitespacesAndNewlines)
            let tags = entry.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return GarmentDraft(name: name.isEmpty ? "Garment \(ordinal)" : name, category: entry.category, color: trimmedColor.isEmpty ? nil : trimmedColor, tags: tags)
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
    @State private var classificationRunID: UUID?
    @State private var preparationTask: Task<Void, Never>?
    @State private var preparationRunID: UUID?
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
                                VStack(alignment: .leading, spacing: 12) {
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
                                    if case .classifying = entry.state {
                                        EmptyView()
                                    } else {
                                        TextField("Garment name", text: $entry.name).textInputAutocapitalization(.words)
                                            .onChange(of: entry.name) { _, _ in entry.isReviewed = false }
                                        Picker("Category", selection: $entry.category) {
                                            ForEach(GarmentTaxonomy.categories, id: \.self) { Text($0).tag($0) }
                                        }
                                        .onChange(of: entry.category) { _, _ in entry.isReviewed = false }
                                        TextField("Color", text: $entry.color).textInputAutocapitalization(.words)
                                            .onChange(of: entry.color) { _, _ in entry.isReviewed = false }
                                        TextField("Tags, separated by commas", text: $entry.tags).textInputAutocapitalization(.never)
                                            .onChange(of: entry.tags) { _, _ in entry.isReviewed = false }
                                    }
                                    if case .succeeded = entry.state {
                                        TextField("Material guess (optional, verify)", text: $entry.materialGuess).textInputAutocapitalization(.words)
                                            .onChange(of: entry.materialGuess) { _, _ in entry.isReviewed = false }
                                        Toggle("I reviewed these suggested details", isOn: $entry.isReviewed)
                                            .disabled(isClassifying)
                                    }
                                }
                                .padding(.vertical, 6)
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
                        else { Button("Classify") { classifySelected() }.disabled(selectedIDs.isEmpty || preparationTask != nil) }
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Save selected") { saveSelected() }.disabled(selectedIDs.isEmpty || isClassifying || isPreparing || !selectedEntriesAreReviewed) }
                }
            }
            .alert("Couldn’t save batch", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
        .onDisappear { cancelAllWork() }
    }

    private var selectedEntriesAreReviewed: Bool {
        entries.filter { selectedIDs.contains($0.id) }.allSatisfy { entry in
            if case .succeeded = entry.state { return entry.isReviewed }
            return true
        }
    }

    private func selectionBinding(for id: UUID) -> Binding<Bool> {
        Binding(get: { selectedIDs.contains(id) }, set: { selected in if selected { selectedIDs.insert(id) } else { selectedIDs.remove(id) } })
    }

    private func prepare(_ image: UIImage) {
        cancelClassification()
        preparationTask?.cancel()
        let runID = UUID()
        preparationRunID = runID
        isPreparing = true
        preparationTask = Task {
            let task = Task.detached(priority: .userInitiated) { () -> [GarmentCaptureCandidate] in
                guard let original = try? GarmentImagePreparation.originalCandidate(from: image) else { return [] }
                return (try? GarmentImagePreparation.foregroundCandidates(from: original)) ?? []
            }
            let candidates = await task.value
            guard preparationRunID == runID, !Task.isCancelled else { return }
            entries = candidates.map(BatchClassificationEntry.init)
            for index in entries.indices {
                entries[index].name = "Garment \(index + 1)"
            }
            selectedIDs = Set(entries.map(\.id))
            if entries.isEmpty { errorMessage = "No separate foreground masks were found. Try a clearer photo or add garments one at a time." }
            isPreparing = false
            preparationTask = nil
            preparationRunID = nil
        }
    }

    private func classifySelected() {
        let selected = entries.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        let runID = UUID()
        classificationRunID = runID
        for index in entries.indices where selectedIDs.contains(entries[index].id) {
            entries[index].isReviewed = false
        }
        isClassifying = true
        classificationTask = Task {
            let results = await queue.classify(selected) { _, _ in }
            guard classificationRunID == runID else { return }
            let states = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0.state) })
            entries = entries.enumerated().map { index, entry in
                var entry = entry
                if let state = states[entry.id] {
                    entry.state = state
                    if case let .succeeded(provenance) = state {
                        entry.name = "\(provenance.suggestion.category) \(index + 1)"
                        entry.category = provenance.suggestion.category
                        entry.color = provenance.suggestion.color ?? ""
                        entry.tags = provenance.suggestion.tags.joined(separator: ", ")
                        entry.materialGuess = provenance.suggestion.materialGuess ?? ""
                        entry.isReviewed = false
                    }
                }
                return entry
            }
            isClassifying = false
            classificationTask = nil
            classificationRunID = nil
        }
    }

    private func cancelClassification() {
        classificationTask?.cancel()
    }

    private func cancelAllWork() {
        cancelClassification()
        preparationTask?.cancel()
        preparationRunID = nil
    }

    private func saveSelected() {
        var failed: [UUID] = []
        for (offset, entry) in entries.filter({ selectedIDs.contains($0.id) }).enumerated() {
            guard let draft = BatchGarmentDraftFactory.draft(for: entry, ordinal: offset + 1) else {
                failed.append(entry.id)
                errorMessage = "Review and confirm every selected suggestion before saving."
                continue
            }
            do { try store.create(draft, imageData: entry.candidate.data) }
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
        case .succeeded: "Edit and confirm these suggestions before saving"
        case let .failed(message): message
        case .pending: "Select this crop only if it is a garment"
        case .classifying: "This is the only active request"
        case .cancelled: "You can retry classification or save manually"
        }
    }
}
