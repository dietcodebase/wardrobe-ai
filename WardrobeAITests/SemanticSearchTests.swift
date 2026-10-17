import XCTest
@testable import WardrobeAI

final class SemanticSearchTests: XCTestCase {
    func testSearchRanksCompatibleEmbeddings() async throws {
        let repository = try makeRepository()
        let blue = try repository.createItem(GarmentDraft(name: "Blue linen shirt", category: "Top"))
        let black = try repository.createItem(GarmentDraft(name: "Black boots", category: "Shoes"))
        try repository.saveEmbedding(GarmentEmbedding(itemID: blue.id, metadata: metadata, contentHash: "blue", vector: [1, 0, 0], indexedAt: .now))
        try repository.saveEmbedding(GarmentEmbedding(itemID: black.id, metadata: metadata, contentHash: "black", vector: [0, 1, 0], indexedAt: .now))

        let coordinator = SemanticSearchCoordinator(repository: repository, embedder: FakeEmbedder(metadata: metadata, query: [1, 0, 0]))
        let results = try await coordinator.search(query: "breathable blue", items: [blue, black])
        XCTAssertEqual(results.map(\.item.id), [blue.id, black.id])
        XCTAssertEqual(results.first?.score, 1, accuracy: 0.0001)
    }

    func testRejectsInvalidVectorsAndEditingInvalidatesEmbedding() throws {
        let repository = try makeRepository()
        let item = try repository.createItem(GarmentDraft(name: "Coat", category: "Outerwear"))
        XCTAssertThrowsError(try repository.saveEmbedding(GarmentEmbedding(itemID: item.id, metadata: metadata, contentHash: "bad", vector: [1, .infinity, 0], indexedAt: .now)))
        try repository.saveEmbedding(GarmentEmbedding(itemID: item.id, metadata: metadata, contentHash: "before", vector: [1, 0, 0], indexedAt: .now))
        var edited = item
        edited.name = "Overshirt"
        _ = try repository.updateItem(edited)
        XCTAssertTrue(try repository.embeddings(compatibleWith: metadata).isEmpty)
    }

    func testUnavailableEmbedderLeavesTextSearchFallbackUsable() async throws {
        let repository = try makeRepository()
        let item = try repository.createItem(GarmentDraft(name: "Linen shirt", category: "Top"))
        let coordinator = SemanticSearchCoordinator(repository: repository)
        do { _ = try await coordinator.search(query: "breathable", items: [item]); XCTFail("Expected unavailable search") }
        catch { XCTAssertEqual(error as? SemanticSearchError, .unavailable) }
        XCTAssertEqual(try repository.items(matching: "linen").map(\.id), [item.id])
    }

    private let metadata = EmbeddingMetadata(modelID: "test", modelRevision: "r1", dimension: 3, normalized: true, preprocessingVersion: "test-v1")
    private func makeRepository() throws -> WardrobeRepository { WardrobeRepository(database: try WardrobeDatabase.makeInMemoryQueue()) }
}

private struct FakeEmbedder: WardrobeEmbedding {
    let metadata: EmbeddingMetadata
    let query: [Float]
    func embedQuery(_ text: String) async throws -> [Float] { query }
    func embedItem(_ item: GarmentItem) async throws -> [Float] { query }
}
