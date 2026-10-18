import Foundation
import XCTest
@testable import WardrobeAI

final class StorageTests: XCTestCase {
    func testRecommendationEventsRoundTripWithoutDiagnosticText() throws {
        let repository = try makeRepository()
        let garment = try repository.createItem(GarmentDraft(name: "Oxford shirt", category: "Top", tags: ["Work"]))
        let event = RecommendationEvent(
            id: UUID(), recommendationID: UUID(), candidateIDs: [garment.id],
            contextSnapshot: #"{"occasion":"Work","anchorItemID":null,"recentWearItemIDs":[]}"#,
            source: .localRules, outcome: .generated, occurredAt: .now
        )

        try repository.recordRecommendationEvent(event)
        let loaded = try XCTUnwrap(repository.recommendationEvents().first)
        XCTAssertEqual(loaded, event)
        XCTAssertFalse(loaded.contextSnapshot.localizedCaseInsensitiveContains("chain of thought"))
        XCTAssertNil(try repository.recommendationContext(recommendationID: UUID()))
    }

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

    func testAvailabilityAndExpandedStylePreferencesPersist() throws {
        let repository = try makeRepository()
        let item = try repository.createItem(GarmentDraft(name: "Raincoat", category: "Outerwear", availability: .repair))
        XCTAssertEqual(try repository.item(id: item.id)?.availability, .repair)

        let preferences = StylePreferences(preferredCategories: ["Shoes"], preferredColors: ["Black"], notes: "Comfort first", warmthPreference: .preferWarm, prefersRainTolerance: true, prefersWalkingComfort: true, preferredFormality: "Casual", footwearPreference: "sneaker", repeatFrequency: .repeatRecent)
        try repository.savePreferences(preferences)
        XCTAssertEqual(try repository.preferences(), preferences)
    }

