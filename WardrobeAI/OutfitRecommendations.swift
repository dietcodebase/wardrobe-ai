import Foundation

struct RecommendationContext: Equatable, Sendable {
    var occasion: String?
    var preferredColors: [String]

    static let everyday = RecommendationContext(occasion: nil, preferredColors: [])
}

struct OutfitSuggestion: Identifiable, Equatable, Sendable {
    let id: UUID
    let itemIDs: [UUID]
    let score: Int
    let explanation: String
}

protocol OutfitCandidateRanker {
    /// Returns only candidate IDs, in preferred order. Invalid IDs are ignored.
    func rank(candidateIDs: [UUID], context: RecommendationContext) -> [UUID]?
}

struct OutfitRecommendationEngine {
    private let ranker: OutfitCandidateRanker?
    private let maximumCandidates = 24

    init(ranker: OutfitCandidateRanker? = nil) {
        self.ranker = ranker
    }

    func suggestions(
        items: [GarmentItem],
        preferences: StylePreferences,
        wearEvents: [WearEvent],
        context: RecommendationContext = .everyday
    ) -> [OutfitSuggestion] {
        let byCategory = Dictionary(grouping: items, by: \.category)
        let recentIDs = Set(wearEvents.prefix(3).flatMap(\.itemIDs))
        var candidates: [[GarmentItem]] = []

        for onePiece in (byCategory["Dress"] ?? []) + (byCategory["One-piece outfit"] ?? []) {
            candidates.append(completing(primary: [onePiece], categories: byCategory))
        }
        for top in byCategory["Top"] ?? [] {
            for bottom in byCategory["Bottom"] ?? [] {
                candidates.append(completing(primary: [top, bottom], categories: byCategory))
            }
        }
        if candidates.isEmpty { candidates = items.map { [$0] } }

        let scored = candidates
            .map { candidate in makeSuggestion(candidate, preferences: preferences, recentIDs: recentIDs, context: context) }
            .sorted { $0.score == $1.score ? $0.explanation < $1.explanation : $0.score > $1.score }
        let bounded = Array(scored.prefix(maximumCandidates))
        guard let rankedIDs = ranker?.rank(candidateIDs: bounded.map(\.id), context: context) else { return bounded }

        let valid = Dictionary(uniqueKeysWithValues: bounded.map { ($0.id, $0) })
        var seen = Set<UUID>()
        let reranked = rankedIDs.compactMap { id -> OutfitSuggestion? in
            guard seen.insert(id).inserted else { return nil }
            return valid[id]
        }
        let missing = bounded.filter { !Set(reranked.map(\.id)).contains($0.id) }
        return reranked + missing
    }

    private func completing(primary: [GarmentItem], categories: [String: [GarmentItem]]) -> [GarmentItem] {
        var result = primary
        for category in ["Outerwear", "Shoes", "Accessory"] {
            if let item = categories[category]?.first { result.append(item) }
        }
        return result
    }

    private func makeSuggestion(_ items: [GarmentItem], preferences: StylePreferences, recentIDs: Set<UUID>, context: RecommendationContext) -> OutfitSuggestion {
        let ids = items.map(\.id)
        let occasion = context.occasion?.lowercased()
        let occasionMatches = occasion.map { requested in items.filter { $0.tags.contains { $0.caseInsensitiveCompare(requested) == .orderedSame } }.count } ?? 0
        let colorMatches = items.filter { item in
            guard let color = item.color?.lowercased() else { return false }
            return (context.preferredColors + preferences.preferredColors).contains { $0.lowercased() == color }
        }.count
        let preferredCategories = items.filter { preferences.preferredCategories.contains($0.category) }.count
        let recentPenalty = items.filter { recentIDs.contains($0.id) }.count
        let score = occasionMatches * 4 + colorMatches * 2 + preferredCategories - recentPenalty * 3
        let names = items.map(\.name).joined(separator: " with ")
        let explanation: String
        if occasionMatches > 0, let occasion { explanation = "Uses your \(occasion) pieces: \(names)." }
        else if recentPenalty == 0 { explanation = "A less-recently worn combination: \(names)." }
        else { explanation = "A simple combination from your wardrobe: \(names)." }
        return OutfitSuggestion(id: stableID(for: ids), itemIDs: ids, score: score, explanation: explanation)
    }

    private func stableID(for ids: [UUID]) -> UUID {
        var bytes = Array(repeating: UInt8(0), count: 16)
        for (index, byte) in ids.flatMap({ Array($0.uuidString.utf8) }).enumerated() { bytes[index % 16] ^= byte }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
