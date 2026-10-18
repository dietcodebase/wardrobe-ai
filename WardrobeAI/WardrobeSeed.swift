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
        WardrobeSeedEntry(key: "seed-tan-ankle-boots", assetName: "tan-ankle-boots", draft: GarmentDraft(name: "Tan Ankle Boots", category: "Shoes", color: "Tan", tags: ["casual", "smart casual"])),
        WardrobeSeedEntry(key: "seed-emerald-sari-blouse", assetName: "emerald-sari-blouse", draft: GarmentDraft(name: "Emerald Sari Blouse", category: "Top", color: "Emerald", tags: ["international", "festive", "silk"])),
        WardrobeSeedEntry(key: "seed-indigo-yukata-jacket", assetName: "indigo-yukata-jacket", draft: GarmentDraft(name: "Indigo Yukata Jacket", category: "Outerwear", color: "Indigo", tags: ["international", "printed", "layering"])),
        WardrobeSeedEntry(key: "seed-white-guayabera", assetName: "white-guayabera", draft: GarmentDraft(name: "White Linen Guayabera", category: "Top", color: "White", tags: ["international", "linen", "travel"])),
        WardrobeSeedEntry(key: "seed-red-batik-overshirt", assetName: "red-batik-overshirt", draft: GarmentDraft(name: "Red Batik Overshirt", category: "Outerwear", color: "Red", tags: ["international", "pattern", "statement"])),
        WardrobeSeedEntry(key: "seed-cream-moroccan-kaftan", assetName: "cream-moroccan-kaftan", draft: GarmentDraft(name: "Cream Moroccan Kaftan", category: "One-piece outfit", color: "Cream", tags: ["international", "evening", "flowing"])),
        WardrobeSeedEntry(key: "seed-blue-denim-chore-jacket", assetName: "blue-denim-chore-jacket", draft: GarmentDraft(name: "Blue Denim Chore Jacket", category: "Outerwear", color: "Blue", tags: ["international", "denim", "utility"])),
        WardrobeSeedEntry(key: "seed-black-agbada-top", assetName: "black-agbada-top", draft: GarmentDraft(name: "Black Agbada Top", category: "Top", color: "Black", tags: ["international", "formal", "statement"])),
        WardrobeSeedEntry(key: "seed-rust-peruvian-cardigan", assetName: "rust-peruvian-cardigan", draft: GarmentDraft(name: "Rust Peruvian Cardigan", category: "Outerwear", color: "Rust", tags: ["international", "knitwear", "pattern"])),
        WardrobeSeedEntry(key: "seed-ivory-qipao-dress", assetName: "ivory-qipao-dress", draft: GarmentDraft(name: "Ivory Qipao Dress", category: "Dress", color: "Ivory", tags: ["international", "evening", "silk"])),
        WardrobeSeedEntry(key: "seed-charcoal-tartan-kilt", assetName: "charcoal-tartan-kilt", draft: GarmentDraft(name: "Charcoal Tartan Kilt", category: "Bottom", color: "Charcoal", tags: ["international", "tartan", "statement"]))
    ]

    static func install(in repository: WardrobeRepository, imageStore: WardrobeImageStore? = nil, bundle: Bundle = .main) throws -> [GarmentItem] {
        let items = try entries.map { entry in
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

        let byKey = Dictionary(uniqueKeysWithValues: zip(entries.map(\.key), items))
        let outfitSeeds: [(String, [String], String)] = [
            ("Indigo travel layers", ["seed-indigo-yukata-jacket", "seed-white-guayabera", "seed-straight-jeans", "seed-white-sneakers"], "A breathable, easy-moving layer set for city days."),
            ("Emerald evening", ["seed-emerald-sari-blouse", "seed-charcoal-trousers", "seed-black-loafers", "seed-burgundy-crossbody"], "Festive color with a grounded, walkable base."),
            ("Modern heritage", ["seed-black-agbada-top", "seed-charcoal-tartan-kilt", "seed-tan-ankle-boots"], "A statement silhouette balanced by tonal texture."),
            ("Ivory occasion", ["seed-ivory-qipao-dress", "seed-black-loafers", "seed-burgundy-crossbody"], "Polished evening dressing with a practical accent bag."),
            ("Warm market layers", ["seed-cream-moroccan-kaftan", "seed-rust-peruvian-cardigan", "seed-tan-ankle-boots"], "Soft texture and warm neutrals for cooler nights.")
        ]
        let existingNames = Set(try repository.allOutfits().map(\.name))
        for (name, keys, notes) in outfitSeeds where !existingNames.contains(name) {
            let itemIDs = keys.compactMap { byKey[$0]?.id }
            if !itemIDs.isEmpty { _ = try repository.createOutfit(OutfitDraft(name: name, itemIDs: itemIDs, notes: notes)) }
        }
        return items
    }
}
