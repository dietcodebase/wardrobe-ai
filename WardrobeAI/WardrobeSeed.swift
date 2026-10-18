import Foundation

struct WardrobeSeedEntry: Equatable, Sendable {
    let key: String
    let draft: GarmentDraft
}

enum WardrobeSeed {
    static let entries = [
        WardrobeSeedEntry(key: "seed-navy-oxford", draft: GarmentDraft(name: "Navy Oxford", category: "Top", color: "Navy", tags: ["casual", "smart"])),
        WardrobeSeedEntry(key: "seed-straight-jeans", draft: GarmentDraft(name: "Straight Jeans", category: "Bottom", color: "Blue", tags: ["casual"])),
        WardrobeSeedEntry(key: "seed-white-sneakers", draft: GarmentDraft(name: "White Sneakers", category: "Shoes", color: "White", tags: ["casual", "everyday"])),
        WardrobeSeedEntry(key: "seed-cream-tee", draft: GarmentDraft(name: "Cream Tee", category: "Top", color: "Cream", tags: ["casual", "everyday"])),
        WardrobeSeedEntry(key: "seed-charcoal-trousers", draft: GarmentDraft(name: "Charcoal Trousers", category: "Bottom", color: "Charcoal", tags: ["smart", "work"])),
        WardrobeSeedEntry(key: "seed-olive-chore-jacket", draft: GarmentDraft(name: "Olive Chore Jacket", category: "Outerwear", color: "Olive", tags: ["casual", "layering"])),
        WardrobeSeedEntry(key: "seed-camel-overshirt", draft: GarmentDraft(name: "Camel Overshirt", category: "Outerwear", color: "Camel", tags: ["casual", "layering"])),
        WardrobeSeedEntry(key: "seed-black-blazer", draft: GarmentDraft(name: "Black Blazer", category: "Outerwear", color: "Black", tags: ["smart", "work", "evening"])),
        WardrobeSeedEntry(key: "seed-black-loafers", draft: GarmentDraft(name: "Black Loafers", category: "Shoes", color: "Black", tags: ["smart", "work", "evening"])),
        WardrobeSeedEntry(key: "seed-black-midi-dress", draft: GarmentDraft(name: "Black Midi Dress", category: "Dress", color: "Black", tags: ["smart", "evening"])),
        WardrobeSeedEntry(key: "seed-tan-ankle-boots", draft: GarmentDraft(name: "Tan Ankle Boots", category: "Shoes", color: "Tan", tags: ["smart", "evening"])),
        WardrobeSeedEntry(key: "seed-cream-knit", draft: GarmentDraft(name: "Cream Knit", category: "Top", color: "Cream", tags: ["smart", "layering"])),
        WardrobeSeedEntry(key: "seed-burgundy-crossbody", draft: GarmentDraft(name: "Burgundy Crossbody", category: "Accessory", color: "Burgundy", tags: ["evening", "accent"]))
    ]

    private static let outfitEntries: [(name: String, keys: [String], notes: String)] = [
        ("Smart Casual", ["seed-navy-oxford", "seed-straight-jeans", "seed-white-sneakers"], "A clean everyday combination."),
        ("Office Charcoal", ["seed-navy-oxford", "seed-charcoal-trousers", "seed-black-blazer", "seed-black-loafers"], "Polished tailoring for work."),
        ("Weekend Layers", ["seed-cream-tee", "seed-straight-jeans", "seed-olive-chore-jacket", "seed-white-sneakers"], "Easy layers for a casual day."),
        ("Soft Tailoring", ["seed-cream-tee", "seed-charcoal-trousers", "seed-camel-overshirt", "seed-black-loafers"], "Relaxed but put together."),
        ("Cream Knit Weekend", ["seed-cream-knit", "seed-straight-jeans", "seed-white-sneakers"], "A warm, low-key weekend look."),
        ("Evening Dress", ["seed-black-midi-dress", "seed-tan-ankle-boots", "seed-burgundy-crossbody"], "A complete evening look with a warm accent.")
    ]

    static func install(in repository: WardrobeRepository, imageStore: WardrobeImageStore? = nil) throws -> [GarmentItem] {
        let items = try entries.map { entry in
            var draft = entry.draft
            if try repository.item(seedKey: entry.key) == nil, let imageStore, let data = bundledImageData(for: entry.key) {
                draft.imagePath = try imageStore.store(data, fileExtension: "png")
            }
            return try repository.createSeedItem(draft, key: entry.key)
        }
        try installOutfits(in: repository)
        return items
    }

    private static func installOutfits(in repository: WardrobeRepository) throws {
        let existingNames = Set(try repository.allOutfits().map(\.name))
        for entry in outfitEntries where !existingNames.contains(entry.name) {
            let itemIDs = try entry.keys.map { key -> UUID in
                guard let item = try repository.item(seedKey: key) else {
                    throw WardrobeRepositoryError.itemNotFound(UUID())
                }
                return item.id
            }
            _ = try repository.createOutfit(OutfitDraft(name: entry.name, itemIDs: itemIDs, notes: entry.notes))
        }
    }

    private static func bundledImageData(for key: String) -> Data? {
        let names = [
            "seed-navy-oxford": "navy-oxford",
            "seed-straight-jeans": "straight-jeans",
            "seed-white-sneakers": "white-sneakers",
            "seed-cream-tee": "cream-tee",
            "seed-charcoal-trousers": "charcoal-trousers",
            "seed-olive-chore-jacket": "olive-chore-jacket",
            "seed-camel-overshirt": "camel-overshirt",
            "seed-black-blazer": "black-blazer",
            "seed-black-loafers": "black-loafers",
            "seed-black-midi-dress": "black-midi-dress",
            "seed-tan-ankle-boots": "tan-ankle-boots",
            "seed-cream-knit": "cream-knit",
            "seed-burgundy-crossbody": "burgundy-crossbody"
        ]
        guard let name = names[key], let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "SeedAssets") else { return nil }
        return try? Data(contentsOf: url)
    }
}
