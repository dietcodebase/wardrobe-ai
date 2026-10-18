import XCTest
@testable import WardrobeAI

@MainActor
final class StylistChatTests: XCTestCase {
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

    func testOpenRouterPayloadPinsConfiguredModelAndBoundedOutput() throws {
        let payload = OpenRouterChatRequest(
            model: OpenRouterSettings.defaultModel,
            messages: [.init(role: "user", content: "Find a navy shirt")],
            maxTokens: 180,
            temperature: 0.4
        )
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "google/gemma-4-26b-a4b-it")
        XCTAssertEqual(json?["max_tokens"] as? Int, 180)
        XCTAssertEqual((json?["messages"] as? [[String: String]])?.first?["content"], "Find a navy shirt")
    }

    private func makeStore() throws -> WardrobeStore {
        let database = try WardrobeDatabase.makeQueue(at: FileManager.default.temporaryDirectory.appending(path: "stylist-\(UUID().uuidString).sqlite"))
        return WardrobeStore(repository: WardrobeRepository(database: database))
    }
}
