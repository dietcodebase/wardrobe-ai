import Foundation
import XCTest
@testable import WardrobeAI

final class GarmentClassificationTests: XCTestCase {
    func testDecoderAcceptsOnlyBoundedKnownOutput() throws {
        let suggestion = try GarmentClassificationResponse.decode(#"{"category":"Top","suggestedName":" Navy Oxford Shirt ","color":" Navy ","tags":["work","WORK","smart"],"materialGuess":"linen","garmentType":"Oxford shirt","pattern":"solid","fit":"regular","formality":"smart casual","seasons":["spring","autumn"],"occasions":["work","travel"],"colorFamily":"blue","secondaryColors":["white"],"silhouette":"straight","texture":"woven","layering":"mid layer","warmth":"light","styleKeywords":["classic","preppy"],"pairingNotes":["works with denim"]}"#)
        XCTAssertEqual(suggestion.category, "Top")
        XCTAssertEqual(suggestion.suggestedName, "Navy Oxford Shirt")
        XCTAssertEqual(suggestion.color, "Navy")
        XCTAssertEqual(suggestion.tags, ["work", "smart"])
        XCTAssertEqual(suggestion.materialGuess, "linen")
        XCTAssertEqual(suggestion.garmentType, "Oxford shirt")
        XCTAssertEqual(suggestion.pattern, "solid")
        XCTAssertEqual(suggestion.fit, "regular")
        XCTAssertEqual(suggestion.formality, "smart casual")
        XCTAssertEqual(suggestion.seasons, ["spring", "autumn"])
        XCTAssertEqual(suggestion.occasions, ["work", "travel"])
        XCTAssertEqual(suggestion.colorFamily, "blue")
        XCTAssertEqual(suggestion.secondaryColors, ["white"])
        XCTAssertEqual(suggestion.silhouette, "straight")
        XCTAssertEqual(suggestion.texture, "woven")
        XCTAssertEqual(suggestion.layering, "mid layer")
        XCTAssertEqual(suggestion.warmth, "light")
        XCTAssertEqual(suggestion.styleKeywords, ["classic", "preppy"])
        XCTAssertEqual(suggestion.pairingNotes, ["works with denim"])
    }

    func testDecoderRejectsMalformedAndUnknownCategoryOutput() {
        XCTAssertThrowsError(try GarmentClassificationResponse.decode("not json")) { XCTAssertEqual($0 as? GarmentClassificationError, .malformedResponse) }
        XCTAssertThrowsError(try GarmentClassificationResponse.decode(#"{"category":"Hat"}"#)) { error in
            XCTAssertEqual(error as? GarmentClassificationError, .unknownCategory("Hat"))
        }
    }

    func testDecoderRecoversFencedGemmaOutputAndNormalizesCategory() throws {
        let suggestion = try GarmentClassificationResponse.decode("""
        Here is the visual read:
        ```json
        {"category":"shirt","suggestedName":"Cream tee","tags":["casual","everyday","cotton","extra","fifth","sixth","seventh","eighth","ignored"],"pattern":"solid"}
        ```
        """)
        XCTAssertEqual(suggestion.category, "Top")
        XCTAssertEqual(suggestion.suggestedName, "Cream tee")
        XCTAssertEqual(suggestion.tags.count, 8)
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

    func testOllamaVisionRequestUsesJSONAndDisablesThinking() async throws {
        let transport = CapturingVisionTransport(response: #"{"message":{"content":"{\\\"category\\\":\\\"Top\\\",\\\"suggestedName\\\":\\\"Navy Oxford Shirt\\\",\\\"color\\\":\\\"Navy\\\",\\\"tags\\\":[\\\"work\\\"],\\\"garmentType\\\":\\\"Oxford shirt\\\",\\\"pattern\\\":\\\"solid\\\",\\\"fit\\\":\\\"regular\\\",\\\"formality\\\":\\\"smart casual\\\",\\\"seasons\\\":[\\\"spring\\\"],\\\"occasions\\\":[\\\"work\\\"]}"}}"#)
        let classifier = OllamaGarmentClassifier(
            configuration: OllamaConfiguration(endpointText: "http://192.168.1.20:11434"),
            transport: transport
        )

        let provenance = try await classifier.classify(imageData: Data([1, 2, 3]))
        let capturedRequest = await transport.request()
        let request = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.20:11434/api/chat")
        XCTAssertEqual(object["format"] as? String, "json")
        XCTAssertEqual(object["think"] as? Bool, false)
        XCTAssertEqual((object["messages"] as? [[String: Any]])?[1]["images"] as? [String], ["AQID"])
        XCTAssertEqual(provenance.suggestion.garmentType, "Oxford shirt")
        XCTAssertEqual(provenance.suggestion.suggestedName, "Navy Oxford Shirt")
        XCTAssertEqual(provenance.route, "remote-ollama-vision")
    }
}

private actor CapturingVisionTransport: OllamaTransport {
    private let response: Data
    private var capturedRequest: URLRequest?

    init(response: String) {
        self.response = Data(response.utf8)
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequest = request
        return (response, HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func request() -> URLRequest? {
        capturedRequest
    }
}
