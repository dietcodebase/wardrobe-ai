import Foundation

struct RecommendationContext: Equatable, Sendable {
    var occasion: String?
    var preferredColors: [String]
    var preferredCategories: [String] = []
    var anchorItemID: UUID? = nil
    var weather: WeatherSnapshot? = nil
    var weatherFreshness: WeatherFreshness? = nil

    static let everyday = RecommendationContext(occasion: nil, preferredColors: [], preferredCategories: [], anchorItemID: nil, weather: nil, weatherFreshness: nil)
}

struct RecommendationFactor: Equatable, Sendable, Identifiable {
    let name: String
    let value: Int
    let reason: String
    var id: String { name }
}

enum RecommendationOutcome: String, Codable, Sendable {
    case generated, viewed, saved, worn, skipped, failedToGenerate
}

enum RecommendationSource: String, Codable, Sendable {
    case localRules, ollamaRanking, cachedWeather, noContext
}

struct RecommendationEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let recommendationID: UUID
    let candidateIDs: [UUID]
    let contextSnapshot: String
    let source: RecommendationSource
    let outcome: RecommendationOutcome
    let occurredAt: Date
}

struct OutfitSuggestion: Identifiable, Equatable, Sendable {
    let id: UUID
    let itemIDs: [UUID]
    let score: Int
    let explanation: String
    let factors: [RecommendationFactor]
    let recommendationID: UUID?
    let source: RecommendationSource

    init(id: UUID, itemIDs: [UUID], score: Int, explanation: String, factors: [RecommendationFactor] = [], recommendationID: UUID? = nil, source: RecommendationSource = .localRules) {
        self.id = id
        self.itemIDs = itemIDs
        self.score = score
        self.explanation = explanation
        self.factors = factors
        self.recommendationID = recommendationID
        self.source = source
    }
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
        let recommendationID = UUID()
        var bounded: [OutfitSuggestion] = []
        var evaluations = 0
        func consider(_ candidate: [GarmentItem]) {
            guard evaluations < maximumCandidateEvaluations else { return }
            evaluations += 1
            guard !candidate.isEmpty, Set(candidate.map(\.id)).count == candidate.count else { return }
            if let anchorID = context.anchorItemID, !candidate.contains(where: { $0.id == anchorID }) { return }
            let suggestion = makeSuggestion(candidate, preferences: preferences, recentIDs: recentIDs, context: context, recommendationID: recommendationID)
            bounded.append(suggestion)
            bounded.sort { $0.score == $1.score ? $0.explanation < $1.explanation : $0.score > $1.score }
            if bounded.count > maximumCandidates { bounded.removeLast() }
        }

