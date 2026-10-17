import Foundation
import Combine

enum WardrobeStoreError: LocalizedError {
    case imageStorageUnavailable

    var errorDescription: String? {
        switch self {
        case .imageStorageUnavailable: "Photo storage is unavailable. Your garment was not saved. Try again after freeing device storage or restarting the app."
        }
    }
}

@MainActor
final class WardrobeStore: ObservableObject {
    @Published private(set) var items: [GarmentItem] = []
    @Published private(set) var outfits: [Outfit] = []
    @Published private(set) var wearEvents: [WearEvent] = []
    @Published private(set) var underusedItems: [WearItemSummary] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var searchModeMessage: String?
    @Published var searchText = "" { didSet { loadItems() } }
    @Published var selectedCategory: String? { didSet { loadItems() } }
    @Published var selectedTag: String? { didSet { loadItems() } }

    let repository: WardrobeRepository
    private let imageCoordinator: GarmentImageCoordinator?

    init(repository: WardrobeRepository, imageStore: WardrobeImageStore? = nil) {
        self.repository = repository
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

    func recommendations(for occasion: String?, anchorItemID: UUID? = nil, weather: WeatherSnapshot? = nil, ranker: (any OutfitCandidateRanker)? = nil) throws -> [OutfitSuggestion] {
        let preferences = try repository.preferences()
        return OutfitRecommendationEngine(ranker: ranker).suggestions(
            items: allGarments,
            preferences: preferences,
            wearEvents: wearEvents,
            context: RecommendationContext(occasion: occasion, preferredColors: preferences.preferredColors, anchorItemID: anchorItemID, weather: weather)
        )
    }

    func saveSuggestion(_ suggestion: OutfitSuggestion) throws -> Outfit {
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
        let outfit = try saveSuggestion(suggestion)
        return try wearToday(outfit)
    }
}
