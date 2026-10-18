import Foundation

struct WardrobeSeedEntry: Equatable, Sendable {
    let key: String
    let assetName: String
    let draft: GarmentDraft
}

enum WardrobeSeed {
    /// Names/categories give the demo an offline fallback. Gemma can enrich
    /// each stored photo after import.
    static let entries = [
        WardrobeSeedEntry(key: "seed-navy-oxford", assetName: "navy-oxford", draft: GarmentDraft(name: "Navy Oxford", category: "Top", color: "Navy", tags: ["smart casual", "work"])),
        WardrobeSeedEntry(key: "seed-straight-jeans", assetName: "straight-jeans", draft: GarmentDraft(name: "Straight Jeans", category: "Bottom", color: "Blue", tags: ["casual", "denim"])),
        WardrobeSeedEntry(key: "seed-cream-knit", assetName: "cream-knit", draft: GarmentDraft(name: "Cream Knit", category: "Top", color: "Cream", tags: ["knitwear", "layering"])),
        WardrobeSeedEntry(key: "seed-olive-chore-jacket", assetName: "olive-chore-jacket", draft: GarmentDraft(name: "Olive Chore Jacket", category: "Outerwear", color: "Olive", tags: ["casual", "layering"])),
        WardrobeSeedEntry(key: "seed-camel-overshirt", assetName: "camel-overshirt", draft: GarmentDraft(name: "Camel Overshirt", category: "Outerwear", color: "Camel", tags: ["smart casual", "layering"])),
        WardrobeSeedEntry(key: "seed-cream-tee", assetName: "cream-tee", draft: GarmentDraft(name: "Cream Tee", category: "Top", color: "Cream", tags: ["casual", "everyday"])),
        WardrobeSeedEntry(key: "seed-white-sneakers", assetName: "white-sneakers", draft: GarmentDraft(name: "White Sneakers", category: "Shoes", color: "White", tags: ["casual", "everyday"])),
        WardrobeSeedEntry(key: "seed-black-blazer", assetName: "black-blazer", draft: GarmentDraft(name: "Black Blazer", category: "Outerwear", color: "Black", tags: ["formal", "work"])),
        WardrobeSeedEntry(key: "seed-burgundy-crossbody", assetName: "burgundy-crossbody", draft: GarmentDraft(name: "Burgundy Crossbody", category: "Accessory", color: "Burgundy", tags: ["evening", "everyday"])),
        WardrobeSeedEntry(key: "seed-black-loafers", assetName: "black-loafers", draft: GarmentDraft(name: "Black Loafers", category: "Shoes", color: "Black", tags: ["work", "formal"])),
        WardrobeSeedEntry(key: "seed-black-midi-dress", assetName: "black-midi-dress", draft: GarmentDraft(name: "Black Midi Dress", category: "Dress", color: "Black", tags: ["evening", "formal"])),
        WardrobeSeedEntry(key: "seed-charcoal-trousers", assetName: "charcoal-trousers", draft: GarmentDraft(name: "Charcoal Trousers", category: "Bottom", color: "Charcoal", tags: ["work", "smart casual"])),
        WardrobeSeedEntry(key: "seed-tan-ankle-boots", assetName: "tan-ankle-boots", draft: GarmentDraft(name: "Tan Ankle Boots", category: "Shoes", color: "Tan", tags: ["casual", "smart casual"]))
    ]

    static func install(in repository: WardrobeRepository, imageStore: WardrobeImageStore? = nil, bundle: Bundle = .main) throws -> [GarmentItem] {
        try entries.map { entry in
            let item = try repository.createSeedItem(entry.draft, key: entry.key)
            guard item.imagePath == nil,
                  let imageStore,
                  let url = bundle.url(forResource: entry.assetName, withExtension: "png", subdirectory: "SeedAssets"),
                  let data = try? Data(contentsOf: url) else {
                return item
            }
            var updated = item
            let path = try imageStore.store(data, fileExtension: "png")
            updated.imagePath = path
            do { return try repository.updateItem(updated) }
            catch { try? imageStore.remove(path); throw error }
        }
    }
}
