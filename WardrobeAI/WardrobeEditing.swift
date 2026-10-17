import SwiftUI

struct GarmentDetail: View {
    let item: GarmentItem
    @ObservedObject var store: WardrobeStore
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Garment") {
                    LabeledContent("Name", value: item.name)
                    LabeledContent("Category", value: item.category)
                    if let color = item.color, !color.isEmpty { LabeledContent("Color", value: color) }
                }
                if !item.tags.isEmpty { Section("Tags") { Text(item.tags.joined(separator: ", ")) } }
                if let notes = item.notes, !notes.isEmpty { Section("Notes") { Text(notes) } }
                Section { Button("Delete garment", role: .destructive) { isConfirmingDelete = true } }
            }
            .navigationTitle(item.name)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { isEditing = true } } }
            .sheet(isPresented: $isEditing) { GarmentEditor(store: store, item: item) }
            .confirmationDialog("Delete \\(item.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    do { try store.delete(item); dismiss() } catch { errorMessage = error.localizedDescription }
                }
            } message: { Text("This cannot be undone. Garments used by an outfit or wear history must be removed there first.") }
            .alert("Couldn’t delete garment", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
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
    @State private var notes: String
    @State private var errorMessage: String?

    init(store: WardrobeStore, item: GarmentItem? = nil) {
        self.store = store
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _category = State(initialValue: item?.category ?? GarmentTaxonomy.categories[0])
        _color = State(initialValue: item?.color ?? "")
        _tags = State(initialValue: item?.tags.joined(separator: ", ") ?? "")
        _notes = State(initialValue: item?.notes ?? "")
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
                Section("Occasion ideas") { Text(GarmentTaxonomy.occasions.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle(item == nil ? "Add garment" : "Edit garment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.accessibilityLabel("Save garment") }
            }
            .alert("Couldn’t save garment", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        let draft = GarmentDraft(name: name, category: category, color: color.nilIfBlank, tags: tags.split(separator: ",").map(String.init), notes: notes.nilIfBlank, imagePath: item?.imagePath)
        do {
            if var item { item.name = draft.name; item.category = draft.category; item.color = draft.color; item.tags = draft.tags; item.notes = draft.notes; try store.save(item) }
            else { try store.create(draft) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
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
