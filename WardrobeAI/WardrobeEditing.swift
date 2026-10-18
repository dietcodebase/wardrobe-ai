import SwiftUI

struct GarmentDetail: View {
    let item: GarmentItem
    @ObservedObject var store: WardrobeStore
    @Environment(\.dismiss) private var dismiss
    @State private var displayedItem: GarmentItem
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    init(item: GarmentItem, store: WardrobeStore) {
        self.item = item
        self.store = store
        _displayedItem = State(initialValue: item)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Garment") {
                    LabeledContent("Name", value: displayedItem.name)
                    LabeledContent("Category", value: displayedItem.category)
                    if let color = displayedItem.color, !color.isEmpty { LabeledContent("Color", value: color) }
                }
                if !displayedItem.tags.isEmpty { Section("Tags") { Text(displayedItem.tags.joined(separator: ", ")) } }
                if let notes = displayedItem.notes, !notes.isEmpty { Section("Notes") { Text(notes) } }
                Section { Button("Delete garment", role: .destructive) { isConfirmingDelete = true } }
            }
            .navigationTitle(displayedItem.name)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { isEditing = true } } }
            .sheet(isPresented: $isEditing, onDismiss: refreshItem) { GarmentEditor(store: store, item: displayedItem) }
            .confirmationDialog("Delete \(displayedItem.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    do { try store.delete(displayedItem); dismiss() } catch { errorMessage = error.localizedDescription }
                }
            } message: { Text("This cannot be undone. Garments used by an outfit or wear history must be removed there first.") }
            .alert("Couldn’t delete garment", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func refreshItem() {
        if let latest = store.item(id: item.id) { displayedItem = latest }
    }
}

struct GarmentEditor: View {
    @ObservedObject var store: WardrobeStore
    let item: GarmentItem?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var category: String
    @State private var color: String
    @State private var tags: String
    @State private var materialGuess: String
    @State private var notes: String
    @State private var capturedImage: GarmentCaptureCandidate?
    @State private var isCapturing = false
    @State private var errorMessage: String?
    @State private var classification: ClassificationProvenance?
    @State private var isClassifying = false
    @State private var classificationMessage: String?
    @State private var classificationTask: Task<Void, Never>?
    private let classifier = GarmentClassificationCoordinator()

