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

    func testAnchorAppearsAndOptionalAlternativesAreConsideredWithinBound() {
        let top = item("Top", "Top")
        let bottom = item("Bottom", "Bottom")
        let shoesA = item("Sneakers", "Shoes", color: "White")
        let shoesB = item("Loafers", "Shoes", color: "Black")
        let results = OutfitRecommendationEngine().suggestions(
            items: [top, bottom, shoesA, shoesB],
            preferences: .empty,
            wearEvents: [],
            context: .init(occasion: nil, preferredColors: [], anchorItemID: shoesB.id)
        )

        XCTAssertLessThanOrEqual(results.count, 24)
        XCTAssertTrue(results.allSatisfy { $0.itemIDs.contains(shoesB.id) })
        let allResults = OutfitRecommendationEngine().suggestions(items: [top, bottom, shoesA, shoesB], preferences: .empty, wearEvents: [])
        XCTAssertTrue(allResults.contains { $0.itemIDs.contains(shoesA.id) })
        XCTAssertTrue(allResults.contains { $0.itemIDs.contains(shoesB.id) })
    }

    func testFreshRainContextFavorsOuterwearAndLabelsTheSource() {
        let top = item("Top", "Top")
        let bottom = item("Bottom", "Bottom")
        let coat = item("Coat", "Outerwear")
        let weather = WeatherSnapshot(location: .init(city: "Pune"), temperatureCelsius: 18, condition: .rain, description: "light rain", fetchedAt: .now)
        let results = OutfitRecommendationEngine().suggestions(items: [top, bottom, coat], preferences: .empty, wearEvents: [], context: .init(occasion: nil, preferredColors: [], weather: weather))
        XCTAssertEqual(results.first?.itemIDs, [top.id, bottom.id, coat.id])
        XCTAssertTrue(results.first?.explanation.contains("Weather context: light rain") == true)
    }

    func testMirrorCheckOffersOnlyVerifiedOwnedSameCategorySwaps() {
        let selectedTop = item("Blue shirt", "Top")
        let alternateTop = item("White shirt", "Top")
        let trousers = item("Trousers", "Bottom")
        let outfit = Outfit(id: UUID(), name: "Work", notes: nil, isFavorite: false, createdAt: .now, updatedAt: .now, itemIDs: [selectedTop.id, trousers.id])

        let assessment = MirrorFitCheckEngine().assess(
            outfit: outfit,
            items: [selectedTop, alternateTop, trousers],
            context: .init(occasion: "Work", weather: nil)
        )

        XCTAssertEqual(assessment.swaps.count, 1)
        XCTAssertEqual(assessment.swaps.first?.replacingItemID, selectedTop.id)
        XCTAssertEqual(assessment.swaps.first?.replacementItemID, alternateTop.id)
        XCTAssertTrue(assessment.contextComment.contains("Work"))
        XCTAssertFalse(assessment.clothingComment.localizedCaseInsensitiveContains("body"))
    }

    func testMirrorCheckAllowsNoSuitableSwap() {
        let dress = item("Dress", "Dress")
        let outfit = Outfit(id: UUID(), name: "Evening", notes: nil, isFavorite: false, createdAt: .now, updatedAt: .now, itemIDs: [dress.id])

        let assessment = MirrorFitCheckEngine().assess(outfit: outfit, items: [dress])

        XCTAssertTrue(assessment.swaps.isEmpty)
        XCTAssertTrue(assessment.clothingComment.contains("Dress"))
    }

    private func item(_ name: String, _ category: String, tags: [String] = [], color: String? = nil) -> GarmentItem {
        GarmentItem(id: UUID(), name: name, category: category, color: color, tags: tags, notes: nil, imagePath: nil, classification: nil, createdAt: .now, updatedAt: .now)
    }
}

private struct InvalidRanker: OutfitCandidateRanker {
    func rank(candidateIDs: [UUID], context: RecommendationContext) -> [UUID]? { [UUID()] }
}
