import SwiftUI

struct OutfitView: View {
    @ObservedObject var store: WardrobeStore
    @State private var isAdding = false
    @State private var selectedOutfit: Outfit?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if store.outfits.isEmpty {
                    ContentUnavailableView("No saved outfits", systemImage: "square.grid.2x2", description: Text("Combine garments into an outfit, then record it only when you actually wear it.")) {
                        Button("Create outfit") { isAdding = true }.buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section("Saved outfits") {
                        ForEach(store.outfits) { outfit in
                            Button { selectedOutfit = outfit } label: { OutfitRow(outfit: outfit, store: store) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if !store.wearEvents.isEmpty {
                    Section("Wear history") {
                        ForEach(store.wearEvents) { event in
                            WearEventRow(event: event, store: store) { undo(event) }
                        }
                    }
                }
                if !store.underusedItems.isEmpty {
                    Section("Wear less, wear more") {
                        ForEach(store.underusedItems) { summary in
                            HStack {
                                Text(summary.item.name)
                                Spacer()
                                Text(summary.wearCount == 0 ? "Never worn" : "\(summary.wearCount) wears")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Outfits")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { isAdding = true } label: { Label("Create outfit", systemImage: "plus") } } }
            .sheet(isPresented: $isAdding) { OutfitEditor(store: store) }
            .sheet(item: $selectedOutfit) { outfit in OutfitDetail(outfit: outfit, store: store) }
            .alert("Couldn’t update wear history", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func undo(_ event: WearEvent) {
        do { try store.undoWear(event) } catch { errorMessage = error.localizedDescription }
    }
}

private struct OutfitRow: View {
    let outfit: Outfit
    @ObservedObject var store: WardrobeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(outfit.name, systemImage: outfit.isFavorite ? "heart.fill" : "square.grid.2x2")
                .foregroundStyle(outfit.isFavorite ? .pink : .primary)
            Text(itemNames(for: outfit).joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
        }
        .accessibilityLabel("\(outfit.name), \(itemNames(for: outfit).joined(separator: ", "))")
    }

    private func itemNames(for outfit: Outfit) -> [String] { outfit.itemIDs.compactMap { store.item(id: $0)?.name } }
}

private struct WearEventRow: View {
    let event: WearEvent
    @ObservedObject var store: WardrobeStore
    let undo: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(event.outfitID.flatMap { id in store.outfits.first(where: { $0.id == id })?.name } ?? "Worn outfit")
                Text(event.wornAt.formatted(date: .abbreviated, time: .omitted)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Undo", action: undo).buttonStyle(.bordered)
        }
    }
}

private struct OutfitDetail: View {
    let outfit: Outfit
    @ObservedObject var store: WardrobeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    private var displayedOutfit: Outfit {
        store.outfits.first(where: { $0.id == outfit.id }) ?? outfit
    }

    private var didWearToday: Bool {
        store.wearEvents.contains { event in
            event.outfitID == displayedOutfit.id && calendar.isDateInToday(event.wornAt)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Garments") { ForEach(displayedOutfit.itemIDs, id: \.self) { id in Text(store.item(id: id)?.name ?? "Removed garment").foregroundStyle(store.item(id: id) == nil ? .secondary : .primary) } }
                if let notes = displayedOutfit.notes, !notes.isEmpty { Section("Notes") { Text(notes) } }
                Section { Button(didWearToday ? "Worn today" : "Wear today") { wearToday() }.buttonStyle(.borderedProminent).disabled(didWearToday) }
                Section { Button("Delete outfit", role: .destructive) { isConfirmingDelete = true } }
            }
            .navigationTitle(displayedOutfit.name)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { isEditing = true } } }
            .sheet(isPresented: $isEditing) { OutfitEditor(store: store, outfit: displayedOutfit) }
            .confirmationDialog("Delete \(displayedOutfit.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) { Button("Delete", role: .destructive) { delete() } }
            .alert("Couldn’t update outfit", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func wearToday() { do { _ = try store.wearToday(displayedOutfit) } catch { errorMessage = error.localizedDescription } }
    private func delete() { do { try store.deleteOutfit(displayedOutfit); dismiss() } catch { errorMessage = error.localizedDescription } }
}

private struct OutfitEditor: View {
    @ObservedObject var store: WardrobeStore
    let outfit: Outfit?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notes: String
    @State private var isFavorite: Bool
    @State private var itemIDs: Set<UUID>
    @State private var errorMessage: String?

    init(store: WardrobeStore, outfit: Outfit? = nil) {
        self.store = store; self.outfit = outfit
        _name = State(initialValue: outfit?.name ?? "")
        _notes = State(initialValue: outfit?.notes ?? "")
        _isFavorite = State(initialValue: outfit?.isFavorite ?? false)
        _itemIDs = State(initialValue: Set(outfit?.itemIDs ?? []))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Outfit") { TextField("Outfit name", text: $name).textInputAutocapitalization(.words); Toggle("Favorite", isOn: $isFavorite); TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...4) }
                Section("Choose garments") {
                    if store.allGarments.isEmpty { Text("Add garments to your wardrobe first.").foregroundStyle(.secondary) }
                    ForEach(store.allGarments) { item in
                        Toggle(item.name, isOn: Binding(get: { itemIDs.contains(item.id) }, set: { selected in if selected { itemIDs.insert(item.id) } else { itemIDs.remove(item.id) } }))
                    }
                }
            }
            .navigationTitle(outfit == nil ? "New outfit" : "Edit outfit")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(itemIDs.isEmpty) } }
            .alert("Couldn’t save outfit", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        let orderedIDs = store.allGarments.map(\.id).filter(itemIDs.contains)
        do {
            if var outfit { outfit.name = name; outfit.notes = notes.nilIfBlank; outfit.isFavorite = isFavorite; outfit.itemIDs = orderedIDs; try store.updateOutfit(outfit) }
            else { try store.createOutfit(OutfitDraft(name: name, itemIDs: orderedIDs, notes: notes.nilIfBlank, isFavorite: isFavorite)) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
