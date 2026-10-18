import SwiftUI
import Iconoir

struct IconoirIcon: View {
    let icon: Iconoir
    let size: CGFloat

    init(_ icon: Iconoir, size: CGFloat = 18) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        icon.asImage
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct IconoirLabel: View {
    let title: String
    let icon: Iconoir

    var body: some View {
        HStack(spacing: 7) {
            IconoirIcon(icon, size: 16)
            Text(title)
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case wardrobe = "Wardrobe"
    case looks = "Looks"

    var id: String { rawValue }
    var symbol: String { switch self { case .today: "sparkles"; case .wardrobe: "tshirt"; case .looks: "square.grid.2x2" } }
    var message: String { switch self { case .today: "Plan a look from what you own"; case .wardrobe: "Your wardrobe starts here"; case .looks: "Your saved looks and plans live here" } }
}

struct ContentView: View {
    @ObservedObject var store: WardrobeStore
    @ObservedObject var modelManager: ModelManager
    @State private var selectedTab: AppTab = .today
    @State private var showingAddGarment = false
    @State private var showingModelStatus = false
    @State private var showingStylist = false
    @State private var showingAISettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView(
                    store: store,
                    showWardrobe: { selectedTab = .wardrobe },
                    showLooks: { selectedTab = .looks },
                    addGarment: { showingAddGarment = true },
                    askStylist: { showingStylist = true },
                    configureOllama: { showingAISettings = true }
                )
            }
            .tabItem { Label { Text("Today") } icon: { IconoirIcon(.sparks, size: 16) } }
            .tag(AppTab.today)

            NavigationStack {
                WardrobeView(store: store)
            }
            .tabItem { Label { Text("Wardrobe") } icon: { IconoirIcon(.shirt, size: 16) } }
            .tag(AppTab.wardrobe)

            NavigationStack {
                OutfitView(store: store)
            }
            .tabItem { Label { Text("Looks") } icon: { IconoirIcon(.viewGrid, size: 16) } }
            .tag(AppTab.looks)
        }
        .tint(WardrobeDesign.Color.signal)
        .preferredColorScheme(.dark)
        .font(WardrobeDesign.body())
        .sheet(isPresented: $showingAddGarment) { GarmentEditor(store: store) }
        .sheet(isPresented: $showingModelStatus) {
            NavigationStack { ModelStatusView(manager: modelManager, store: store).navigationTitle("Local AI") }
        }
        .sheet(isPresented: $showingStylist) {
            NavigationStack {
                AssistantConversationView(
                    store: store,
                    showWardrobe: { showingStylist = false; selectedTab = .wardrobe },
                    showOutfits: { showingStylist = false; selectedTab = .looks },
                    showAddGarment: { showingStylist = false; showingAddGarment = true },
                    showModelStatus: { showingStylist = false; showingModelStatus = true }
                )
            }
        }
        .sheet(isPresented: $showingAISettings) { AssistantSettingsView() }
    }
}

private struct TodayView: View {
    @ObservedObject var store: WardrobeStore
    let showWardrobe: () -> Void
    let showLooks: () -> Void
    let addGarment: () -> Void
    let askStylist: () -> Void
    let configureOllama: () -> Void

    @AppStorage("recommendation.weatherCity") private var weatherCity = ""
    @State private var contextExpanded = false
    @State private var occasion = "Everyday"
    @State private var dressCodeNote = ""
    @State private var warmth = WarmthPreference.any
    @State private var tolerateRain = false
    @State private var prioritizeWalkingComfort = false
    @State private var repeatFrequency = RepeatFrequency.any
    @State private var weatherState: WeatherContextState = .unavailable(reason: "Weather has not been added.")
    @State private var isRefreshingWeather = false
    @State private var calendarReader = EventKitCalendarReader()
    @State private var calendarAccess: CalendarAccessState = .notDetermined
    @State private var calendarEvents: [CalendarEventContext] = []
    @State private var selectedCalendarEventIDs = Set<String>()
    @State private var isLoadingCalendar = false
    @State private var lockedItemIDs: [UUID] = []
    @State private var requestedSlot: RecommendationSlot = .completeLook
    @State private var localSuggestions: [OutfitSuggestion] = []
    @State private var adjustedSuggestions: [OutfitSuggestion] = []
    @State private var refinedSuggestions: [OutfitSuggestion] = []
    @State private var isRefining = false
    @State private var message: String?
    @State private var showingCompose = false
    @State private var replacementTarget: OutfitSuggestion?
    @State private var skipTarget: OutfitSuggestion?