    func testItemValidationCanonicalizesOptionalTextAndCaseDuplicateTags() throws {
        let repository = try makeRepository()
        let item = try repository.createItem(GarmentDraft(
            name: "Shirt", category: "Top", color: "  ", tags: ["Work", "work", "WORK"], notes: "  "
        ))

        XCTAssertNil(item.color)
        XCTAssertNil(item.notes)
        XCTAssertEqual(item.tags, ["Work"])
        XCTAssertThrowsError(try repository.createItem(GarmentDraft(name: "Hat", category: "Hat"))) {
            XCTAssertEqual($0 as? WardrobeRepositoryError, .invalidCategory)
        }
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

    func testClassificationProvenancePersistsManualCorrections() throws {
        let repository = try makeRepository()
        let suggestion = try GarmentClassificationSuggestion(category: "Top", color: "Blue", tags: ["work"], materialGuess: "linen")
        let provenance = ClassificationProvenance(modelID: "e2b", modelRevision: "test", route: "local", classifiedAt: .now, suggestion: suggestion, wasEditedBeforeSave: true)
        let item = try repository.createItem(GarmentDraft(name: "Oxford shirt", category: "Top", color: "Navy", tags: ["work"], classification: provenance))

        XCTAssertEqual(try repository.item(id: item.id)?.classification, provenance)
    }

    func testWearTodayIsIdempotentAndUndoRestoresUnderusedItems() throws {
        let repository = try makeRepository()
        let shirt = try repository.createItem(GarmentDraft(name: "Shirt", category: "Top"))
        let trousers = try repository.createItem(GarmentDraft(name: "Trousers", category: "Bottom"))
        let outfit = try repository.createOutfit(OutfitDraft(name: "Work", itemIDs: [shirt.id, trousers.id]))

        let first = try repository.wearToday(outfitID: outfit.id)
        let retry = try repository.wearToday(outfitID: outfit.id)
        XCTAssertEqual(first, retry)
        XCTAssertEqual(Set(first.itemIDs), Set([shirt.id, trousers.id]))
        XCTAssertEqual(try repository.underusedItems().map(\.wearCount), [1, 1])

        try repository.undoWear(eventID: first.id)
        XCTAssertTrue(try repository.wearEvents().isEmpty)
        XCTAssertEqual(try repository.underusedItems().map(\.wearCount), [0, 0])
    }

    func testWearLogsPreserveOutfitAndWearEventIntegrity() throws {
        let repository = try makeRepository()
        let top = try repository.createItem(GarmentDraft(name: "Top", category: "Top"))
        let bottom = try repository.createItem(GarmentDraft(name: "Bottom", category: "Bottom"))
        let outfit = try repository.createOutfit(OutfitDraft(name: "Set", itemIDs: [top.id]))

        XCTAssertThrowsError(try repository.logWear(itemID: bottom.id, outfitID: outfit.id)) {
            XCTAssertEqual($0 as? WardrobeRepositoryError, .itemNotInOutfit(itemID: bottom.id, outfitID: outfit.id))
        }

        let event = try repository.wearToday(outfitID: outfit.id)
        let eventLog = try XCTUnwrap(try repository.wearLogs(for: top.id).first)
        XCTAssertThrowsError(try repository.deleteWearLog(id: eventLog.id)) {
            XCTAssertEqual($0 as? WardrobeRepositoryError, .wearEventLogRequiresUndo(event.id))
        }
        XCTAssertEqual(try repository.wearEvents(), [event])
    }

    func testWearTodayUsesLocalDayBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let repository = try makeRepository(calendar: calendar)
        let item = try repository.createItem(GarmentDraft(name: "Dress", category: "Dress"))
        let outfit = try repository.createOutfit(OutfitDraft(name: "Friday", itemIDs: [item.id]))

        let late = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 59)))
        let nextDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 0, minute: 1)))
        XCTAssertNotEqual(try repository.wearToday(outfitID: outfit.id, wornAt: late).id, try repository.wearToday(outfitID: outfit.id, wornAt: nextDay).id)
        XCTAssertEqual(try repository.wearEvents().count, 2)
    }

    @MainActor
    func testSchedulingIsSeparateFromWearAndPersistsSourceEventReference() throws {
        let repository = try makeRepository()
        let item = try repository.createItem(GarmentDraft(name: "Jacket", category: "Outerwear"))
        let outfit = try repository.createOutfit(OutfitDraft(name: "Dinner", itemIDs: [item.id]))
        let store = WardrobeStore(repository: repository)

        try store.schedule(outfit, for: Date(timeIntervalSince1970: 1_800_000_000), occasion: "Evening", sourceEventID: "event-123")

        let plan = try XCTUnwrap(repository.plans().first)
        XCTAssertEqual(plan.outfitID, outfit.id)
        XCTAssertEqual(plan.occasion, "Evening")
        XCTAssertEqual(plan.sourceEventID, "event-123")
        XCTAssertTrue(try repository.wearEvents().isEmpty)
        try repository.deletePlan(id: plan.id)
        XCTAssertTrue(try repository.plans().isEmpty)
    }

    @MainActor
    func testRepeatedWearSuggestionReusesOutfitAndWearEvent() throws {
        let repository = try makeRepository()
        let top = try repository.createItem(GarmentDraft(name: "Top", category: "Top"))
        let bottom = try repository.createItem(GarmentDraft(name: "Bottom", category: "Bottom"))
        _ = try repository.createOutfit(OutfitDraft(name: "Saved in reverse order", itemIDs: [bottom.id, top.id]))
        let store = WardrobeStore(repository: repository)
        let suggestion = OutfitSuggestion(id: UUID(), itemIDs: [top.id, bottom.id], score: 0, explanation: "Owned items")

        XCTAssertEqual(try store.wearSuggestion(suggestion), try store.wearSuggestion(suggestion))
        XCTAssertEqual(try repository.allOutfits().count, 1)
        XCTAssertEqual(try repository.wearEvents().count, 1)
    }

    private func makeRepository(calendar: Calendar = .autoupdatingCurrent) throws -> WardrobeRepository {
        let queue = try WardrobeDatabase.makeInMemoryQueue()
        return WardrobeRepository(database: queue, now: { Date(timeIntervalSince1970: 1_700_000_000) }, calendar: calendar)
    }
}
