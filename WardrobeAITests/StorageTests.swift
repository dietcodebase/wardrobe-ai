import Foundation
import XCTest
@testable import WardrobeAI

final class StorageTests: XCTestCase {
    func testItemCRUDTagFilterAndPreferencesRoundTrip() throws {
        let repository = try makeRepository()
        let item = try repository.createItem(GarmentDraft(
            name: "  Linen shirt ", category: " Top ", color: "Cream",
            tags: ["casual", "casual", "weekend"], notes: "  breathable  "
        ))

        XCTAssertEqual(item.name, "Linen shirt")
        XCTAssertEqual(item.tags, ["casual", "weekend"])
        XCTAssertEqual(try repository.items(tag: "casual").map(\.id), [item.id])
        XCTAssertTrue(try repository.items(tag: "casual' OR 1 = 1 --").isEmpty)
        XCTAssertEqual(try repository.allItems().count, 1)

        var edited = item
        edited.name = "Linen overshirt"
        let updated = try repository.updateItem(edited)
        XCTAssertEqual(try repository.item(id: item.id), updated)

        let preferences = StylePreferences(preferredCategories: ["Top"], preferredColors: ["Cream"], notes: "Relaxed")
        try repository.savePreferences(preferences)
        XCTAssertEqual(try repository.preferences(), preferences)
    }

    func testDeletionRespectsOutfitAndWearReferences() throws {
        let repository = try makeRepository()
        let item = try repository.createItem(GarmentDraft(name: "Trousers", category: "Bottom"))
        let outfit = try repository.createOutfit(OutfitDraft(name: "Work", itemIDs: [item.id]))

        XCTAssertThrowsError(try repository.deleteItem(id: item.id)) { error in
            XCTAssertEqual(error as? WardrobeRepositoryError, .itemIsReferenced(item.id))
        }

        try repository.deleteOutfit(id: outfit.id)
        let log = try repository.logWear(itemID: item.id)
        XCTAssertThrowsError(try repository.deleteItem(id: item.id))
        try repository.deleteWearLog(id: log.id)
        try repository.deleteItem(id: item.id)
        XCTAssertNil(try repository.item(id: item.id))
    }

    func testSeedImportIsIdempotent() throws {
        let repository = try makeRepository()
        let firstImport = try WardrobeSeed.install(in: repository)
        let secondImport = try WardrobeSeed.install(in: repository)

        XCTAssertEqual(firstImport.map(\.id), secondImport.map(\.id))
        XCTAssertEqual(try repository.allItems().count, WardrobeSeed.entries.count)
    }

    func testFileDatabaseMigratesAndPersistsRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseURL = directory.appending(path: "wardrobe.sqlite")

        let firstRepository = WardrobeRepository(database: try WardrobeDatabase.makeQueue(at: databaseURL))
        let item = try firstRepository.createItem(GarmentDraft(name: "Coat", category: "Outerwear"))

        let reopenedRepository = WardrobeRepository(database: try WardrobeDatabase.makeQueue(at: databaseURL))
        XCTAssertEqual(try reopenedRepository.item(id: item.id)?.name, "Coat")
    }

    func testImageWriteRollbackAndOrphanRecovery() throws {
        let repository = try makeRepository()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageStore = WardrobeImageStore(rootURL: directory)
        let coordinator = GarmentImageCoordinator(repository: repository, imageStore: imageStore)

        XCTAssertThrowsError(try coordinator.createItem(GarmentDraft(name: "", category: "Top"), imageData: Data([1, 2, 3])))
        XCTAssertEqual(try coordinator.recoverOrphanedImages(), [])

        let item = try coordinator.createItem(GarmentDraft(name: "Jacket", category: "Outerwear"), imageData: Data([4, 5]))
        XCTAssertEqual(try imageStore.data(at: try XCTUnwrap(item.imagePath)), Data([4, 5]))
        let replaced = try coordinator.replaceImage(for: item.id, with: Data([6, 7]))
        XCTAssertNil(try imageStore.data(at: try XCTUnwrap(item.imagePath)))
        XCTAssertEqual(try imageStore.data(at: try XCTUnwrap(replaced.imagePath)), Data([6, 7]))
        let orphan = try imageStore.store(Data([9]))
        XCTAssertEqual(try coordinator.recoverOrphanedImages(), [orphan])
        XCTAssertNil(try imageStore.data(at: orphan))
    }

    func testSearchCombinesTextCategoryAndTagFilters() throws {
        let repository = try makeRepository()
        let shirt = try repository.createItem(GarmentDraft(name: "Navy Oxford", category: "Top", color: "Navy", tags: ["smart", "work"], notes: "Button-down"))
        _ = try repository.createItem(GarmentDraft(name: "Navy trousers", category: "Bottom", color: "Navy", tags: ["work"]))

        XCTAssertEqual(try repository.items(matching: "button", category: "Top").map(\.id), [shirt.id])
        XCTAssertEqual(try repository.items(matching: "navy", tag: "smart").map(\.id), [shirt.id])
        XCTAssertTrue(try repository.items(matching: "navy", category: "Shoes").isEmpty)
    }

    private func makeRepository() throws -> WardrobeRepository {
        let queue = try WardrobeDatabase.makeInMemoryQueue()
        return WardrobeRepository(database: queue, now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }
}
