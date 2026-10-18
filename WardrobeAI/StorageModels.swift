import Foundation
import SwiftUI

/// App-wide visual tokens. The naming follows the Cornholio ink/paper/signal
/// language, but the values are tuned for a calm, OLED-friendly dark wardrobe.
enum WardrobeDesign {
    enum Color {
        static let ink = SwiftUI.Color(red: 0.94, green: 0.94, blue: 0.94)
        static let paper = SwiftUI.Color(red: 0.105, green: 0.105, blue: 0.105)
        static let canvas = SwiftUI.Color(red: 0.045, green: 0.045, blue: 0.045)
        static let card = SwiftUI.Color(red: 0.145, green: 0.145, blue: 0.145)
        static let signal = SwiftUI.Color(red: 0.88, green: 0.88, blue: 0.88)
        static let moss = SwiftUI.Color(red: 0.70, green: 0.70, blue: 0.70)
        static let quiet = SwiftUI.Color(red: 0.62, green: 0.62, blue: 0.62)
        static let hairline = SwiftUI.Color.white.opacity(0.12)
    }
    enum Space {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }
    enum Radius { static let chip: CGFloat = 12; static let card: CGFloat = 20 }
    /// Plus Jakarta Sans is represented by the native rounded face here so the
    /// hierarchy stays consistent until a bundled font resource is introduced.
    static func display(_ size: CGFloat = 26) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func body(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .regular, design: .rounded) }
    static func metadata(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .semibold, design: .monospaced) }
}

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

struct OutfitPlan: Identifiable, Equatable, Sendable {
    let id: UUID
    var outfitID: UUID
    var scheduledFor: Date
    var occasion: String?
    var sourceEventID: String?
    let createdAt: Date
    var updatedAt: Date
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
    static let patterns = ["Solid", "Stripe", "Check", "Plaid", "Floral", "Geometric", "Animal", "Graphic", "Textured", "Other"]
    static let fabrics = ["Cotton", "Linen", "Wool", "Cashmere", "Denim", "Leather", "Silk", "Polyester", "Knit", "Unknown"]
    static let textures = ["Smooth", "Soft", "Ribbed", "Brushed", "Crisp", "Coarse", "Lustrous", "Woven", "Quilted"]
    static let fits = ["Slim", "Regular", "Relaxed", "Oversized", "Tailored", "Cropped", "Wide-leg"]
    static let silhouettes = ["Straight", "A-line", "Boxy", "Structured", "Draped", "Tapered", "Flowing"]
    static let layering = ["Base layer", "Mid layer", "Top layer", "Standalone", "Light layer"]
    static let warmthLevels = ["Light", "Medium", "Warm", "Very warm"]
    static let formalityLevels = ["Relaxed", "Smart casual", "Work", "Formal", "Evening"]
    static let styleKeywords = ["Minimal", "Classic", "Sporty", "Utility", "Romantic", "Street", "Preppy", "Modern", "Vintage"]

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
    case planNotFound(UUID)
    case itemNotInOutfit(itemID: UUID, outfitID: UUID)
    case wearEventLogRequiresUndo(UUID)

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
        case .planNotFound: "That outfit plan no longer exists."
        case .itemNotInOutfit: "That garment is not part of the selected outfit."
        case .wearEventLogRequiresUndo: "Undo the wear event instead of removing one of its garment records."
        }
    }
}