    private var heuristicSuggestions: [OutfitSuggestion] {
        (try? store.recommendations(context: recommendationContext)) ?? []
    }

    private var suggestions: [OutfitSuggestion] {
        if !adjustedSuggestions.isEmpty { return adjustedSuggestions }
        return refinedSuggestions.isEmpty ? localSuggestions : refinedSuggestions
    }

    private var weatherSnapshot: WeatherSnapshot? { weatherState.snapshot }
    private var weatherFreshness: WeatherFreshness {
        switch weatherState {
        case .fresh: .fresh
        case .cached: .cached
        case .stale: .stale
        case .unavailable: .unavailable
        }
    }

    private var selectedCalendarPeriods: [CalendarBusyPeriod] {
        calendarEvents.filter { selectedCalendarEventIDs.contains($0.id) }.map { CalendarBusyPeriod(startDate: $0.startDate, endDate: $0.endDate, isAllDay: $0.isAllDay) }
    }

    private var recommendationContext: RecommendationContext {
        let preferences = (try? store.repository.preferences()) ?? .empty
        return RecommendationContext(
            occasion: occasion == "Everyday" ? nil : occasion,
            preferredColors: preferences.preferredColors,
            preferredCategories: preferences.preferredCategories,
            weather: weatherSnapshot,
            weatherFreshness: weatherFreshness,
            dressCodeNote: dressCodeNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : dressCodeNote.trimmingCharacters(in: .whitespacesAndNewlines),
            lockedItemIDs: lockedItemIDs,
            requestedSlots: [requestedSlot],
            warmth: warmth,
            tolerateRain: tolerateRain,
            prioritizeWalkingComfort: prioritizeWalkingComfort,
            repeatFrequency: repeatFrequency,
            formality: preferences.preferredFormality,
            footwearPreference: preferences.footwearPreference,
            calendarBusyPeriods: selectedCalendarPeriods
        )
    }

