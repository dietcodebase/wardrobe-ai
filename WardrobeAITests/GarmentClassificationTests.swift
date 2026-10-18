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
        let coordinator = GarmentClassificationCoordinator(classifier: UnavailableGarmentClassifier())
        do {
            _ = try await coordinator.classify(imageData: Data([1]))
            XCTFail("Expected the unavailable classifier")
        } catch {
            XCTAssertEqual(error as? GarmentClassificationError, .unavailable)
        }
    }

    func testVisionMappingKeepsOnlyKnownGarmentCategories() throws {
        let suggestion = try VisionClassificationMapping.suggestion(for: ["clothing", "button_down_shirt", "fashion"])
        XCTAssertEqual(suggestion.category, "Top")
        XCTAssertEqual(suggestion.tags, ["clothing", "button down shirt", "fashion"])
        XCTAssertThrowsError(try VisionClassificationMapping.suggestion(for: ["dog", "furniture"])) { error in
            XCTAssertEqual(error as? GarmentClassificationError, .unavailable)
        }
    }

    func testOpenRouterTaggingRequestUsesAnImageMessageAndBoundedOutput() throws {
        let payload = OpenRouterGarmentClassifier.request(for: Data([1, 2, 3]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, OpenRouterSettings.model)
        XCTAssertEqual(json["max_tokens"] as? Int, 180)
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages.last?["content"] as? [[String: String]])
        XCTAssertEqual(parts.compactMap { $0["type"] }, ["text", "image_url"])
        XCTAssertEqual(parts.last?["image_url"], "data:image/jpeg;base64,AQID")
    }

    func testOpenRouterJSONExtractionSupportsMarkdownFences() throws {
        let response = """
        ```json
        {"category":"Top","tags":["casual"]}
        ```
        """
        let suggestion = try GarmentClassificationResponse.decode(OpenRouterGarmentClassifier.jsonObject(in: response))
        XCTAssertEqual(suggestion.category, "Top")
        XCTAssertEqual(suggestion.tags, ["casual"])
    }

    func testOpenRouterLiveTaggingWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_OPENROUTER_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set RUN_OPENROUTER_LIVE_TEST=1 to run the billable OpenRouter integration check.")
        }
        guard OpenRouterSettings.apiKey() != nil else {
            XCTFail("The saved OpenRouter API key is unavailable to the app test host.")
            return
        }
        guard let imageURL = Bundle.main.url(forResource: "navy-oxford", withExtension: "png", subdirectory: "SeedAssets") else {
            XCTFail("Missing bundled wardrobe fixture.")
            return
        }

        let previousEnabled = UserDefaults.standard.object(forKey: OpenRouterSettings.enabledKey)
        UserDefaults.standard.set(true, forKey: OpenRouterSettings.enabledKey)
        defer {
            if let previousEnabled { UserDefaults.standard.set(previousEnabled, forKey: OpenRouterSettings.enabledKey) }
            else { UserDefaults.standard.removeObject(forKey: OpenRouterSettings.enabledKey) }
        }

        let result = try await OpenRouterGarmentClassifier().classify(imageData: try Data(contentsOf: imageURL))
        XCTAssertEqual(result.route, "cloud-openrouter-fallback")
        XCTAssertTrue(GarmentTaxonomy.isKnownCategory(result.suggestion.category))
        XCTAssertFalse(result.suggestion.tags.isEmpty)
    }
}
