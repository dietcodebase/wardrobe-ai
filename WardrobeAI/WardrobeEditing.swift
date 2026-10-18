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
                if let suggestion = displayedItem.classification?.suggestion {
                    Section("Style read") {
                        TagSummaryGrid(rows: [
                            ("Fabric", suggestion.materialGuess),
                            ("Pattern", suggestion.pattern),
                            ("Texture", suggestion.texture),
                            ("Fit", suggestion.fit),
                            ("Silhouette", suggestion.silhouette),
                            ("Layering", suggestion.layering),
                            ("Warmth", suggestion.warmth),
                            ("Formality", suggestion.formality),
                            ("Color family", suggestion.colorFamily)
                        ])
                        if !suggestion.styleKeywords.isEmpty {
                            Text(suggestion.styleKeywords.joined(separator: "  ·  "))
                                .font(WardrobeDesign.metadata())
                                .foregroundStyle(WardrobeDesign.Color.signal)
                        }
                    }
                }
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

private struct TagSummaryGrid: View {
    let rows: [(String, String?)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if let value = row.1, !value.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.0.uppercased()).font(WardrobeDesign.metadata(9)).foregroundStyle(WardrobeDesign.Color.quiet)
                        Text(value).font(WardrobeDesign.body(14))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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
    @State private var garmentType: String
    @State private var pattern: String
    @State private var fit: String
    @State private var formality: String
    @State private var seasons: String
    @State private var suggestedOccasions: String
    @State private var colorFamily: String
    @State private var secondaryColors: String
    @State private var texture: String
    @State private var layering: String
    @State private var warmth: String
    @State private var silhouette: String
    @State private var styleKeywords: String
    @State private var pairingNotes: String
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
        _garmentType = State(initialValue: item?.classification?.suggestion.garmentType ?? "")
        _pattern = State(initialValue: item?.classification?.suggestion.pattern ?? "")
        _fit = State(initialValue: item?.classification?.suggestion.fit ?? "")
        _formality = State(initialValue: item?.classification?.suggestion.formality ?? "")
        _seasons = State(initialValue: item?.classification?.suggestion.seasons.joined(separator: ", ") ?? "")
        _suggestedOccasions = State(initialValue: item?.classification?.suggestion.occasions.joined(separator: ", ") ?? "")
        _colorFamily = State(initialValue: item?.classification?.suggestion.colorFamily ?? "")
        _secondaryColors = State(initialValue: item?.classification?.suggestion.secondaryColors.joined(separator: ", ") ?? "")
        _texture = State(initialValue: item?.classification?.suggestion.texture ?? "")
        _layering = State(initialValue: item?.classification?.suggestion.layering ?? "")
        _warmth = State(initialValue: item?.classification?.suggestion.warmth ?? "")
        _silhouette = State(initialValue: item?.classification?.suggestion.silhouette ?? "")
        _styleKeywords = State(initialValue: item?.classification?.suggestion.styleKeywords.joined(separator: ", ") ?? "")
        _pairingNotes = State(initialValue: item?.classification?.suggestion.pairingNotes.joined(separator: ", ") ?? "")
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
                    OptionPicker(title: "Pattern", selection: $pattern, options: GarmentTaxonomy.patterns)
                    OptionPicker(title: "Fabric", selection: $materialGuess, options: GarmentTaxonomy.fabrics)
                    OptionPicker(title: "Texture", selection: $texture, options: GarmentTaxonomy.textures)
                    OptionPicker(title: "Fit", selection: $fit, options: GarmentTaxonomy.fits)
                    OptionPicker(title: "Silhouette", selection: $silhouette, options: GarmentTaxonomy.silhouettes)
                    OptionPicker(title: "Layering role", selection: $layering, options: GarmentTaxonomy.layering)
                    OptionPicker(title: "Warmth", selection: $warmth, options: GarmentTaxonomy.warmthLevels)
                    OptionPicker(title: "Formality", selection: $formality, options: GarmentTaxonomy.formalityLevels)
                    TextField("Tags, separated by commas", text: $tags).textInputAutocapitalization(.never).accessibilityLabel("Tags, separated by commas")
                    TextField("Style keywords, separated by commas", text: $styleKeywords).textInputAutocapitalization(.words)
                    TextField("Pairs well with…", text: $pairingNotes).textInputAutocapitalization(.sentences)
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
                        Text("Suggested locally by \(classification.modelID.uppercased()). Review and edit every field before saving.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if classification.suggestion.materialGuess != nil {
                            TextField("Material guess (verify this)", text: $materialGuess)
                                .textInputAutocapitalization(.words)
                                .accessibilityLabel("Material guess, verify this")
                        } else if !materialGuess.isEmpty {
                            TextField("Material", text: $materialGuess)
                                .textInputAutocapitalization(.words)
                                .accessibilityLabel("Material")
                        }
                        DisclosureGroup("Gemma's full read") {
                            TextField("Garment type", text: $garmentType).textInputAutocapitalization(.words)
                            TextField("Color family", text: $colorFamily).textInputAutocapitalization(.words)
                            TextField("Secondary colors", text: $secondaryColors).textInputAutocapitalization(.words)
                            TextField("Seasons, separated by commas", text: $seasons).textInputAutocapitalization(.words)
                            TextField("Occasions, separated by commas", text: $suggestedOccasions).textInputAutocapitalization(.words)
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
                garmentType = result.suggestion.garmentType ?? ""
                pattern = result.suggestion.pattern ?? ""
                fit = result.suggestion.fit ?? ""
                formality = result.suggestion.formality ?? ""
                seasons = result.suggestion.seasons.joined(separator: ", ")
                suggestedOccasions = result.suggestion.occasions.joined(separator: ", ")
                colorFamily = result.suggestion.colorFamily ?? ""
                secondaryColors = result.suggestion.secondaryColors.joined(separator: ", ")
                texture = result.suggestion.texture ?? ""
                layering = result.suggestion.layering ?? ""
                warmth = result.suggestion.warmth ?? ""
                silhouette = result.suggestion.silhouette ?? ""
                styleKeywords = result.suggestion.styleKeywords.joined(separator: ", ")
                pairingNotes = result.suggestion.pairingNotes.joined(separator: ", ")
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
        let editedSeasons = seasons.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let editedOccasions = suggestedOccasions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let editedGarmentType = garmentType.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let editedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let editedFit = fit.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let editedFormality = formality.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let editedColorFamily = colorFamily.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let editedSecondaryColors = splitValues(secondaryColors)
        let editedTexture = texture.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let editedLayering = layering.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let editedWarmth = warmth.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let editedSilhouette = silhouette.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let editedStyleKeywords = splitValues(styleKeywords)
        let editedPairingNotes = splitValues(pairingNotes)
        if editedMaterial != classification.suggestion.materialGuess
            || editedGarmentType != classification.suggestion.garmentType
            || editedPattern != classification.suggestion.pattern
            || editedFit != classification.suggestion.fit
            || editedFormality != classification.suggestion.formality
            || editedColorFamily != classification.suggestion.colorFamily
            || editedSecondaryColors != classification.suggestion.secondaryColors
            || editedTexture != classification.suggestion.texture
            || editedLayering != classification.suggestion.layering
            || editedWarmth != classification.suggestion.warmth
            || editedSilhouette != classification.suggestion.silhouette
            || editedStyleKeywords != classification.suggestion.styleKeywords
            || editedPairingNotes != classification.suggestion.pairingNotes
            || editedSeasons != classification.suggestion.seasons
            || editedOccasions != classification.suggestion.occasions,
           let updatedSuggestion = try? GarmentClassificationSuggestion(
                category: classification.suggestion.category,
                color: classification.suggestion.color,
                tags: classification.suggestion.tags,
                materialGuess: editedMaterial,
                garmentType: editedGarmentType,
                pattern: editedPattern,
                fit: editedFit,
                formality: editedFormality,
                seasons: editedSeasons,
                occasions: editedOccasions,
                colorFamily: editedColorFamily,
                secondaryColors: editedSecondaryColors,
                silhouette: editedSilhouette,
                texture: editedTexture,
                layering: editedLayering,
                warmth: editedWarmth,
                styleKeywords: editedStyleKeywords,
                pairingNotes: editedPairingNotes
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

    private func splitValues(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

private struct OptionPicker: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Menu {
            Button("Not set") { selection = "" }
            ForEach(options, id: \.self) { option in
                Button(option) { selection = option }
            }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(selection.isEmpty ? "Not set" : selection)
                    .foregroundStyle(selection.isEmpty ? .secondary : WardrobeDesign.Color.signal)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(title), \(selection.isEmpty ? "not set" : selection)")
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
