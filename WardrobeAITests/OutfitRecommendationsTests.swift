import XCTest
@testable import WardrobeAI

final class OutfitRecommendationsTests: XCTestCase {
    func testBuildsValidTopBottomAndOnePieceSuggestions() {
        let top = item("Oxford", "Top", tags: ["work"])
        let bottom = item("Trousers", "Bottom", tags: ["work"])
        let dress = item("Black dress", "Dress")
        let shoe = item("Loafers", "Shoes")
        let results = OutfitRecommendationEngine().suggestions(items: [top, bottom, dress, shoe], preferences: .empty, wearEvents: [], context: .init(occasion: "Work", preferredColors: []))

        XCTAssertTrue(results.contains { Set($0.itemIDs).isSuperset(of: [top.id, bottom.id]) })
        XCTAssertTrue(results.contains { $0.itemIDs.contains(dress.id) })
        XCTAssertTrue(results.allSatisfy { Set($0.itemIDs).count == $0.itemIDs.count })
    }

    func testSparseWardrobeFallsBackToOwnedItemsOnly() {
        let shirt = item("Shirt", "Top")
        let results = OutfitRecommendationEngine().suggestions(items: [shirt], preferences: .empty, wearEvents: [])
        XCTAssertEqual(results.map(\.itemIDs), [[shirt.id]])
    }

    func testInvalidRankerIDsCannotCreateSuggestions() {
        let top = item("Top", "Top")
        let bottom = item("Bottom", "Bottom")
        let results = OutfitRecommendationEngine(ranker: InvalidRanker()).suggestions(items: [top, bottom], preferences: .empty, wearEvents: [])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(Set(results[0].itemIDs), Set([top.id, bottom.id]))
    }

    func testFixedContextsNeverReturnUnknownOrConflictingPrimaryItems() {
        let top = item("Oxford", "Top", tags: ["work"])
        let bottom = item("Trousers", "Bottom", tags: ["work"])
        let dress = item("Dress", "Dress", tags: ["evening"])
        let items = [top, bottom, dress, item("Shoes", "Shoes")]
        let contexts = ["Everyday", "Work", "Casual", "Formal", "Exercise", "Travel", "Evening", "Work", "Casual", "Everyday"]

        for occasion in contexts {
            let results = OutfitRecommendationEngine().suggestions(items: items, preferences: .empty, wearEvents: [], context: .init(occasion: occasion, preferredColors: []))
            XCTAssertTrue(results.allSatisfy { suggestion in
                let categories = suggestion.itemIDs.compactMap { id in items.first(where: { $0.id == id })?.category }
                return categories.count == suggestion.itemIDs.count
                    && categories.filter { $0 == "Top" }.count <= 1
                    && categories.filter { $0 == "Bottom" }.count <= 1
                    && !(categories.contains("Dress") && (categories.contains("Top") || categories.contains("Bottom")))
            })
        }
    }

    private func item(_ name: String, _ category: String, tags: [String] = []) -> GarmentItem {
        GarmentItem(id: UUID(), name: name, category: category, color: nil, tags: tags, notes: nil, imagePath: nil, classification: nil, createdAt: .now, updatedAt: .now)
    }
}

private struct InvalidRanker: OutfitCandidateRanker {
    func rank(candidateIDs: [UUID], context: RecommendationContext) -> [UUID]? { [UUID()] }
}
