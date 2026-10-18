import Foundation

struct RecommendationContext: Equatable, Sendable {
    var occasion: String?
    var preferredColors: [String]
    var anchorItemID: UUID? = nil
    var weather: WeatherSnapshot? = nil

    static let everyday = RecommendationContext(occasion: nil, preferredColors: [], anchorItemID: nil, weather: nil)
}

struct OutfitSuggestion: Identifiable, Equatable, Sendable {
    let id: UUID
    let itemIDs: [UUID]
    let score: Int
    let explanation: String
}

/// A bounded, local result for the still-photo mirror flow. The app deliberately
/// comments on the selected clothing and context, never on a person's body.
struct MirrorFitContext: Equatable, Sendable {
    var occasion: String?
    var weather: WeatherSnapshot?

    static let none = MirrorFitContext(occasion: nil, weather: nil)
}

struct OwnedItemSwap: Identifiable, Equatable, Sendable {
    let replacingItemID: UUID
    let replacementItemID: UUID
    let reason: String

    var id: UUID {
        var bytes = Array(repeating: UInt8(0), count: 16)
        for (index, byte) in (replacingItemID.uuidString + replacementItemID.uuidString).utf8.enumerated() {
            bytes[index % 16] ^= byte
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

struct MirrorFitAssessment: Equatable, Sendable {
    let clothingComment: String
    let contextComment: String
    let swaps: [OwnedItemSwap]
}

struct MirrorFitCheckEngine {
    func assess(
        outfit: Outfit,
        items: [GarmentItem],
        observedCategory: String?,
        context: MirrorFitContext = .none
    ) -> MirrorFitAssessment {
        let owned = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let selected = outfit.itemIDs.compactMap { owned[$0] }
        let names = selected.map(\.name).joined(separator: ", ")
        let clothingComment: String
        guard let observedCategory, GarmentTaxonomy.isKnownCategory(observedCategory) else {
            clothingComment = "I couldn’t identify a clothing category in this photo. Check the saved outfit manually or try a clearer still photo."
            var contextParts: [String] = []
            if let occasion = context.occasion?.trimmingCharacters(in: .whitespacesAndNewlines), !occasion.isEmpty {
                contextParts.append("Context: \(occasion).")
            }
            if contextParts.isEmpty { contextParts.append("The photo could not be matched to an owned garment.") }
            return MirrorFitAssessment(clothingComment: clothingComment, contextComment: contextParts.joined(separator: " "), swaps: [])
        }
        if names.isEmpty {
            clothingComment = "This saved outfit no longer has available garments. Choose another outfit before checking a photo."
        } else if selected.contains(where: { $0.category == observedCategory }) {
            clothingComment = "The photo suggests a \(observedCategory.lowercased()), which is included in \(outfit.name). Review how the saved layers work together for your plans."
        } else {
            clothingComment = "The photo suggests a \(observedCategory.lowercased()), while \(outfit.name) contains \(names). Check whether that photographed piece belongs with this saved outfit."
        }

        var contextParts: [String] = []
        if let occasion = context.occasion?.trimmingCharacters(in: .whitespacesAndNewlines), !occasion.isEmpty {
            contextParts.append("Context: \(occasion).")
        }
        if let weather = context.weather {
            contextParts.append("Weather context: \(weather.description), \(Int(weather.temperatureCelsius.rounded()))°C in \(weather.location.normalizedCity).")
        }
        if contextParts.isEmpty {
            contextParts.append("Add an occasion or optional weather context for a more specific clothing check.")
        }

        let selectedIDs = Set(outfit.itemIDs)
        let selectedObservedCategory = selected.first { $0.category == observedCategory }
        let swapSource = selectedObservedCategory.map { [$0] } ?? []
        let swaps = swapSource.compactMap { current -> OwnedItemSwap? in
            let replacement = items
                .filter { $0.category == observedCategory && $0.id != current.id && !selectedIDs.contains($0.id) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .first
            guard let replacement else { return nil }
            return OwnedItemSwap(
                replacingItemID: current.id,
                replacementItemID: replacement.id,
                reason: "The photo suggests a \(observedCategory.lowercased()); this is an available owned option."
            )
        }
        return MirrorFitAssessment(clothingComment: clothingComment, contextComment: contextParts.joined(separator: " "), swaps: swaps)
    }
}

protocol OutfitCandidateRanker {
    /// Returns only candidate IDs, in preferred order. Invalid IDs are ignored.
    func rank(candidateIDs: [UUID], context: RecommendationContext) -> [UUID]?
}

struct OutfitRecommendationEngine {
    private let ranker: OutfitCandidateRanker?
    private let maximumCandidates = 24
    private let maximumCandidateEvaluations = 240

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
        var bounded: [OutfitSuggestion] = []
        var evaluations = 0
        func consider(_ candidate: [GarmentItem]) {
            guard evaluations < maximumCandidateEvaluations else { return }
            evaluations += 1
            guard !candidate.isEmpty, Set(candidate.map(\.id)).count == candidate.count else { return }
            if let anchorID = context.anchorItemID, !candidate.contains(where: { $0.id == anchorID }) { return }
            let suggestion = makeSuggestion(candidate, preferences: preferences, recentIDs: recentIDs, context: context)
            bounded.append(suggestion)
            bounded.sort { $0.score == $1.score ? $0.explanation < $1.explanation : $0.score > $1.score }
            if bounded.count > maximumCandidates { bounded.removeLast() }
        }

        generation: do {
            let dresses = (byCategory["Dress"] ?? []) + (byCategory["One-piece outfit"] ?? [])
            for onePiece in dresses {
                consider([onePiece])
                if evaluations >= maximumCandidateEvaluations { break generation }
                for category in ["Outerwear", "Shoes", "Accessory"] {
                    for optional in byCategory[category] ?? [] {
                        consider([onePiece, optional])
                        if evaluations >= maximumCandidateEvaluations { break generation }
                    }
                }
            }
            for top in byCategory["Top"] ?? [] {
                for bottom in byCategory["Bottom"] ?? [] {
                    consider([top, bottom])
                    if evaluations >= maximumCandidateEvaluations { break generation }
                    for category in ["Outerwear", "Shoes", "Accessory"] {
                        for optional in byCategory[category] ?? [] {
                            consider([top, bottom, optional])
                            if evaluations >= maximumCandidateEvaluations { break generation }
                        }
                    }
                }
            }
        }
        if bounded.isEmpty {
            for item in items { consider([item]) }
        }
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
        let weatherScore = weatherAdjustment(for: items, weather: context.weather)
        let practicality = practicalityAdjustment(for: items)
        let score = occasionMatches * 4 + colorMatches * 2 + preferredCategories + weatherScore + practicality.score - recentPenalty * 3
        let names = items.map(\.name).joined(separator: " with ")
        let explanation: String
        var reasons: [String] = []
        if occasionMatches > 0, let occasion { reasons.append("fits your \(occasion) plan") }
        if practicality.score > 0 { reasons.append(practicality.note) }
        if recentPenalty == 0 { reasons.append("gives recently worn pieces a break") }
        explanation = "\((reasons.first ?? "a simple combination from your wardrobe").capitalized) with \(names)."
        let weatherNote = context.weather.map { " Weather context: \($0.description), \(Int($0.temperatureCelsius.rounded()))°C in \($0.location.normalizedCity)." } ?? ""
        return OutfitSuggestion(id: stableID(for: ids), itemIDs: ids, score: score, explanation: explanation + weatherNote)
    }

    private func practicalityAdjustment(for items: [GarmentItem]) -> (score: Int, note: String) {
        let categories = Set(items.map(\.category))
        var score = 0
        var notes: [String] = []
        if categories.contains("Dress") || categories.contains("One-piece outfit") {
            score += 3
            notes.append("keeps the base simple")
        } else if categories.contains("Top") && categories.contains("Bottom") {
            score += 3
            notes.append("balances a clear base")
        }
        if categories.contains("Shoes") {
            score += 2
            notes.append("finishes the look with footwear")
        }
        if categories.contains("Outerwear") && !(categories.contains("Top") || categories.contains("Dress") || categories.contains("One-piece outfit")) {
            score -= 2
        }
        if items.count > 4 { score -= 1 }
        return (score, notes.first ?? "keeps the pieces easy to wear")
    }

    private func weatherAdjustment(for items: [GarmentItem], weather: WeatherSnapshot?) -> Int {
        guard let weather else { return 0 }
        let categories = items.map(\.category)
        var adjustment = 0
        if weather.temperatureCelsius < 15, categories.contains("Outerwear") { adjustment += 2 }
        if weather.temperatureCelsius > 24, categories.contains("Outerwear") { adjustment -= 2 }
        if weather.condition == .rain || weather.condition == .thunderstorm, categories.contains("Outerwear") { adjustment += 2 }
        return adjustment
    }

    private func stableID(for ids: [UUID]) -> UUID {
        var bytes = Array(repeating: UInt8(0), count: 16)
        for (index, byte) in ids.flatMap({ Array($0.uuidString.utf8) }).enumerated() { bytes[index % 16] ^= byte }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