        var candidateSets: [[[GarmentItem]]] = []
        let dresses = (byCategory["Dress"] ?? []) + (byCategory["One-piece outfit"] ?? [])
        for onePiece in dresses {
            candidateSets.append(layeredCandidates(base: [onePiece], byCategory: byCategory, anchorItemID: context.anchorItemID))
        }
        for top in byCategory["Top"] ?? [] {
            for bottom in byCategory["Bottom"] ?? [] {
                candidateSets.append(layeredCandidates(base: [top, bottom], byCategory: byCategory, anchorItemID: context.anchorItemID))
            }
        }
        // Evaluate one variation from every base outfit before adding the next
        // layer variation. A nested loop used to spend the entire budget on the
        // first dress or top/bottom pair in a large wardrobe.
        var variation = 0
        while evaluations < maximumCandidateEvaluations {
            var consideredAny = false
            for candidates in candidateSets where variation < candidates.count {
                consider(candidates[variation])
                consideredAny = true
                if evaluations >= maximumCandidateEvaluations { break }
            }
            guard consideredAny else { break }
            variation += 1
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

    /// Generates complete, owned-item outfits while retaining a hard evaluation bound.
    /// An outer layer, footwear and one accessory may coexist; the previous loop
    /// considered each optional category independently and never produced that set.
    private func layeredCandidates(
        base: [GarmentItem],
        byCategory: [String: [GarmentItem]],
        anchorItemID: UUID?
    ) -> [[GarmentItem]] {
        let outerwear = candidateOptions(byCategory["Outerwear"] ?? [], limit: 6, anchorItemID: anchorItemID)
        let shoes = candidateOptions(byCategory["Shoes"] ?? [], limit: 6, anchorItemID: anchorItemID)
        let accessories = candidateOptions(byCategory["Accessory"] ?? [], limit: 4, anchorItemID: anchorItemID)
        let layers: [GarmentItem?] = [nil] + outerwear
        let footwear: [GarmentItem?] = [nil] + shoes
        let accents: [GarmentItem?] = [nil] + accessories

        var candidates = [base]
        // Ensure a complete option is evaluated early. With a large wardrobe,
        // the bounded search otherwise spends its budget on bare base outfits.
        if let layer = layers.dropFirst().first, let shoe = footwear.dropFirst().first, let accent = accents.dropFirst().first {
            candidates.append(base + [layer, shoe, accent].compactMap { $0 })
        }
        candidates += shoes.map { base + [$0] }
        candidates += outerwear.map { base + [$0] }
        candidates += accessories.map { base + [$0] }
        for layer in layers.dropFirst() {
            for shoe in footwear.dropFirst() {
                candidates.append(base + [layer, shoe].compactMap { $0 })
            }
        }
        for accent in accents.dropFirst() {
            for layer in layers {
                for shoe in footwear {
                    candidates.append(base + [layer, shoe, accent].compactMap { $0 })
                }
            }
        }
        return candidates
    }

    /// Retain the requested piece even when it falls beyond the bounded optional
    /// category sample. This keeps “what goes with this?” literal and reliable.
    private func candidateOptions(_ items: [GarmentItem], limit: Int, anchorItemID: UUID?) -> [GarmentItem] {
        guard let anchorItemID, let anchor = items.first(where: { $0.id == anchorItemID }) else {
            return Array(items.prefix(limit))
        }
        return [anchor] + Array(items.filter { $0.id != anchor.id }.prefix(max(0, limit - 1)))
    }

    private func makeSuggestion(_ items: [GarmentItem], preferences: StylePreferences, recentIDs: Set<UUID>, context: RecommendationContext, recommendationID: UUID) -> OutfitSuggestion {
        let ids = items.map(\.id)
        let occasion = context.occasion?.lowercased()
        let occasionMatches = occasion.map { requested in items.filter { matchesOccasion($0, requested: requested) }.count } ?? 0
        let occasionConflicts = occasion.map { requested in
            items.filter { hasOccasionSignal($0) && !matchesOccasion($0, requested: requested) }.count
        } ?? 0
        let colorMatches = items.filter { item in
            guard let color = item.color?.lowercased() else { return false }
            return (context.preferredColors + preferences.preferredColors).contains { $0.lowercased() == color }
        }.count
        let preferredCategories = items.filter { preferences.preferredCategories.contains($0.category) }.count
        let recentPenalty = items.filter { recentIDs.contains($0.id) }.count
        let weatherScore = weatherAdjustment(for: items, weather: context.weather)
        let practicality = practicalityAdjustment(for: items)
        let formality = formalityAdjustment(for: items)
        let score = occasionMatches * 4 - occasionConflicts * 3 + colorMatches * 2 + preferredCategories + weatherScore + practicality.score + formality.score - recentPenalty * 3
        var factors: [RecommendationFactor] = []
        if let occasion = context.occasion {
            factors.append(RecommendationFactor(name: "occasion", value: occasionMatches * 4 - occasionConflicts * 3, reason: "Compared item tags and classification metadata with the selected occasion: \(occasion)."))
        }
        if colorMatches > 0 { factors.append(RecommendationFactor(name: "preferredColors", value: colorMatches * 2, reason: "Matched \(colorMatches) item color(s) to saved or selected color preferences.")) }
        if preferredCategories > 0 { factors.append(RecommendationFactor(name: "preferredCategories", value: preferredCategories, reason: "Matched \(preferredCategories) item(s) to saved category preferences.")) }
        if context.anchorItemID != nil { factors.append(RecommendationFactor(name: "anchor", value: 0, reason: "Includes the garment you selected as the starting piece.")) }
        if context.weather != nil { factors.append(RecommendationFactor(name: "weather", value: weatherScore, reason: "Adjusted for the supplied weather snapshot and its garment layers.")) }
        factors.append(RecommendationFactor(name: "recentWear", value: -recentPenalty * 3, reason: recentPenalty == 0 ? "No candidate items appear in the three most recent wear events." : "Reduced score for \(recentPenalty) item(s) in the three most recent wear events."))
        factors.append(RecommendationFactor(name: "completeness", value: practicality.score, reason: practicality.note + "."))
        if formality.score != 0 { factors.append(RecommendationFactor(name: "formality", value: formality.score, reason: formality.note + ".")) }
        let names = items.map(\.name).joined(separator: " with ")
        let explanation: String
        var reasons: [String] = []
        if occasionMatches > 0, let occasion { reasons.append("has \(occasionMatches) piece\(occasionMatches == 1 ? "" : "s") suited to \(occasion)") }
        if formality.score > 0 { reasons.append(formality.note) }
        if practicality.score > 0 { reasons.append(practicality.note) }
        if recentPenalty == 0 { reasons.append("gives recently worn pieces a break") }
        explanation = "\((reasons.first ?? "a simple combination from your wardrobe").capitalized) with \(names)."
        let weatherNote = context.weather.map { " Weather context: \($0.description), \(Int($0.temperatureCelsius.rounded()))°C in \($0.location.normalizedCity)." } ?? ""
        return OutfitSuggestion(id: stableID(for: ids), itemIDs: ids, score: score, explanation: explanation + weatherNote, factors: factors, recommendationID: recommendationID)
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

    private func matchesOccasion(_ item: GarmentItem, requested: String) -> Bool {
        let classification = item.classification?.suggestion
        let values = item.tags
            + (classification?.occasions ?? [])
            + [classification?.formality, classification?.garmentType].compactMap { $0 }
        return values.contains { $0.caseInsensitiveCompare(requested) == .orderedSame }
    }

    private func hasOccasionSignal(_ item: GarmentItem) -> Bool {
        if !(item.classification?.suggestion.occasions ?? []).isEmpty { return true }
        let knownOccasions = Set(GarmentTaxonomy.occasions.map { $0.lowercased() })
        return item.tags.contains { knownOccasions.contains($0.lowercased()) }
    }

    private func formalityAdjustment(for items: [GarmentItem]) -> (score: Int, note: String) {
        let values = items.compactMap { $0.classification?.suggestion.formality?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard values.count >= 2, Set(values).count == 1, let value = values.first else { return (0, "") }
        return (2, "keeps the formality consistently \(value)")
    }

    private func stableID(for ids: [UUID]) -> UUID {
        let canonical = ids.map(\.uuidString).sorted().joined(separator: ",")
        var first: UInt64 = 0xcbf29ce484222325
        var second: UInt64 = 0x84222325cbf29ce4
        for byte in canonical.utf8 {
            first = (first ^ UInt64(byte)) &* 0x100000001b3
            second = (second ^ UInt64(byte)) &* 0x100000001b3
        }
        let words = [first.bigEndian, second.bigEndian]
        let bytes = words.flatMap { value in
            withUnsafeBytes(of: value) { Array($0) }
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