    init(store: WardrobeStore, item: GarmentItem? = nil) {
        self.store = store
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _category = State(initialValue: item?.category ?? GarmentTaxonomy.categories[0])
        _color = State(initialValue: item?.color ?? "")
        _tags = State(initialValue: item?.tags.joined(separator: ", ") ?? "")
        _materialGuess = State(initialValue: item?.classification?.suggestion.materialGuess ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _classification = State(initialValue: item?.classification)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Garment name", text: $name).textInputAutocapitalization(.words).accessibilityLabel("Garment name")
                    Picker("Category", selection: $category) { ForEach(GarmentTaxonomy.categories, id: \.self) { Text($0).tag($0) } }
                    TextField("Color", text: $color).textInputAutocapitalization(.words)
                }
                Section("Details") {
                    TextField("Tags, separated by commas", text: $tags).textInputAutocapitalization(.never).accessibilityLabel("Tags, separated by commas")
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                Section("Photo") {
                    if let capturedImage {
                        HStack {
                            Image(uiImage: capturedImage.image).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading) {
                                Text(capturedImage.kind == .foreground ? "Foreground cutout" : "Original photo")
                                HStack { Circle().fill(capturedImage.swatch.color).frame(width: 14, height: 14); Text("Average swatch") }
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(capturedImage == nil ? "Add photo" : "Change photo") { isCapturing = true }
                }
                Section("Automatic suggestions") {
                    if isClassifying {
                        HStack { ProgressView(); Text("Finding editable suggestions…") }
                        Button("Stop suggestions", role: .cancel) { cancelClassification() }
                    } else if let classification {
                        Text(classification.route == "cloud-openrouter-fallback" ? "Suggested by OpenRouter. Review and edit every field before saving." : "Suggested locally by \(classification.modelID.uppercased()). Review and edit every field before saving.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let material = classification.suggestion.materialGuess {
                            TextField("Material guess (verify this)", text: $materialGuess)
                                .textInputAutocapitalization(.words)
                                .accessibilityLabel("Material guess, verify this")
                        } else if !materialGuess.isEmpty {
                            TextField("Material", text: $materialGuess)
                                .textInputAutocapitalization(.words)
                                .accessibilityLabel("Material")
                        }
                        Button("Try automatic suggestions again") { startClassification() }
                            .disabled(capturedImage == nil)
                    } else {
                        Text(classificationMessage ?? "Suggestions are optional. Manual garment details always work.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Suggest garment details") { startClassification() }
                            .disabled(capturedImage == nil)
                    }
                }
                Section("Occasion ideas") { Text(GarmentTaxonomy.occasions.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle(item == nil ? "Add garment" : "Edit garment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.accessibilityLabel("Save garment") }
            }
            .alert("Couldn’t save garment", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
            .sheet(isPresented: $isCapturing) { GarmentCaptureSheet { candidate in
                capturedImage = candidate
                startClassification()
            } }
            .onDisappear { cancelClassification() }
        }
    }

    private func save() {
        let userTags = tags.split(separator: ",").map(String.init)
        let draft = GarmentDraft(name: name, category: category, color: color.nilIfBlank, tags: userTags, notes: notes.nilIfBlank, imagePath: item?.imagePath, classification: savedClassification())
        do {
            if var item {
                item.name = draft.name; item.category = draft.category; item.color = draft.color; item.tags = draft.tags; item.notes = draft.notes; item.classification = draft.classification
                try store.save(item, imageData: capturedImage?.data)
            } else { try store.create(draft, imageData: capturedImage?.data) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func startClassification() {
        guard let capturedImage else { return }
        cancelClassification()
        isClassifying = true
        classification = nil
        classificationMessage = nil
        let data = capturedImage.data
        classificationTask = Task {
            do {
                let result = try await classifier.classify(imageData: data)
                guard !Task.isCancelled else { return }
                classification = result
                category = result.suggestion.category
                color = result.suggestion.color ?? ""
                tags = result.suggestion.tags.joined(separator: ", ")
                materialGuess = result.suggestion.materialGuess ?? ""
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                classification = nil
                classificationMessage = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            isClassifying = false
            classificationTask = nil
        }
    }

    private func cancelClassification() {
        classificationTask?.cancel()
        classificationTask = nil
        isClassifying = false
    }

    private func savedClassification() -> ClassificationProvenance? {
        guard var classification else { return nil }
        let editedTags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let editedMaterial = materialGuess.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        if editedMaterial != classification.suggestion.materialGuess,
           let updatedSuggestion = try? GarmentClassificationSuggestion(
                category: classification.suggestion.category,
                color: classification.suggestion.color,
                tags: classification.suggestion.tags,
                materialGuess: editedMaterial
           ) {
            classification = ClassificationProvenance(
                modelID: classification.modelID,
                modelRevision: classification.modelRevision,
                route: classification.route,
                classifiedAt: classification.classifiedAt,
                suggestion: updatedSuggestion,
                wasEditedBeforeSave: true
            )
        }
        classification.wasEditedBeforeSave = classification.wasEditedBeforeSave
            || category != classification.suggestion.category
            || color.nilIfBlank != classification.suggestion.color
            || editedTags != classification.suggestion.tags
        return classification
    }
}

struct StyleProfileEditor: View {
    @ObservedObject var store: WardrobeStore
    @Environment(\.dismiss) private var dismiss
    @State private var categories: Set<String>
    @State private var colors: String
    @State private var notes: String
    @State private var errorMessage: String?

    init(store: WardrobeStore) {
        self.store = store
        let preferences = (try? store.repository.preferences()) ?? .empty
        _categories = State(initialValue: Set(preferences.preferredCategories))
        _colors = State(initialValue: preferences.preferredColors.joined(separator: ", "))
        _notes = State(initialValue: preferences.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preferred categories") {
                    ForEach(GarmentTaxonomy.categories, id: \.self) { category in
                        Toggle(category, isOn: Binding(get: { categories.contains(category) }, set: { selected in if selected { categories.insert(category) } else { categories.remove(category) } }))
                    }
                }
                Section("Style") {
                    TextField("Favorite colors, separated by commas", text: $colors).accessibilityLabel("Favorite colors, separated by commas")
                    TextField("Style notes", text: $notes, axis: .vertical).lineLimit(3...6)
                }
            }
            .navigationTitle("Style profile")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } } }
            .alert("Couldn’t save style profile", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        let preferences = StylePreferences(preferredCategories: categories.sorted(), preferredColors: colors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
        do { try store.repository.savePreferences(preferences); dismiss() } catch { errorMessage = error.localizedDescription }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
