import Foundation

struct WardrobeSeedEntry: Equatable, Sendable {
    let key: String
    let draft: GarmentDraft
}

enum WardrobeSeed {
    static let entries = [
        WardrobeSeedEntry(key: "seed-navy-oxford", draft: GarmentDraft(name: "Navy Oxford", category: "Top", color: "Navy", tags: ["casual", "smart"])),
        WardrobeSeedEntry(key: "seed-straight-jeans", draft: GarmentDraft(name: "Straight Jeans", category: "Bottom", color: "Blue", tags: ["casual"])),
        WardrobeSeedEntry(key: "seed-white-sneakers", draft: GarmentDraft(name: "White Sneakers", category: "Shoes", color: "White", tags: ["casual", "everyday"]))
    ]

    static func install(in repository: WardrobeRepository) throws -> [GarmentItem] {
        try entries.map { entry in
            try repository.createSeedItem(entry.draft, key: entry.key)
        }
    }
}
