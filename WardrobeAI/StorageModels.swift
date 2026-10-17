import Foundation

struct GarmentItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var category: String
    var color: String?
    var tags: [String]
    var notes: String?
    var imagePath: String?
    var classification: ClassificationProvenance?
    let createdAt: Date
    var updatedAt: Date
}

struct GarmentDraft: Equatable, Sendable {
    var name: String
    var category: String
    var color: String?
    var tags: [String]
    var notes: String?
    var imagePath: String?
    var classification: ClassificationProvenance?

    init(
        name: String,
        category: String,
        color: String? = nil,
        tags: [String] = [],
        notes: String? = nil,
        imagePath: String? = nil,
        classification: ClassificationProvenance? = nil
    ) {
        self.name = name
        self.category = category
        self.color = color
        self.tags = tags
        self.notes = notes
        self.imagePath = imagePath
        self.classification = classification
    }
}

struct Outfit: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var notes: String?
    var isFavorite: Bool
    let createdAt: Date
    var updatedAt: Date
    var itemIDs: [UUID]
}

struct OutfitDraft: Equatable, Sendable {
    var name: String
    var itemIDs: [UUID]
    var notes: String?
    var isFavorite: Bool

    init(name: String, itemIDs: [UUID], notes: String? = nil, isFavorite: Bool = false) {
        self.name = name
        self.itemIDs = itemIDs
        self.notes = notes
        self.isFavorite = isFavorite
    }
}

struct WearLog: Identifiable, Equatable, Sendable {
    let id: UUID
    let itemID: UUID
    let outfitID: UUID?
    let wornAt: Date
    let createdAt: Date
}

struct WearEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let outfitID: UUID?
    let wornAt: Date
    let localDay: String
    let createdAt: Date
    var itemIDs: [UUID]
}

struct WearItemSummary: Identifiable, Equatable, Sendable {
    let item: GarmentItem
    let wearCount: Int
    let lastWornAt: Date?

    var id: UUID { item.id }
}

struct StylePreferences: Equatable, Sendable {
    var preferredCategories: [String]
    var preferredColors: [String]
    var notes: String

    static let empty = StylePreferences(preferredCategories: [], preferredColors: [], notes: "")
}

struct EmbeddingMetadata: Codable, Equatable, Sendable {
    let modelID: String
    let modelRevision: String
    let dimension: Int
    let normalized: Bool
    let preprocessingVersion: String

    static let embeddingGemma2 = EmbeddingMetadata(
        modelID: "embeddinggemma-2-740m",
        modelRevision: "24d962e906c7d332c6428e71c9676855024569e2",
        dimension: 768,
        normalized: true,
        preprocessingVersion: "pending-prefix-evaluation-v1"
    )
}

struct GarmentEmbedding: Equatable, Sendable {
    let itemID: UUID
    let metadata: EmbeddingMetadata
    let contentHash: String
    let vector: [Float]
    let indexedAt: Date
}

enum SemanticSearchError: LocalizedError, Equatable {
    case unavailable
    case invalidVector
    case incompatibleVector

    var errorDescription: String? {
        switch self {
        case .unavailable: "Semantic search is not available on this device. Showing text matches instead."
        case .invalidVector: "The local embedding was invalid and was not saved."
        case .incompatibleVector: "The local embedding does not match this search index."
        }
    }
}

enum GarmentTaxonomy {
    static let categories = ["Top", "Bottom", "Dress", "One-piece outfit", "Outerwear", "Shoes", "Accessory"]
    static let occasions = ["Everyday", "Work", "Casual", "Formal", "Exercise", "Travel", "Evening"]

    static func isKnownCategory(_ category: String) -> Bool {
        categories.contains(category)
    }
}

enum WardrobeRepositoryError: Error, Equatable, LocalizedError {
    case invalidName
    case invalidCategory
    case itemNotFound(UUID)
    case outfitNotFound(UUID)
    case itemIsReferenced(UUID)
    case duplicateOutfitItem(UUID)
    case emptyOutfit
    case corruptRecord

    var errorDescription: String? {
        switch self {
        case .invalidName: "A name is required."
        case .invalidCategory: "A category is required."
        case .itemNotFound: "That garment no longer exists."
        case .outfitNotFound: "That outfit no longer exists."
        case .itemIsReferenced: "Remove this garment from outfits and wear history before deleting it."
        case .duplicateOutfitItem: "An outfit can include a garment only once."
        case .emptyOutfit: "Add at least one garment before saving this outfit."
        case .corruptRecord: "A local wardrobe record could not be read."
        }
    }
}
