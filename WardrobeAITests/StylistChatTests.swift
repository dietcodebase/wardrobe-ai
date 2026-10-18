import XCTest
@testable import WardrobeAI

@MainActor
final class StylistChatTests: XCTestCase {
    func testOllamaConfigurationUsesGemma4AndNormalizesTheChatEndpoint() {
        let root = OllamaConfiguration(endpointText: "https://ollama.example.net")
        XCTAssertEqual(root.model, "gemma4:latest")
        XCTAssertEqual(root.chatURL?.absoluteString, "https://ollama.example.net/api/chat")
        XCTAssertEqual(root.tagsURL?.absoluteString, "https://ollama.example.net/api/tags")

        let api = OllamaConfiguration(endpointText: "https://ollama.example.net/api/")
        XCTAssertEqual(api.chatURL?.absoluteString, "https://ollama.example.net/api/chat")
        XCTAssertFalse(OllamaConfiguration(endpointText: "ollama.example.net").isConfigured)
    }

    func testOllamaClientPostsNonStreamingChatRequestAndReturnsContent() async throws {
        let configuration = OllamaConfiguration(endpointText: "https://ollama.example.net", model: "gemma4")
        let transport = StubOllamaTransport(
            data: Data(#"{"message":{"content":"Try the blue shirt."}}"#.utf8),
            response: HTTPURLResponse(url: URL(string: "https://ollama.example.net/api/chat")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
        let answer = try await OllamaClient(transport: transport).reply(to: "What should I wear?", configuration: configuration, wardrobeContext: "Owned garments: Blue shirt")

        XCTAssertEqual(answer, "Try the blue shirt.")
        XCTAssertEqual(transport.request?.url?.path, "/api/chat")
        let body = try XCTUnwrap(transport.request?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gemma4")
        XCTAssertEqual(json["stream"] as? Bool, false)
    }

    func testConnectionCheckRequiresTheConfiguredModel() async throws {
        let configuration = OllamaConfiguration(endpointText: "https://ollama.example.net", model: "gemma4:latest")
        let transport = StubOllamaTransport(
            data: Data(#"{"models":[{"name":"gemma4:latest","model":"gemma4:latest"}]}"#.utf8),
            response: HTTPURLResponse(url: URL(string: "https://ollama.example.net/api/tags")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
        let status = try await OllamaClient(transport: transport).verifyConnection(configuration: configuration)
        XCTAssertEqual(status, "Connected to Ollama • gemma4:latest is ready")
        XCTAssertEqual(transport.request?.url?.path, "/api/tags")
    }

    func testPhysicalDeviceCanReachOllamaWhenEndpointIsProvided() async throws {
        guard let endpoint = ProcessInfo.processInfo.environment["OLLAMA_TEST_ENDPOINT"], !endpoint.isEmpty else {
            throw XCTSkip("Set OLLAMA_TEST_ENDPOINT to run the LAN Ollama smoke test.")
        }
        let status = try await OllamaClient().verifyConnection(
            configuration: OllamaConfiguration(endpointText: endpoint, model: "gemma4:latest")
        )
        XCTAssertEqual(status, "Connected to Ollama • gemma4:latest is ready")
    }

    func testSearchRejectsEmptyArgumentsAndHonorsCallLimit() throws {
        let toolbox = StylistToolbox(store: try makeStore(), maximumCallCount: 1)
        XCTAssertThrowsError(try toolbox.execute(.init(tool: .searchWardrobe, query: "  "))) {
            XCTAssertEqual($0 as? StylistToolError, .invalidArguments("Enter what you want to find in your wardrobe."))
        }
        XCTAssertThrowsError(try toolbox.execute(.init(tool: .recentWear))) {
            XCTAssertEqual($0 as? StylistToolError, .callLimitReached)
        }
    }

    func testWearRequiresConfirmationAndUnknownIDDoesNotWrite() throws {
        let store = try makeStore()
        let toolbox = StylistToolbox(store: store)
        let unknown = UUID()
        XCTAssertThrowsError(try toolbox.execute(.init(tool: .wearToday, outfitID: unknown))) {
            XCTAssertEqual($0 as? StylistToolError, .writeRequiresConfirmation)
        }
        XCTAssertThrowsError(try toolbox.execute(.init(tool: .wearToday, outfitID: unknown), confirmedByUser: true)) {
            XCTAssertEqual($0 as? StylistToolError, .unknownOutfit)
        }
        XCTAssertTrue(store.wearEvents.isEmpty)
    }

    func testConfirmedWearIsIdempotent() throws {
        let store = try makeStore()
        let item = try store.repository.createItem(.init(name: "Blue shirt", category: "Top"))
        let outfit = try store.repository.createOutfit(.init(name: "Office", itemIDs: [item.id]))
        store.loadOutfitData()
        let toolbox = StylistToolbox(store: store, maximumCallCount: 3)
        _ = try toolbox.execute(.init(tool: .wearToday, outfitID: outfit.id), confirmedByUser: true)
        _ = try toolbox.execute(.init(tool: .wearToday, outfitID: outfit.id), confirmedByUser: true)
        XCTAssertEqual(try store.repository.wearEvents().count, 1)
    }

    func testNaturalLanguageSearchExtractsGarmentTermsAndRecommendationIntent() async throws {
        let store = try makeStore()
        _ = try store.repository.createItem(.init(name: "Blue shirt", category: "Top", color: "Blue"))
        let chat = StylistChat(store: store)
        chat.send("Find my blue shirt")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(chat.messages.last?.text.contains("Blue shirt") == true)

        chat.send("What should I wear?")
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertTrue(chat.messages.last?.text.contains("Try: Blue shirt") == true)
    }

    func testConfirmedWearStartsANewToolBudget() throws {
        let store = try makeStore()
        let item = try store.repository.createItem(.init(name: "Blue shirt", category: "Top"))
        let outfit = try store.repository.createOutfit(.init(name: "Office", itemIDs: [item.id]))
        store.loadOutfitData()
        let chat = StylistChat(store: store)
        chat.send("recent wear")
        chat.requestWear(for: outfit)
        chat.confirmWear()
        chat.requestWear(for: outfit)
        chat.confirmWear()
        XCTAssertEqual(try store.repository.wearEvents().count, 1)
        XCTAssertTrue(chat.messages.last?.text.contains("Recorded Office") == true)
    }

    func testContextExcludesExpiredPlans() throws {
        let store = try makeStore()
        let item = try store.repository.createItem(.init(name: "Blue shirt", category: "Top"))
        let outfit = try store.repository.createOutfit(.init(name: "Office", itemIDs: [item.id]))
        _ = try store.repository.createPlan(outfitID: outfit.id, scheduledFor: Date().addingTimeInterval(-86_400), occasion: "Past")
        _ = try store.repository.createPlan(outfitID: outfit.id, scheduledFor: Date().addingTimeInterval(86_400), occasion: "Future")
        store.loadOutfitData()
        let toolbox = StylistToolbox(store: store)
        guard case let .context(plans) = try toolbox.execute(.init(tool: .context)) else { return XCTFail("Expected plan context") }
        XCTAssertEqual(plans.map(\.occasion), ["Future"])
    }

    func testCancelledResponseCannotClearNewResponseState() async throws {
        let store = try makeStore()
        _ = try store.repository.createItem(.init(name: "Blue shirt", category: "Top"))
        let chat = StylistChat(store: store)
        chat.send("Find my blue shirt")
        chat.cancel()
        chat.send("Find my blue shirt")
        try await Task.sleep(for: .milliseconds(15))
        XCTAssertTrue(chat.isResponding)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertFalse(chat.isResponding)
        XCTAssertTrue(chat.messages.last?.text.contains("Blue shirt") == true)
    }

    private func makeStore() throws -> WardrobeStore {
        let database = try WardrobeDatabase.makeQueue(at: FileManager.default.temporaryDirectory.appending(path: "stylist-\(UUID().uuidString).sqlite"))
        return WardrobeStore(repository: WardrobeRepository(database: database))
    }
}

private final class StubOllamaTransport: OllamaTransport, @unchecked Sendable {
    let data: Data
    let response: URLResponse
    private(set) var request: URLRequest?

    init(data: Data, response: URLResponse) {
        self.data = data
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        return (data, response)
    }
}
