import Foundation
import CryptoKit

protocol WardrobeEmbedding: Sendable {
    var metadata: EmbeddingMetadata { get }
    func embedQuery(_ text: String) async throws -> [Float]
    func embedItem(_ item: GarmentItem) async throws -> [Float]
}

/// The runtime adapter remains deliberately unavailable until the M01 embedding
/// protocol has device evidence. This avoids presenting stored feature prints or
/// unqualified vectors as text search.
struct UnavailableWardrobeEmbedding: WardrobeEmbedding {
    let metadata = EmbeddingMetadata.embeddingGemma2

    func embedQuery(_ text: String) async throws -> [Float] { throw SemanticSearchError.unavailable }
    func embedItem(_ item: GarmentItem) async throws -> [Float] { throw SemanticSearchError.unavailable }
}

struct SemanticSearchResult: Equatable, Sendable {
    let item: GarmentItem
    let score: Float
}

actor SemanticSearchCoordinator {
    private let repository: WardrobeRepository
    private let embedder: any WardrobeEmbedding

    init(repository: WardrobeRepository, embedder: any WardrobeEmbedding = UnavailableWardrobeEmbedding()) {
        self.repository = repository
        self.embedder = embedder
    }

    func reindex(_ items: [GarmentItem]) async throws {
        for item in items {
            try Task.checkCancellation()
            let vector = try await embedder.embedItem(item)
            let embedding = GarmentEmbedding(
                itemID: item.id, metadata: embedder.metadata, contentHash: contentHash(for: item),
                vector: vector, indexedAt: Date()
            )
            _ = try repository.saveEmbedding(embedding, for: item)
        }
    }

    func search(query: String, items: [GarmentItem], limit: Int = 5) async throws -> [SemanticSearchResult] {
        let vector = try await embedder.embedQuery(query)
        guard vectorIsCompatible(vector, metadata: embedder.metadata) else { throw SemanticSearchError.invalidVector }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return try repository.embeddings(compatibleWith: embedder.metadata)
            .compactMap { embedding in
                guard let item = byID[embedding.itemID],
                      contentHash(for: item) == embedding.contentHash else { return nil }
                return SemanticSearchResult(item: item, score: cosine(vector, embedding.vector))
            }
            .sorted { $0.score > $1.score }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private func contentHash(for item: GarmentItem) -> String {
        let text = [item.name, item.category, item.color ?? "", item.tags.joined(separator: ","), item.notes ?? ""].joined(separator: "|")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

func cosine(_ lhs: [Float], _ rhs: [Float]) -> Float {
    guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
    let dot = zip(lhs, rhs).reduce(Float.zero) { $0 + $1.0 * $1.1 }
    let lhsMagnitude = sqrt(lhs.reduce(Float.zero) { $0 + $1 * $1 })
    let rhsMagnitude = sqrt(rhs.reduce(Float.zero) { $0 + $1 * $1 })
    guard lhsMagnitude.isFinite, rhsMagnitude.isFinite, lhsMagnitude > 0, rhsMagnitude > 0 else { return 0 }
    return dot / (lhsMagnitude * rhsMagnitude)
}

private func vectorIsCompatible(_ vector: [Float], metadata: EmbeddingMetadata) -> Bool {
    guard vector.count == metadata.dimension, vector.allSatisfy(\.isFinite) else { return false }
    return vector.contains { $0 != 0 }
}
