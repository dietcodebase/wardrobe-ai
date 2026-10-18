import Foundation
import Combine

enum WardrobeStoreError: LocalizedError {
    case imageStorageUnavailable
    case noDemoPhotos

    var errorDescription: String? {
        switch self {
        case .imageStorageUnavailable: "Photo storage is unavailable. Your garment was not saved. Try again after freeing device storage or restarting the app."
        case .noDemoPhotos: "Load the demo wardrobe before asking Gemma to tag its photos."
        }
    }
}

@MainActor
final class WardrobeStore: ObservableObject {
    @Published private(set) var items: [GarmentItem] = []
    @Published private(set) var outfits: [Outfit] = []
    @Published private(set) var wearEvents: [WearEvent] = []
    @Published private(set) var outfitPlans: [OutfitPlan] = []
    @Published private(set) var underusedItems: [WearItemSummary] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var searchModeMessage: String?
    @Published var searchText = "" { didSet { loadItems() } }
    @Published var selectedCategory: String? { didSet { loadItems() } }
    @Published var selectedTag: String? { didSet { loadItems() } }

    let repository: WardrobeRepository
    private let imageCoordinator: GarmentImageCoordinator?
    private let imageStore: WardrobeImageStore?

    init(repository: WardrobeRepository, imageStore: WardrobeImageStore? = nil) {
        self.repository = repository
        self.imageStore = imageStore
        self.imageCoordinator = imageStore.map { GarmentImageCoordinator(repository: repository, imageStore: $0) }
        loadItems()
        loadOutfitData()
    }

