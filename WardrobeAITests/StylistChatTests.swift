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

    private func makeStore() throws -> WardrobeStore {
        let database = try WardrobeDatabase.makeQueue(at: FileManager.default.temporaryDirectory.appending(path: "stylist-\(UUID().uuidString).sqlite"))
        return WardrobeStore(repository: WardrobeRepository(database: database))
    }
}
