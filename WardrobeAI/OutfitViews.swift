import SwiftUI

struct OutfitView: View {
    @ObservedObject var store: WardrobeStore
    @State private var isAdding = false
    @State private var selectedOutfit: Outfit?
    @State private var errorMessage: String?
    @State private var calendarAccess = CalendarAccessState.notDetermined
    @State private var calendarEvents: [CalendarEventContext] = []
    @Environment(\.scenePhase) private var scenePhase
    private let calendarReader = EventKitCalendarReader()

    var body: some View {
        NavigationStack {
            List {
                Section("Today’s context") {
                    CalendarContextSummary(access: calendarAccess, events: calendarEvents) {
                        Task {
                            calendarAccess = await calendarReader.requestAccess()
                            calendarEvents = (try? calendarReader.events(on: .now, calendar: .autoupdatingCurrent)) ?? []
                        }
                    }
                }
                if store.outfits.isEmpty {
                    ContentUnavailableView {
                        Label("No saved outfits", systemImage: "square.grid.2x2")
                    } description: {
                        Text("Combine garments into an outfit, then record it only when you actually wear it.")
                    } actions: {
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
                if !store.outfitPlans.isEmpty {
                    Section("Planned outfits") {
                        ForEach(store.outfitPlans) { plan in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(store.outfits.first(where: { $0.id == plan.outfitID })?.name ?? "Removed outfit")
                                    Text(plan.scheduledFor.formatted(date: .abbreviated, time: .shortened)).font(.footnote).foregroundStyle(.secondary)
                                    if let occasion = plan.occasion, !occasion.isEmpty { Text(occasion).font(.footnote).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Button("Remove", role: .destructive) { remove(plan) }.buttonStyle(.bordered)
                            }
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
            .task {
                refreshCalendarContext()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refreshCalendarContext()
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { isAdding = true } label: { Label("Create outfit", systemImage: "plus") } } }
            .sheet(isPresented: $isAdding) { OutfitEditor(store: store) }
            .sheet(item: $selectedOutfit) { outfit in OutfitDetail(outfit: outfit, store: store) }
            .alert("Couldn’t update wear history", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func undo(_ event: WearEvent) {
        do { try store.undoWear(event) } catch { errorMessage = error.localizedDescription }
    }
    private func remove(_ plan: OutfitPlan) { do { try store.removePlan(plan) } catch { errorMessage = error.localizedDescription } }

    private func refreshCalendarContext() {
        let access = calendarReader.accessState()
        calendarAccess = access
        guard access == .authorized else {
            calendarEvents = []
            return
        }
        calendarEvents = (try? calendarReader.events(on: .now, calendar: .autoupdatingCurrent)) ?? []
    }
}

private struct CalendarContextSummary: View {
    let access: CalendarAccessState
    let events: [CalendarEventContext]
    let request: () -> Void

    var body: some View {
        switch access {
        case .authorized:
            if events.isEmpty { Text("No calendar events today.").foregroundStyle(.secondary) }
            else { ForEach(events) { event in Label(event.timeLabel, systemImage: event.isAllDay ? "calendar" : "clock") } }
        case .notDetermined:
            Button("Show calendar context", action: request)
        case .denied:
            Text("Calendar access is off. You can still plan outfits manually.").foregroundStyle(.secondary)
        case .unavailable:
            Text("Calendar context is unavailable. You can still plan outfits manually.").foregroundStyle(.secondary)
        }
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
    @State private var isScheduling = false
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
                Section { Button("Plan outfit") { isScheduling = true } }
                Section { Button("Delete outfit", role: .destructive) { isConfirmingDelete = true } }
            }
            .navigationTitle(displayedOutfit.name)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { isEditing = true } } }
            .sheet(isPresented: $isEditing) { OutfitEditor(store: store, outfit: displayedOutfit) }
            .sheet(isPresented: $isScheduling) { OutfitPlanEditor(outfit: displayedOutfit, store: store) }
            .confirmationDialog("Delete \(displayedOutfit.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) { Button("Delete", role: .destructive) { delete() } }
            .alert("Couldn’t update outfit", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func wearToday() { do { _ = try store.wearToday(displayedOutfit) } catch { errorMessage = error.localizedDescription } }
    private func delete() { do { try store.deleteOutfit(displayedOutfit); dismiss() } catch { errorMessage = error.localizedDescription } }
}

private struct OutfitPlanEditor: View {
    let outfit: Outfit
    @ObservedObject var store: WardrobeStore
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var occasion = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Picker("Occasion", selection: $occasion) {
                        Text("None").tag("")
                        ForEach(GarmentTaxonomy.occasions, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section { Text("This saves a private in-app plan. It does not create a wear record or change your calendar.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Plan \(outfit.name)")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } } }
            .alert("Couldn’t save plan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        do { try store.schedule(outfit, for: date, occasion: occasion.nilIfBlank); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
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