    var availableTags: [String] {
        Array(Set(items.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func item(id: UUID) -> GarmentItem? {
        try? repository.item(id: id)
    }

    var allGarments: [GarmentItem] { (try? repository.allItems()) ?? [] }

    func loadItems() {
        do {
            items = try repository.items(matching: searchText, category: selectedCategory, tag: selectedTag)
            searchModeMessage = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : "Showing text matches. Semantic search will be available after this device passes the embedding qualification."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadOutfitData() {
        do {
            outfits = try repository.allOutfits()
            wearEvents = try repository.wearEvents()
            outfitPlans = try repository.plans()
            underusedItems = try repository.underusedItems()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ item: GarmentItem?, imageData: Data? = nil) throws {
        if let item {
            if let imageData {
                guard let imageCoordinator else { throw WardrobeStoreError.imageStorageUnavailable }
                _ = try imageCoordinator.updateItem(item, replacingImageWith: imageData)
            } else {
                _ = try repository.updateItem(item)
            }
        }
        loadItems()
        loadOutfitData()
    }

    func create(_ draft: GarmentDraft) throws {
        _ = try repository.createItem(draft)
        loadItems()
        loadOutfitData()
    }

    func create(_ draft: GarmentDraft, imageData: Data?) throws {
        if let imageData {
            guard let imageCoordinator else { throw WardrobeStoreError.imageStorageUnavailable }
            _ = try imageCoordinator.createItem(draft, imageData: imageData)
        } else {
            _ = try repository.createItem(draft)
        }
        loadItems()
        loadOutfitData()
    }

    func replaceImage(for item: GarmentItem, with imageData: Data) throws -> GarmentItem {
        guard let imageCoordinator else { throw WardrobeStoreError.imageStorageUnavailable }
        let updated = try imageCoordinator.replaceImage(for: item.id, with: imageData)
        loadItems()
        loadOutfitData()
        return updated
    }

    func imageData(for item: GarmentItem) -> Data? {
        guard let path = item.imagePath, let imageCoordinator else { return nil }
        return try? imageCoordinator.imageData(at: path)
    }

    func saveClassification(_ provenance: ClassificationProvenance, for itemID: UUID) throws -> GarmentItem {
        guard var item = try repository.item(id: itemID) else { throw WardrobeRepositoryError.itemNotFound(itemID) }
        item.category = provenance.suggestion.category
        item.name = provenance.suggestion.suggestedName ?? item.name
        item.color = provenance.suggestion.color ?? item.color
        item.tags = provenance.suggestion.tags
        item.classification = provenance
        let saved = try repository.updateItem(item)
        loadItems()
        loadOutfitData()
        return saved
    }

    func installDemoWardrobe() throws {
        _ = try installDemoWardrobeAssets()
    }

    private func installDemoWardrobeAssets() throws -> [GarmentItem] {
        let items = try WardrobeSeed.install(in: repository, imageStore: imageStore)
        loadItems()
        loadOutfitData()
        return items
    }

    /// Runs one serialized Gemma vision request per stored photo. Tags are
    /// additive so the demo remains useful if a later model response is sparse.
    func tagDemoWardrobe(classifier: any GarmentClassifying = OllamaGarmentClassifier()) async throws -> Int {
        _ = try installDemoWardrobeAssets()
        let seedIDs = Set(WardrobeSeed.entries.compactMap { try? repository.item(seedKey: $0.key)?.id })
        let candidates = allGarments.filter { seedIDs.contains($0.id) && $0.imagePath != nil && $0.classification == nil }
        guard !candidates.isEmpty else { throw WardrobeStoreError.noDemoPhotos }
        let coordinator = GarmentClassificationCoordinator(classifier: classifier)
        var tagged = 0
        for item in candidates {
            try Task.checkCancellation()
            guard let imageData = imageData(for: item) else { continue }
            let provenance = try await coordinator.classify(imageData: imageData)
            var updated = item
            updated.category = provenance.suggestion.category
            updated.color = provenance.suggestion.color ?? updated.color
            updated.tags = Array(Set(item.tags + provenance.suggestion.tags)).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            updated.classification = provenance
            if let suggestedName = provenance.suggestion.suggestedName, !suggestedName.isEmpty { updated.name = suggestedName }
            _ = try repository.updateItem(updated)
            tagged += 1
        }
        loadItems()
        loadOutfitData()
        return tagged
    }

    func delete(_ item: GarmentItem) throws {
        if let imageCoordinator { try imageCoordinator.deleteItem(id: item.id) }
        else { try repository.deleteItem(id: item.id) }
        loadItems()
        loadOutfitData()
    }

    func createOutfit(_ draft: OutfitDraft) throws {
        _ = try repository.createOutfit(draft)
        loadOutfitData()
    }

    func updateOutfit(_ outfit: Outfit) throws {
        _ = try repository.updateOutfit(outfit)
        loadOutfitData()
    }

    func deleteOutfit(_ outfit: Outfit) throws {
        try repository.deleteOutfit(id: outfit.id)
        loadOutfitData()
    }

    func wearToday(_ outfit: Outfit) throws -> WearEvent {
        let event = try repository.wearToday(outfitID: outfit.id)
        loadOutfitData()
        return event
    }

    func undoWear(_ event: WearEvent) throws {
        try repository.undoWear(eventID: event.id)
        loadOutfitData()
    }

    func schedule(_ outfit: Outfit, for date: Date, occasion: String? = nil, sourceEventID: String? = nil) throws {
        _ = try repository.createPlan(outfitID: outfit.id, scheduledFor: date, occasion: occasion, sourceEventID: sourceEventID)
        loadOutfitData()
    }

    func removePlan(_ plan: OutfitPlan) throws {
        try repository.deletePlan(id: plan.id)
        loadOutfitData()
    }

    func recommendations(for occasion: String?, anchorItemID: UUID? = nil, weather: WeatherSnapshot? = nil, weatherFreshness: WeatherFreshness? = nil, ranker: (any OutfitCandidateRanker)? = nil) throws -> [OutfitSuggestion] {
        let preferences = try repository.preferences()
        let context = RecommendationContext(occasion: occasion, preferredColors: preferences.preferredColors, preferredCategories: preferences.preferredCategories, anchorItemID: anchorItemID, weather: weather, weatherFreshness: weatherFreshness)
        return try recommendations(context: context, ranker: ranker)
    }

    func recommendations(context requestedContext: RecommendationContext, ranker: (any OutfitCandidateRanker)? = nil) throws -> [OutfitSuggestion] {
        let preferences = try repository.preferences()
        var context = requestedContext
        if context.preferredColors.isEmpty { context.preferredColors = preferences.preferredColors }
        if context.preferredCategories.isEmpty { context.preferredCategories = preferences.preferredCategories }
        let generated = OutfitRecommendationEngine(ranker: ranker).suggestions(
            items: allGarments,
            preferences: preferences,
            wearEvents: wearEvents,
            context: context
        )
        let hasContext = context.occasion != nil || context.anchorItemID != nil || !context.preferredColors.isEmpty || !context.preferredCategories.isEmpty || context.weather != nil || !(context.dressCodeNote ?? "").isEmpty || !context.lockedItemIDs.isEmpty || !context.requestedSlots.isEmpty || context.warmth != .any || context.tolerateRain || context.prioritizeWalkingComfort || context.repeatFrequency != .any || !context.calendarBusyPeriods.isEmpty
        let source: RecommendationSource = ranker != nil ? .ollamaRanking : (context.weatherFreshness == .cached ? .cachedWeather : (hasContext ? .localRules : .noContext))
        let results = generated.map { OutfitSuggestion(id: $0.id, itemIDs: $0.itemIDs, score: $0.score, explanation: $0.explanation, factors: $0.factors, recommendationID: $0.recommendationID, source: source) }
        return results
    }

    func recordRecommendation(_ suggestions: [OutfitSuggestion], context: RecommendationContext, source: RecommendationSource, outcome: RecommendationOutcome) throws {
        let recommendationID = suggestions.first?.recommendationID ?? UUID()
        let snapshotLockedIDs = context.lockedItemIDs.isEmpty ? suggestions.first?.itemIDs ?? [] : context.lockedItemIDs
        let snapshot: [String: Any] = [
            "occasion": context.occasion as Any? ?? NSNull(),
            "anchorItemID": context.anchorItemID?.uuidString as Any? ?? NSNull(),
            "preferredColors": context.preferredColors,
            "preferredCategories": context.preferredCategories,
            "recentWearItemIDs": Array(Set(wearEvents.prefix(3).flatMap(\.itemIDs))).map(\.uuidString).sorted(),
            "dressCodeNote": context.dressCodeNote as Any? ?? NSNull(),
            "requestedSlots": context.requestedSlots.map(\.rawValue),
            "warmth": context.warmth.rawValue,
            "weatherFreshness": context.weatherFreshness?.rawValue as Any? ?? NSNull(),
            "weather": context.weather.map { ["city": $0.location.normalizedCity, "temperatureCelsius": $0.temperatureCelsius, "condition": $0.condition.rawValue, "fetchedAt": $0.fetchedAt.timeIntervalSince1970] as [String: Any] } as Any? ?? NSNull(),
            "formalityPreference": context.formality as Any? ?? NSNull(),
            "footwearPreference": context.footwearPreference as Any? ?? NSNull(),
            "tolerateRain": context.tolerateRain,
            "prioritizeWalkingComfort": context.prioritizeWalkingComfort,
            "repeatFrequency": context.repeatFrequency.rawValue,
            "lockedItemIDs": snapshotLockedIDs.map(\.uuidString),
            "calendarBusyPeriods": context.calendarBusyPeriods.map { ["start": $0.startDate.timeIntervalSince1970, "end": $0.endDate.timeIntervalSince1970, "allDay": $0.isAllDay] as [String: Any] }
        ]
        var snapshotWithCandidates = snapshot
        snapshotWithCandidates["candidateItems"] = Dictionary(uniqueKeysWithValues: suggestions.map { ($0.id.uuidString, $0.itemIDs.map(\.uuidString)) })
        let data = try JSONSerialization.data(withJSONObject: snapshotWithCandidates, options: [.sortedKeys])
        let candidateIDs = suggestions.map(\.id)
        let event = RecommendationEvent(id: UUID(), recommendationID: recommendationID, candidateIDs: candidateIDs, contextSnapshot: String(decoding: data, as: UTF8.self), source: source, outcome: outcome, occurredAt: .now, lockedItemIDs: snapshotLockedIDs, requestedSlots: context.requestedSlots)
        try repository.recordRecommendationEvent(event)
    }

    func recordRecommendationOutcome(_ suggestion: OutfitSuggestion, outcome: RecommendationOutcome, reason: RecommendationSkipReason? = nil) throws {
        guard let recommendationID = suggestion.recommendationID else { return }
        let context = try repository.recommendationContext(recommendationID: recommendationID)
        let event = RecommendationEvent(id: UUID(), recommendationID: recommendationID, candidateIDs: [suggestion.id], contextSnapshot: context?.snapshot ?? "{}", source: suggestion.source, outcome: outcome, occurredAt: .now, lockedItemIDs: context?.lockedItemIDs ?? [], requestedSlots: context?.requestedSlots ?? [], outcomeReason: reason)
        try repository.recordRecommendationEvent(event)
    }

    func replacing(_ suggestion: OutfitSuggestion, itemID: UUID, with replacement: GarmentItem, context: RecommendationContext) throws -> OutfitSuggestion? {
        let preferences = try repository.preferences()
        let result = OutfitRecommendationEngine().replacing(itemID, in: suggestion, with: replacement, items: allGarments, preferences: preferences, wearEvents: wearEvents, context: context)
        if let result { try recordRecommendation([result], context: context, source: result.source, outcome: .generated) }
        return result
    }

    func saveSuggestion(_ suggestion: OutfitSuggestion) throws -> Outfit {
        let outfit = try persistSuggestion(suggestion)
        try recordRecommendationOutcome(suggestion, outcome: .saved)
        return outfit
    }

    private func persistSuggestion(_ suggestion: OutfitSuggestion) throws -> Outfit {
        let suggestionItems = Set(suggestion.itemIDs)
        if let existing = try repository.allOutfits().first(where: { Set($0.itemIDs) == suggestionItems }) {
            return existing
        }
        let names = suggestion.itemIDs.compactMap { item(id: $0)?.name }.joined(separator: " + ")
        let outfit = try repository.createOutfit(OutfitDraft(name: names.isEmpty ? "Suggested outfit" : names, itemIDs: suggestion.itemIDs))
        loadOutfitData()
        return outfit
    }

    func wearSuggestion(_ suggestion: OutfitSuggestion) throws -> WearEvent {
        let outfit = try persistSuggestion(suggestion)
        let event = try wearToday(outfit)
        try recordRecommendationOutcome(suggestion, outcome: .worn)
        return event
    }
}
