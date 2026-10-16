import XCTest
@testable import WardrobeAI

final class AppTabTests: XCTestCase {
    func testNavigationHasStableDistinctDestinations() {
        XCTAssertEqual(AppTab.allCases.map(\.rawValue), ["Wardrobe", "Outfits", "Stylist"])
        XCTAssertEqual(Set(AppTab.allCases.map(\.id)).count, 3)
        XCTAssertTrue(AppTab.allCases.allSatisfy { !$0.message.isEmpty && !$0.symbol.isEmpty })
    }
}