    private var suggestionInputID: String {
        let garments = store.allGarments.map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSinceReferenceDate)" }.joined(separator: "|")
        let wears = store.wearEvents.map { "\($0.id.uuidString):\($0.wornAt.timeIntervalSinceReferenceDate)" }.joined(separator: "|")
        let weatherKey = weatherSnapshot.map { "\($0.fetchedAt.timeIntervalSince1970):\($0.temperatureCelsius):\($0.condition.rawValue):\(weatherFreshness.rawValue)" } ?? weatherFreshness.rawValue
        let calendarKey = selectedCalendarPeriods.map { "\($0.startDate.timeIntervalSince1970)-\($0.endDate.timeIntervalSince1970)" }.joined(separator: ",")
        return [occasion, dressCodeNote, warmth.rawValue, String(tolerateRain), String(prioritizeWalkingComfort), repeatFrequency.rawValue, lockedItemIDs.map(\.uuidString).joined(separator: ","), requestedSlot.rawValue, weatherCity, weatherKey, calendarKey, garments, wears].joined(separator: "#")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WardrobeDesign.Space.lg) {
                header
                if store.allGarments.isEmpty {
                    firstGarment
                } else {
                    contextCard
                    composeControls
                    recommendations
                    quickActions
                }
            }
            .padding(WardrobeDesign.Space.md)
        }
        .background(WardrobeDesign.Color.canvas)
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: configureOllama) { IconoirIcon(.settings, size: 20) }
                    .accessibilityLabel("Configure Ollama server")
            }
        }
        .alert("Outfit update", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(message ?? "") }
        .sheet(isPresented: $showingCompose) {
            ComposeBuilderSheet(store: store, lockedItemIDs: $lockedItemIDs, requestedSlot: $requestedSlot)
        }
        .sheet(item: $replacementTarget) { suggestion in
            ComponentReplacementSheet(suggestion: suggestion, store: store) { itemID, replacement in
                replace(suggestion, itemID: itemID, with: replacement)
            }
        }
        .sheet(item: $skipTarget) { suggestion in
            SkipReasonSheet { reason in
                skip(suggestion, reason: reason)
                skipTarget = nil
            }
        }
        .task(id: suggestionInputID) { await refineSuggestions(inputID: suggestionInputID) }
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { contextExpanded.toggle() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Today’s context").font(WardrobeDesign.display(20))
                        Text(contextSummary).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: contextExpanded ? "chevron.up" : "chevron.down")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Today's context, \(contextExpanded ? "expanded" : "collapsed")")
            if contextExpanded {
                Picker("Occasion", selection: $occasion) {
                    ForEach(GarmentTaxonomy.occasions, id: \.self) { Text($0) }
                }
                .accessibilityLabel("Occasion")
                TextField("Dress code note (optional)", text: $dressCodeNote)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Dress code note, optional")
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weather (optional)").font(.subheadline.weight(.semibold))
                    HStack {
                        TextField("City", text: $weatherCity).textInputAutocapitalization(.words).accessibilityLabel("Weather city")
                        Button(isRefreshingWeather ? "Updating…" : "Refresh") { Task { await refreshWeather() } }
                            .disabled(isRefreshingWeather || weatherCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text(weatherDescription).font(.footnote).foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Calendar availability (optional)").font(.subheadline.weight(.semibold))
                    Button(isLoadingCalendar ? "Loading calendar…" : calendarAccess == .authorized ? "Refresh availability" : "Allow calendar availability") {
                        Task { await loadCalendarAvailability() }
                    }
                    .disabled(isLoadingCalendar)
                    Text(calendarDescription).font(.footnote).foregroundStyle(.secondary)
                    ForEach(calendarEvents) { event in
                        Toggle(event.isAllDay ? "Busy all day" : "Busy at \(event.timeLabel)", isOn: Binding(
                            get: { selectedCalendarEventIDs.contains(event.id) },
                            set: { selected in if selected { selectedCalendarEventIDs.insert(event.id) } else { selectedCalendarEventIDs.remove(event.id) } }
                        ))
                        .accessibilityLabel(event.isAllDay ? "Use all-day calendar availability" : "Use calendar availability at \(event.timeLabel)")
                    }
                }
                Divider()
                Picker("Warmth", selection: $warmth) {
                    Text("Use saved preference").tag(WarmthPreference.any)
                    Text("Prefer warmer pieces").tag(WarmthPreference.preferWarm)
                    Text("Prefer lighter pieces").tag(WarmthPreference.preferLight)
                }
                Toggle("Rain-ready pieces", isOn: $tolerateRain)
                Toggle("Prioritize walking comfort", isOn: $prioritizeWalkingComfort)
                Picker("Recent repeats", selection: $repeatFrequency) {
                    Text("Use saved preference").tag(RepeatFrequency.any)
                    Text("Avoid recently worn").tag(RepeatFrequency.avoidRecent)
                    Text("Repeat recent favorites").tag(RepeatFrequency.repeatRecent)
                }
            }
        }
        .padding(WardrobeDesign.Space.md)
        .background(WardrobeDesign.Color.paper, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
    }

    private var contextSummary: String {
        let weather = weatherSnapshot.map { "\(Int($0.temperatureCelsius.rounded()))°C · \($0.description) · \(weatherFreshness.rawValue)" } ?? "No weather"
        let busy = selectedCalendarPeriods.isEmpty ? "No calendar context" : "\(selectedCalendarPeriods.count) busy period(s)"
        return "\(occasion) · \(weather) · \(busy)"
    }

    private var weatherDescription: String {
        switch weatherState {
        case let .fresh(snapshot): "Fresh: \(snapshot.description), \(Int(snapshot.temperatureCelsius.rounded()))°C in \(snapshot.location.normalizedCity)."
        case let .cached(snapshot): "Cached: \(snapshot.description), \(Int(snapshot.temperatureCelsius.rounded()))°C in \(snapshot.location.normalizedCity)."
        case let .stale(snapshot, reason): "Stale: \(snapshot.description), \(Int(snapshot.temperatureCelsius.rounded()))°C. \(reason)."
        case let .unavailable(reason): reason
        }
    }

    private var calendarDescription: String {
        switch calendarAccess {
        case .notDetermined: "Calendar access is optional and requested only when you tap the button. Event titles are not shown or saved."
        case .authorized: calendarEvents.isEmpty ? "No events today. Event titles stay hidden." : "Choose busy times to include. Event titles stay hidden."
        case .denied: "Calendar access is off. You can still set the occasion manually in Today."
        case .unavailable: "Calendar access is unavailable. You can still set the occasion manually in Today."
        }
    }

    @MainActor
    private func refreshWeather() async {
        isRefreshingWeather = true
        defer { isRefreshingWeather = false }
        weatherState = await WeatherContextService(provider: OpenWeatherMapProvider()).refresh(location: WeatherLocation(city: weatherCity))
    }

    @MainActor
    private func loadCalendarAvailability() async {
        isLoadingCalendar = true
        defer { isLoadingCalendar = false }
        if calendarAccess != .authorized { calendarAccess = await calendarReader.requestAccess() }
        guard calendarAccess == .authorized else { return }
        do {
            calendarEvents = try calendarReader.events(on: .now, calendar: .autoupdatingCurrent)
            let validIDs = Set(calendarEvents.map(\.id))
            selectedCalendarEventIDs.formIntersection(validIDs)
        } catch {
            calendarAccess = .unavailable
        }
    }

    private var composeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Compose a look").font(WardrobeDesign.display(20))
            Text(lockedItemIDs.isEmpty ? "Lock up to three owned pieces, then choose what to fill." : "Locked: \(lockedItemNames)")
                .font(.footnote).foregroundStyle(.secondary)
            Button { showingCompose = true } label: { Label("Choose locked pieces and open slot", systemImage: "lock") }
                .buttonStyle(.bordered)
                .accessibilityLabel("Choose locked garments and requested open slot")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WardrobeDesign.Space.md)
        .background(WardrobeDesign.Color.paper, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
    }

    private var lockedItemNames: String {
        lockedItemIDs.compactMap { store.item(id: $0)?.name }.joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dress with less guesswork.")
                .font(WardrobeDesign.display(30))
            Text(store.allGarments.isEmpty ? "Add a few pieces and your wardrobe becomes a useful source of outfit ideas." : "Choose the moment. We’ll build a complete look from the pieces you own.")
                .font(WardrobeDesign.body(16))
                .foregroundStyle(WardrobeDesign.Color.quiet)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WardrobeDesign.Space.lg)
        .background(WardrobeDesign.Color.paper, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
    }

    private var firstGarment: some View {
        VStack(alignment: .leading, spacing: 14) {
            IconoirIcon(.shirt, size: 26).foregroundStyle(WardrobeDesign.Color.signal)
            Text("Start with a piece you wear often.").font(WardrobeDesign.display(22))
            Text("A photo is fastest. You can correct every suggested detail before saving.")
                .foregroundStyle(WardrobeDesign.Color.quiet)
            Button(action: addGarment) {
                IconoirLabel(title: "Add your first garment", icon: .plus).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WardrobeDesign.Color.ink)
            Button("Browse wardrobe", action: showWardrobe).buttonStyle(.bordered)
        }
        .padding(WardrobeDesign.Space.lg)
        .background(WardrobeDesign.Color.card, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var recommendations: some View {
        if suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("A few more pieces will unlock a complete look.").font(WardrobeDesign.body(17).weight(.semibold))
                Text("Add tops, bottoms, and footwear so the planner has enough to combine.").foregroundStyle(WardrobeDesign.Color.quiet)
                Button("Add a garment", action: addGarment).buttonStyle(.bordered)
            }
            .padding(WardrobeDesign.Space.md)
            .background(WardrobeDesign.Color.card, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
        } else {
            HStack {
                Text("Your options").font(WardrobeDesign.display(22))
                Spacer()
                if isRefining { ProgressView().controlSize(.small).accessibilityLabel("Refining outfit ideas") }
            }
            ForEach(suggestions.prefix(3)) { suggestion in
                TodaySuggestionCard(suggestion: suggestion, store: store, save: { save(suggestion) }, wear: { wear(suggestion) }, skip: { skipTarget = suggestion }, replace: { replacementTarget = suggestion })
            }
        }
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: askStylist) { IconoirLabel(title: "Ask stylist", icon: .sparks).frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button(action: showLooks) { IconoirLabel(title: "Saved looks", icon: .viewGrid).frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            Button(action: configureOllama) {
                IconoirLabel(title: OllamaConfiguration.saved().isConfigured ? "Ollama server configured" : "Connect an Ollama server", icon: .network)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func save(_ suggestion: OutfitSuggestion) {
        do { _ = try store.saveSuggestion(suggestion); message = "Saved to Looks. You can plan it or record a wear there." }
        catch { message = error.localizedDescription }
    }

    private func skip(_ suggestion: OutfitSuggestion, reason: RecommendationSkipReason?) {
        do { try store.recordRecommendationOutcome(suggestion, outcome: .skipped, reason: reason); message = "We’ll keep this feedback with the recommendation." }
        catch { message = error.localizedDescription }
    }

    private func replace(_ suggestion: OutfitSuggestion, itemID: UUID, with replacement: GarmentItem) {
        do {
            guard let result = try store.replacing(suggestion, itemID: itemID, with: replacement, context: recommendationContext) else {
                message = "That replacement would conflict with another locked piece."; return
            }
            adjustedSuggestions = suggestions.map { $0.id == suggestion.id ? result : $0 }
        } catch { message = error.localizedDescription }
    }

    private func wear(_ suggestion: OutfitSuggestion) {
        do { _ = try store.wearSuggestion(suggestion); message = "Recorded as worn today." }
        catch { message = error.localizedDescription }
    }

    @MainActor
    private func refineSuggestions(inputID: String) async {
        localSuggestions = []
        adjustedSuggestions = []
        refinedSuggestions = []
        let candidates = heuristicSuggestions
            localSuggestions = Array(candidates.prefix(3))
        let recommendationContext = self.recommendationContext
        try? store.recordRecommendation(candidates, context: recommendationContext, source: candidates.first?.source ?? .noContext, outcome: candidates.isEmpty ? .failedToGenerate : .generated)
        guard !candidates.isEmpty else { return }
        isRefining = true
        defer { if suggestionInputID == inputID { isRefining = false } }
        do {
            let contextOccasion = occasion == "Everyday" ? "unspecified everyday" : occasion
            let lockedContext = recommendationContext.lockedItemIDs.compactMap { store.item(id: $0) }.map { "\($0.name) (\($0.category))" }.joined(separator: ", ")
            let calendarContext = recommendationContext.calendarBusyPeriods.isEmpty ? "none" : "\(recommendationContext.calendarBusyPeriods.count) selected busy period(s), titles hidden"
            let context = "occasion=\(contextOccasion); dress code=\(recommendationContext.dressCodeNote ?? "none"); locked pieces=\(lockedContext); open slot=\(requestedSlot.rawValue); warmth=\(warmth.rawValue); rain-ready=\(tolerateRain); walking comfort=\(prioritizeWalkingComfort); recent-repeat preference=\(repeatFrequency.rawValue); weather=\(weatherDescription); calendar=\(calendarContext)"
            let refined = try await OllamaOutfitAdvisor().recommendations(candidates: candidates, items: store.allGarments, context: context)
            guard !Task.isCancelled, suggestionInputID == inputID else { return }
            try store.recordRecommendation(refined, context: recommendationContext, source: .ollamaRanking, outcome: .generated)
            refinedSuggestions = refined
        } catch {
            try? store.recordRecommendation(candidates, context: recommendationContext, source: .ollamaRanking, outcome: .failedToGenerate)
            // The deterministic planner remains visible when optional ranking is unavailable.
        }
    }

    private func validateLocks(_ ids: [UUID], slot: RecommendationSlot) -> String? {
        let locked = ids.compactMap { store.item(id: $0) }
        return OutfitRecommendationEngine.validationMessage(lockedItems: locked, requestedSlots: [slot])
    }
}

private struct TodaySuggestionCard: View {
    let suggestion: OutfitSuggestion
    @ObservedObject var store: WardrobeStore
    let save: () -> Void
    let wear: () -> Void
    let skip: () -> Void
    let replace: () -> Void
    @State private var showingWhy = false

    private var names: [String] { suggestion.itemIDs.compactMap { store.item(id: $0)?.name } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(names.joined(separator: " · ")).font(WardrobeDesign.body(17).weight(.semibold))
            Text(suggestion.explanation).font(WardrobeDesign.body(14)).foregroundStyle(WardrobeDesign.Color.quiet)
            Button("Why this look?") { showingWhy = true }.buttonStyle(.plain).font(.footnote.weight(.semibold))
            HStack {
                Button("Replace", action: replace).buttonStyle(.bordered)
                Button("Save for later", action: save).buttonStyle(.bordered)
                Button("Wear today", action: wear).buttonStyle(.borderedProminent).tint(WardrobeDesign.Color.ink)
                Button("Not for today", action: skip).buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WardrobeDesign.Space.md)
        .background(WardrobeDesign.Color.card, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous).stroke(WardrobeDesign.Color.hairline))
        .sheet(isPresented: $showingWhy) {
            NavigationStack {
                List {
                    Section("Recommendation") {
                        LabeledContent("Score", value: "\(suggestion.score)")
                        LabeledContent("Source", value: suggestion.source.rawValue)
                    }
                    Section("Items and roles") {
                        ForEach(suggestion.itemIDs, id: \.self) { id in
                            if let item = store.item(id: id) {
                                LabeledContent(item.name, value: item.category)
                            }
                        }
                    }
                    Section("Scoring factors") {
                        ForEach(suggestion.factors) { factor in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(factor.name.capitalized); Spacer(); Text(factor.value >= 0 ? "+\(factor.value)" : "\(factor.value)").monospacedDigit() }
                                Text(factor.reason).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("Why this look?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showingWhy = false } } }
            }
        }
        .task(id: "\(suggestion.recommendationID?.uuidString ?? "none"):\(suggestion.source.rawValue)") {
            try? store.recordRecommendationOutcome(suggestion, outcome: .viewed)
        }
    }
}

private struct ComposeBuilderSheet: View {
    @ObservedObject var store: WardrobeStore
    @Binding var lockedItemIDs: [UUID]
    @Binding var requestedSlot: RecommendationSlot
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    private var activeItems: [GarmentItem] {
        store.allGarments.filter { $0.availability == .active }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Lock up to three pieces") {
                    ForEach(activeItems) { item in
                        Toggle(isOn: binding(for: item)) {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                Text(item.category).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel("Lock \(item.name), \(item.category)")
                    }
                }
                Section("What should stay open?") {
                    Picker("Requested slot", selection: $requestedSlot) {
                        Text("Complete look").tag(RecommendationSlot.completeLook)
                        Text("Footwear").tag(RecommendationSlot.footwear)
                        Text("Outerwear").tag(RecommendationSlot.outerwear)
                        Text("Accessory").tag(RecommendationSlot.accessory)
                        Text("Choose for me").tag(RecommendationSlot.chooseForMe)
                    }
                }
                if let message { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle("Compose a look")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        let locked = lockedItemIDs.compactMap { store.item(id: $0) }
                        if let validation = OutfitRecommendationEngine.validationMessage(lockedItems: locked, requestedSlots: [requestedSlot], allItems: store.allGarments) {
                            message = validation
                        } else { dismiss() }
                    }
                }
            }
        }
    }

    private func binding(for item: GarmentItem) -> Binding<Bool> {
        Binding(
            get: { lockedItemIDs.contains(item.id) },
            set: { selected in
                message = nil
                if selected {
                    guard lockedItemIDs.count < 3 else { message = "Lock up to three garments."; return }
                    let proposed = lockedItemIDs + [item.id]
                    let locked = proposed.compactMap { id in store.item(id: id) }
                    if let validation = OutfitRecommendationEngine.validationMessage(lockedItems: locked, requestedSlots: [requestedSlot], allItems: store.allGarments) {
                        message = validation
                    } else { lockedItemIDs = proposed }
                } else { lockedItemIDs.removeAll { $0 == item.id } }
            }
        )
    }
}

private struct ComponentReplacementSheet: View {
    let suggestion: OutfitSuggestion
    @ObservedObject var store: WardrobeStore
    let select: (UUID, GarmentItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(suggestion.itemIDs.compactMap { store.item(id: $0) }) { current in
                    Section(current.category) {
                        let alternatives = store.allGarments.filter { $0.availability == .active && $0.category == current.category && $0.id != current.id && !suggestion.itemIDs.contains($0.id) }
                        if alternatives.isEmpty {
                            Text("No other available \(current.category.lowercased()) in your wardrobe.").foregroundStyle(.secondary)
                        } else {
                            ForEach(alternatives) { alternative in
                                Button {
                                    select(current.id, alternative)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(alternative.name)
                                        Spacer()
                                        if let color = alternative.color { Text(color).foregroundStyle(.secondary) }
                                    }
                                }
                                .accessibilityLabel("Replace \(current.name) with \(alternative.name)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Replace a piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

private struct SkipReasonSheet: View {
    let select: (RecommendationSkipReason?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("What didn’t work?") {
                    Button("Skip without a reason") { select(nil); dismiss() }
                    ForEach(RecommendationSkipReason.allCases) { reason in
                        Button(reason.title) { select(reason); dismiss() }
                    }
                }
            }
            .navigationTitle("Not today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct WardrobeView: View {
    @ObservedObject var store: WardrobeStore
    @State private var isAdding = false
    @State private var isPhotoCapture = false
    @State private var isBatchCapturing = false
    @State private var isShowingPreferences = false
    @State private var selectedItem: GarmentItem?
    @State private var captureForEditing: GarmentCaptureCandidate?
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        Group {
            if let error = store.errorMessage {
                ContentUnavailableView {
                    IconoirLabel(title: "Couldn’t load wardrobe", icon: .warningTriangle)
                } description: {
                    Text(error)
                }
            } else if store.items.isEmpty {
                PhotoFirstEmptyState(startPhotoFlow: { isPhotoCapture = true }, startBatch: { isBatchCapturing = true })
            } else {
                ScrollView {
                    Button(action: { isPhotoCapture = true }) {
                        HStack(spacing: WardrobeDesign.Space.sm) {
                            IconoirIcon(.plus, size: 22)
                                .font(.title2.weight(.semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add a garment from a photo").font(WardrobeDesign.body(16).weight(.semibold))
                                Text("We’ll suggest the details, then you review them.").font(WardrobeDesign.body(13)).foregroundStyle(WardrobeDesign.Color.quiet)
                            }
                            Spacer()
                            IconoirIcon(.navArrowRight).foregroundStyle(WardrobeDesign.Color.quiet)
                        }
                        .padding(WardrobeDesign.Space.md)
                        .foregroundStyle(WardrobeDesign.Color.ink)
                        .background(WardrobeDesign.Color.card, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.top, 8)
                        if let message = store.searchModeMessage {
                IconoirLabel(title: message, icon: .textMagnifyingGlass)
                                .font(.footnote).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top, 8)
                                .accessibilityLabel("Search mode: \(message)")
                        }
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.items) { item in
                            Button { selectedItem = item } label: { GarmentCard(item: item, store: store) }
                                .buttonStyle(.plain).accessibilityLabel("\(item.name), \(item.category)")
                        }
                    }.padding()
                }
            }
        }
        .navigationTitle("Wardrobe")
        .font(WardrobeDesign.body())
        .searchable(text: $store.searchText, prompt: "Search garments, colors, tags, or describe a garment")
        .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu { Button("All categories") { store.selectedCategory = nil }; Divider(); ForEach(GarmentTaxonomy.categories, id: \.self) { category in Button(category) { store.selectedCategory = category } } } label: {
                    IconoirLabel(title: store.selectedCategory ?? "Filter", icon: .filterListCircle)
                    }.accessibilityLabel("Filter by category")
                }
                ToolbarItem(placement: .topBarTrailing) { Button { isShowingPreferences = true } label: { IconoirIcon(.user, size: 20) }.accessibilityLabel("Style profile") }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add from photo") { isPhotoCapture = true }
                        Button("Enter manually") { isAdding = true }
                        Button("Add several photos") { isBatchCapturing = true }
                    } label: { IconoirIcon(.plus, size: 22) }
                    .accessibilityLabel("Add a garment")
                }
        }
        .safeAreaInset(edge: .bottom) { if !store.availableTags.isEmpty { TagFilter(tags: store.availableTags, selected: $store.selectedTag) } }
        .sheet(isPresented: $isAdding) { GarmentEditor(store: store) }
        .sheet(isPresented: $isPhotoCapture) { GarmentCaptureSheet { captureForEditing = $0 } }
        .sheet(item: $captureForEditing) { candidate in GarmentEditor(store: store, initialCapture: candidate) }
        .sheet(isPresented: $isBatchCapturing) { BatchGarmentCaptureSheet(store: store) }
        .sheet(item: $selectedItem) { item in GarmentDetail(item: item, store: store) }
        .sheet(isPresented: $isShowingPreferences) { StyleProfileEditor(store: store) }
    }
}

private struct PhotoFirstEmptyState: View {
    let startPhotoFlow: () -> Void
    let startBatch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WardrobeDesign.Space.lg) {
            Spacer()
            IconoirIcon(.camera, size: 28)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(WardrobeDesign.Color.ink)
                .frame(width: 72, height: 72)
                .background(WardrobeDesign.Color.card, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
            Text("Start with one photo.")
                .font(WardrobeDesign.display(30))
            Text("Upload or take a clear photo of a garment. We’ll propose the details, and you approve them before it enters your wardrobe.")
                .font(WardrobeDesign.body(16))
                .foregroundStyle(WardrobeDesign.Color.quiet)
            Button(action: startPhotoFlow) {
                IconoirLabel(title: "Upload garment photo", icon: .mediaImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WardrobeDesign.Color.ink)
            .foregroundStyle(WardrobeDesign.Color.canvas)
            Button("Add several photos", action: startBatch)
                .buttonStyle(.bordered)
                .tint(WardrobeDesign.Color.quiet)
            Spacer()
        }
        .padding(WardrobeDesign.Space.xl)
    }
}

private struct TagFilter: View {
    let tags: [String]
    @Binding var selected: String?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack {
            Button("All tags") { selected = nil }.buttonStyle(.bordered).tint(selected == nil ? WardrobeDesign.Color.signal : WardrobeDesign.Color.quiet)
            ForEach(tags, id: \.self) { tag in Button(tag) { selected = tag }.buttonStyle(.bordered).tint(selected == tag ? WardrobeDesign.Color.signal : WardrobeDesign.Color.quiet) }
        }.padding(.horizontal).padding(.vertical, 8) }
        .background(WardrobeDesign.Color.paper).accessibilityElement(children: .contain).accessibilityLabel("Filter by tag")
    }
}

private struct GarmentCard: View {
    let item: GarmentItem
    @ObservedObject var store: WardrobeStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GarmentThumbnail(item: item, store: store).frame(height: 132)
            Text(item.name).font(WardrobeDesign.body(16).weight(.semibold)).lineLimit(2)
            Text(item.category.uppercased()).font(WardrobeDesign.metadata(10)).foregroundStyle(WardrobeDesign.Color.quiet)
            if let color = item.color, !color.isEmpty { Text(color).font(WardrobeDesign.body(12)).foregroundStyle(WardrobeDesign.Color.quiet) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(WardrobeDesign.Color.card, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous).stroke(WardrobeDesign.Color.hairline))
    }
}

private struct GarmentThumbnail: View {
    let item: GarmentItem
    @ObservedObject var store: WardrobeStore
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 16).fill(WardrobeDesign.Color.canvas)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 16)) }
                else { IconoirIcon(.shirt, size: 34).foregroundStyle(.secondary) }
            }
            .clipped()
            .task(id: item.imagePath) { image = store.imageData(for: item).flatMap(UIImage.init(data:)) }
            .accessibilityHidden(true)
    }
}
