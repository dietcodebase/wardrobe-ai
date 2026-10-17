import XCTest
@testable import WardrobeAI

final class GarmentClassificationTests: XCTestCase {
    func testDecoderAcceptsOnlyBoundedKnownOutput() throws {
        let suggestion = try GarmentClassificationResponse.decode(#"{"category":"Top","color":" Navy ","tags":["work","WORK","smart"],"materialGuess":"linen"}"#)
        XCTAssertEqual(suggestion.category, "Top")
        XCTAssertEqual(suggestion.color, "Navy")
        XCTAssertEqual(suggestion.tags, ["work", "smart"])
        XCTAssertEqual(suggestion.materialGuess, "linen")
    }

    func testDecoderRejectsMalformedAndUnknownCategoryOutput() {
        XCTAssertThrowsError(try GarmentClassificationResponse.decode("not json")) { XCTAssertEqual($0 as? GarmentClassificationError, .malformedResponse) }
        XCTAssertThrowsError(try GarmentClassificationResponse.decode(#"{"category":"Hat"}"#)) { error in
            XCTAssertEqual(error as? GarmentClassificationError, .unknownCategory("Hat"))
        }
    }

    func testCoordinatorSurfacesUnavailableFallback() async {
        let coordinator = GarmentClassificationCoordinator()
        do {
            _ = try await coordinator.classify(imageData: Data([1]))
            XCTFail("Expected the unavailable classifier")
        } catch {
            XCTAssertEqual(error as? GarmentClassificationError, .unavailable)
        }
    }
}
