import Foundation

struct GarmentItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var category: String
    var color: String?
    var tags: [String]
    var notes: String?
    var imagePath: String?
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

    init(
        name: String,
        category: String,
        color: String? = nil,
        tags: [String] = [],
        notes: String? = nil,
        imagePath: String? = nil
    ) {
        self.name = name
        self.category = category
        self.color = color
        self.tags = tags
        self.notes = notes
        self.imagePath = imagePath
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

struct StylePreferences: Equatable, Sendable {
    var preferredCategories: [String]
    var preferredColors: [String]
    var notes: String

    static let empty = StylePreferences(preferredCategories: [], preferredColors: [], notes: "")
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
    case corruptRecord

    var errorDescription: String? {
        switch self {
        case .invalidName: "A name is required."
        case .invalidCategory: "A category is required."
        case .itemNotFound: "That garment no longer exists."
        case .outfitNotFound: "That outfit no longer exists."
        case .itemIsReferenced: "Remove this garment from outfits and wear history before deleting it."
        case .duplicateOutfitItem: "An outfit can include a garment only once."
        case .corruptRecord: "A local wardrobe record could not be read."
        }
    }
}
