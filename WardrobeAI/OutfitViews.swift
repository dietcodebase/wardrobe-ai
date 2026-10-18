import SwiftUI
import UIKit
import Iconoir

struct OutfitView: View {
    @ObservedObject var store: WardrobeStore
    @State private var isAdding = false
    @State private var selectedOutfit: Outfit?
    @State private var errorMessage: String?
    @State private var isCheckingMirror = false
    @State private var isShowingPlanner = false

    var body: some View {
        NavigationStack {
            List {
                if store.outfits.isEmpty {
                    ContentUnavailableView {
                        IconoirLabel(title: "No saved looks", icon: .viewGrid)
                    } description: {
                        Text("Save an idea from Today, or make a look manually when you want to keep a combination.")
                    } actions: {
                        Button("Create a look") { isAdding = true }.buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section("Saved looks") {
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
                    Section("Planned looks") {
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
            .navigationTitle("Looks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isShowingPlanner = true } label: { IconoirLabel(title: "Planner", icon: .calendar) }
                        .accessibilityLabel("Open weekly outfit planner")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isCheckingMirror = true } label: { IconoirLabel(title: "Mirror fit check", icon: .camera) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAdding = true } label: { IconoirLabel(title: "Create look", icon: .plus) }
                }
            }
            .sheet(isPresented: $isAdding) { OutfitEditor(store: store) }
            .sheet(isPresented: $isCheckingMirror) { MirrorFitCheckSheet(store: store) }
            .sheet(isPresented: $isShowingPlanner) { OutfitWeekPlanner(store: store) }
            .sheet(item: $selectedOutfit) { outfit in OutfitDetail(outfit: outfit, store: store) }
            .alert("Couldn’t update wear history", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func undo(_ event: WearEvent) {
        do { try store.undoWear(event) } catch { errorMessage = error.localizedDescription }
    }
    private func remove(_ plan: OutfitPlan) { do { try store.removePlan(plan) } catch { errorMessage = error.localizedDescription } }

}

private struct OutfitWeekPlanner: View {
    @ObservedObject var store: WardrobeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @State private var weekStart = Date.now
    @State private var selectedPlan: OutfitPlan?
    @State private var isAddingPlan = false
    @State private var errorMessage: String?

    private var startOfWeek: Date {
        calendar.dateInterval(of: .weekOfYear, for: weekStart)?.start ?? calendar.startOfDay(for: weekStart)
    }

    private var days: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    private var weekPlans: [OutfitPlan] {
        guard let end = calendar.date(byAdding: .day, value: 7, to: startOfWeek) else { return [] }
        return store.outfitPlans.filter { $0.scheduledFor >= startOfWeek && $0.scheduledFor < end }
    }

    private var unscheduledLooks: [Outfit] {
        let planned = Set(store.outfitPlans.map(\.outfitID))
        return store.outfits.filter { !planned.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Week of", selection: $weekStart, displayedComponents: .date)
                    Text("Plans stay separate from actual wear. Moving a plan never records a wear event.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                ForEach(days, id: \.self) { day in
                    Section(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                        let plans = weekPlans.filter { calendar.isDate($0.scheduledFor, inSameDayAs: day) }
                        let worn = store.wearEvents.filter { calendar.isDate($0.wornAt, inSameDayAs: day) }
                        if plans.isEmpty && worn.isEmpty {
                            Text("No plan or recorded wear.").foregroundStyle(.secondary)
                        }
                        ForEach(plans) { plan in
                            Button { selectedPlan = plan } label: {
                                PlannerPlanRow(plan: plan, store: store)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Planned look \(outfitName(for: plan)) on \(day.formatted(date: .abbreviated, time: .omitted))")
                        }
                        ForEach(worn) { event in
                            HStack {
                                IconoirIcon(.checkCircle, size: 16).foregroundStyle(.green)
                                VStack(alignment: .leading) {
                                    Text(event.outfitID.flatMap { outfitName(for: $0) } ?? "Worn outfit")
                                    Text("Worn").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityLabel("Worn: \(event.outfitID.flatMap { outfitName(for: $0) } ?? "outfit")")
                        }
                    }
                }

                Section("Unscheduled looks") {
                    if unscheduledLooks.isEmpty {
                        Text("Every saved look has a plan.").foregroundStyle(.secondary)
                    } else {
                        ForEach(unscheduledLooks) { outfit in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(outfit.name)
                                    Text(outfit.itemIDs.compactMap { store.item(id: $0)?.name }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button("Plan") { selectedPlan = OutfitPlan(id: UUID(), outfitID: outfit.id, scheduledFor: calendar.startOfDay(for: Date.now), occasion: nil, sourceEventID: nil, createdAt: .now, updatedAt: .now) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Week planner")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Plan a look") { isAddingPlan = true } }
            }
            .sheet(item: $selectedPlan) { plan in
                PlannerPlanEditor(plan: plan, isNew: !store.outfitPlans.contains(where: { $0.id == plan.id }), store: store)
            }
            .sheet(isPresented: $isAddingPlan) { PlannerLookPicker(store: store, initialDate: calendar.startOfDay(for: Date.now)) }
            .alert("Couldn’t update planner", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func outfitName(for plan: OutfitPlan) -> String { outfitName(for: plan.outfitID) }
    private func outfitName(for id: UUID) -> String { store.outfits.first(where: { $0.id == id })?.name ?? "Removed outfit" }
}

private struct PlannerPlanRow: View {
    let plan: OutfitPlan
    @ObservedObject var store: WardrobeStore

    var body: some View {
        HStack {
            IconoirIcon(.calendar, size: 16).foregroundStyle(WardrobeDesign.Color.signal)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.outfits.first(where: { $0.id == plan.outfitID })?.name ?? "Removed outfit")
                Text(plan.occasion?.isEmpty == false ? plan.occasion! : "Planned")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            IconoirIcon(.navArrowRight, size: 16).foregroundStyle(.secondary)
        }
    }
}

private struct PlannerLookPicker: View {
    @ObservedObject var store: WardrobeStore
    let initialDate: Date
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOutfitID: UUID?
    @State private var date: Date
    @State private var occasion = ""
    @State private var errorMessage: String?

    init(store: WardrobeStore, initialDate: Date) {
        self.store = store
        self.initialDate = initialDate
        _selectedOutfitID = State(initialValue: store.outfits.first?.id)
        _date = State(initialValue: initialDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Look") {
                    Picker("Saved look", selection: $selectedOutfitID) {
                        ForEach(store.outfits) { Text($0.name).tag(Optional($0.id)) }
                    }
                    DatePicker("When", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Picker("Occasion", selection: $occasion) {
                        Text("None").tag("")
                        ForEach(GarmentTaxonomy.occasions, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section { Text("This creates a private in-app plan. It does not create a wear event or write to your calendar.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Plan a look")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(selectedOutfitID == nil) }
            }
            .alert("Couldn’t save plan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) { } } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard let id = selectedOutfitID, let outfit = store.outfits.first(where: { $0.id == id }) else { return }
        do { try store.schedule(outfit, for: date, occasion: occasion.nilIfBlank); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct PlannerPlanEditor: View {
    let plan: OutfitPlan
    let isNew: Bool
    @ObservedObject var store: WardrobeStore
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var occasion: String
    @State private var errorMessage: String?

    init(plan: OutfitPlan, isNew: Bool, store: WardrobeStore) {
        self.plan = plan; self.isNew = isNew; self.store = store
        _date = State(initialValue: plan.scheduledFor)
        _occasion = State(initialValue: plan.occasion ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    Text(store.outfits.first(where: { $0.id == plan.outfitID })?.name ?? "Removed outfit")
                    DatePicker("When", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Picker("Occasion", selection: $occasion) {
                        Text("None").tag("")
                        ForEach(GarmentTaxonomy.occasions, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section { Text("Changing this plan does not log a wear event.").font(.footnote).foregroundStyle(.secondary) }
                if !isNew { Section { Button("Remove plan", role: .destructive) { remove() } } }
            }
            .navigationTitle(isNew ? "Plan a look" : "Reschedule look")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .alert("Couldn’t update plan", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) { } } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard let outfit = store.outfits.first(where: { $0.id == plan.outfitID }) else { return }
        do {
            if isNew { try store.schedule(outfit, for: date, occasion: occasion.nilIfBlank) }
            else { try store.reschedule(plan, for: date, occasion: occasion.nilIfBlank) }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func remove() {
        do { try store.removePlan(plan); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct MirrorFitCheckSheet: View {
    @ObservedObject var store: WardrobeStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOutfitID: UUID?
    @State private var photo: UIImage?
    @State private var photoData: Data?
    @State private var photoID: UUID?
    @State private var observedCategory: String?
    @State private var isAssessingPhoto = false
    @State private var photoAssessmentError: String?
    @State private var occasion = ""

    private var selectedOutfit: Outfit? {
        if let selectedOutfitID { return store.outfits.first { $0.id == selectedOutfitID } }
        return store.outfits.first
    }

    private var assessment: MirrorFitAssessment? {
        guard let selectedOutfit else { return nil }
        return MirrorFitCheckEngine().assess(
            outfit: selectedOutfit,
            items: store.allGarments,
            observedCategory: observedCategory,
            context: MirrorFitContext(occasion: occasion, weather: nil)
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Outfit and context") {
                    if store.outfits.isEmpty {
                        Text("Save an outfit before starting a mirror fit check.").foregroundStyle(.secondary)
                    } else {
                        Picker("Outfit", selection: $selectedOutfitID) {
                            ForEach(store.outfits) { outfit in
                                Text(outfit.name).tag(Optional(outfit.id))
                            }
                        }
                        TextField("Occasion (optional)", text: $occasion)
                            .textInputAutocapitalization(.words)
                    }
                }

                Section("Still photo") {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Still outfit photo ready for a fit check")
                        Button("Retake or choose another photo") { clearPhoto() }
                    } else {
                        GarmentPhotoSource(onImage: acceptPhoto)
                    }
                    Text("The full-frame still stays in this sheet and is discarded when you close it. Feedback is limited to the selected clothing and context, never your body.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if isAssessingPhoto {
                        HStack { ProgressView(); Text("Checking visible clothing on device…").foregroundStyle(.secondary) }
                    }
                    if let photoAssessmentError {
                        Text(photoAssessmentError).foregroundStyle(.secondary)
                    }
                }

                if let assessment, photo != nil, !isAssessingPhoto {
                    Section("Clothing check") {
                        Text(assessment.clothingComment)
                        Text(assessment.contextComment).foregroundStyle(.secondary)
                    }
                    Section("Owned-item swaps") {
                        if assessment.swaps.isEmpty {
                            Text("No suitable owned swap is available right now. Keeping this outfit is a valid choice.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(assessment.swaps) { swap in
                                if let replacement = store.item(id: swap.replacementItemID), let current = store.item(id: swap.replacingItemID) {
                                    NavigationLink {
                                        MirrorSwapDetail(replacing: current, replacement: replacement, reason: swap.reason)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Try \(replacement.name) instead of \(current.name)")
                                            Text(swap.reason).font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                    .accessibilityLabel("View available swap: \(replacement.name) instead of \(current.name)")
                                }
                            }
                        }
                    }
                } else if selectedOutfit != nil {
                    Section {
                        Text("Add a still photo to show the clothing check and verified wardrobe swaps.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Mirror fit check")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task(id: photoID) { await assessPhoto() }
        }
    }

    private func acceptPhoto(_ image: UIImage) {
        photo = image
        photoData = image.jpegData(compressionQuality: 0.88)
        photoID = UUID()
        observedCategory = nil
        photoAssessmentError = nil
    }

    private func clearPhoto() {
        photo = nil
        photoData = nil
        photoID = nil
        observedCategory = nil
        photoAssessmentError = nil
        isAssessingPhoto = false
    }

    @MainActor
    private func assessPhoto() async {
        guard let photoData, photoID != nil else {
            isAssessingPhoto = false
            return
        }
        isAssessingPhoto = true
        defer { isAssessingPhoto = false }
        do {
            let provenance = try await GarmentClassificationCoordinator().classify(imageData: photoData)
            try Task.checkCancellation()
            observedCategory = provenance.suggestion.category
        } catch is CancellationError {
            return
        } catch {
            observedCategory = nil
            photoAssessmentError = "On-device clothing recognition is unavailable for this photo. You can still use the saved outfit and occasion as a manual reference."
        }
    }
}

private struct MirrorSwapDetail: View {
    let replacing: GarmentItem
    let replacement: GarmentItem
    let reason: String

    var body: some View {
        List {
            Section("Available in your wardrobe") {
                LabeledContent("Replace", value: replacing.name)
                LabeledContent("With", value: replacement.name)
                LabeledContent("Category", value: replacement.category)
                if let color = replacement.color, !color.isEmpty { LabeledContent("Color", value: color) }
            }
            Section { Text(reason).foregroundStyle(.secondary) }
        }
        .navigationTitle("Owned swap")
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
                            else { ForEach(events) { event in IconoirLabel(title: event.timeLabel, icon: event.isAllDay ? .calendar : .clock) } }
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
            IconoirLabel(title: outfit.name, icon: outfit.isFavorite ? .heartSolid : .viewGrid)
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
