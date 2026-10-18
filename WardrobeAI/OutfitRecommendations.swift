import Foundation

struct RecommendationContext: Equatable, Sendable {
    var occasion: String?
    var preferredColors: [String]
    var preferredCategories: [String] = []
    var anchorItemID: UUID? = nil
    var weather: WeatherSnapshot? = nil
    var weatherFreshness: WeatherFreshness? = nil
    var dressCodeNote: String? = nil
    var lockedItemIDs: [UUID] = []
    var requestedSlots: [RecommendationSlot] = []
    var warmth: WarmthPreference = .any
    var tolerateRain = false
    var prioritizeWalkingComfort = false
    var repeatFrequency: RepeatFrequency = .any
    var formality: String? = nil
    var footwearPreference: String? = nil
    var calendarBusyPeriods: [CalendarBusyPeriod] = []

    static let everyday = RecommendationContext(occasion: nil, preferredColors: [], preferredCategories: [], anchorItemID: nil, weather: nil, weatherFreshness: nil)
}

enum RecommendationSlot: String, Codable, CaseIterable, Sendable, Identifiable {
    case completeLook, footwear, outerwear, accessory, chooseForMe
    var id: String { rawValue }
}

enum RecommendationSkipReason: String, Codable, CaseIterable, Sendable, Identifiable {
    case wrongOccasion, weather, comfort, color, tooFormal, somethingElse
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wrongOccasion: "Wrong occasion"
        case .weather: "Weather"
        case .comfort: "Comfort"
        case .color: "Color"
        case .tooFormal: "Too formal"
        case .somethingElse: "Something else"
        }
    }
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
    let lockedItemIDs: [UUID]
    let requestedSlots: [RecommendationSlot]
    let outcomeReason: RecommendationSkipReason?

    init(id: UUID, recommendationID: UUID, candidateIDs: [UUID], contextSnapshot: String, source: RecommendationSource, outcome: RecommendationOutcome, occurredAt: Date, lockedItemIDs: [UUID] = [], requestedSlots: [RecommendationSlot] = [], outcomeReason: RecommendationSkipReason? = nil) {
        self.id = id
        self.recommendationID = recommendationID
        self.candidateIDs = candidateIDs
        self.contextSnapshot = contextSnapshot
        self.source = source
        self.outcome = outcome
        self.occurredAt = occurredAt
        self.lockedItemIDs = lockedItemIDs
        self.requestedSlots = requestedSlots
        self.outcomeReason = outcomeReason
    }
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
        let availableItems = items.filter { $0.availability == .active }
        let byCategory = Dictionary(grouping: availableItems, by: \.category)
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

        let lockedIDs = context.lockedItemIDs + [context.anchorItemID].compactMap { $0 }
        var seenLockedIDs = Set<UUID>()
        let uniqueLockedIDs = lockedIDs.filter { seenLockedIDs.insert($0).inserted }
        guard uniqueLockedIDs.count <= 3,
              uniqueLockedIDs.allSatisfy({ id in availableItems.contains(where: { $0.id == id }) }) else { return [] }
        let lockedItems = uniqueLockedIDs.compactMap { id in availableItems.first(where: { $0.id == id }) }
        guard !Self.hasPrimaryConflict(lockedItems) else { return [] }
        let explicitSlots = context.requestedSlots.filter { $0 != .completeLook && $0 != .chooseForMe }
        let fullLook = context.requestedSlots.isEmpty || context.requestedSlots.contains(.completeLook) || context.requestedSlots.contains(.chooseForMe)
        let baseSets: [[GarmentItem]]
        if fullLook {
            baseSets = fullLookBases(locked: lockedItems, byCategory: byCategory)
        } else {
            let hasPrimary = lockedItems.contains { ["Top", "Bottom", "Dress", "One-piece outfit"].contains($0.category) }
            if hasPrimary {
                baseSets = [lockedItems]
            } else {
                let compatibleBases = fullLookBases(locked: lockedItems, byCategory: byCategory).map { base in merge(base: base, locked: lockedItems) }
                baseSets = compatibleBases.isEmpty ? [] : compatibleBases
            }
        }
        var variationsByBase: [[[GarmentItem]]] = []
        for base in baseSets {
            let merged = merge(base: base, locked: lockedItems)
            guard !merged.isEmpty else { continue }
            let openCategories: [String]
            if fullLook {
                openCategories = ["Outerwear", "Shoes", "Accessory"]
            } else {
                openCategories = explicitSlots.map(Self.category(for:))
            }
            variationsByBase.append(slotVariations(base: merged, categories: openCategories, byCategory: byCategory, mandatory: !fullLook))
        }
        var variation = 0
        while evaluations < maximumCandidateEvaluations {
            var consideredAny = false
            for variations in variationsByBase where variation < variations.count {
                consider(variations[variation])
                consideredAny = true
                if evaluations >= maximumCandidateEvaluations { break }
            }
            guard consideredAny else { break }
            variation += 1
        }
        if bounded.isEmpty {
            if lockedItems.isEmpty { for item in availableItems { consider([item]) } }
            else if fullLook { consider(lockedItems) }
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

    static func hasPrimaryConflict(_ items: [GarmentItem]) -> Bool {
        let primary = items.filter { ["Top", "Bottom", "Dress", "One-piece outfit"].contains($0.category) }
        let categories = primary.map(\.category)
        guard Set(categories).count == categories.count else { return true }
        let hasOnePiece = categories.contains("Dress") || categories.contains("One-piece outfit")
        return hasOnePiece && (categories.contains("Top") || categories.contains("Bottom"))
    }

    static func category(for slot: RecommendationSlot) -> String {
        switch slot {
        case .footwear: "Shoes"
        case .outerwear: "Outerwear"
        case .accessory: "Accessory"
        case .completeLook, .chooseForMe: ""
        }
    }

    func replacing(_ replacedID: UUID, in suggestion: OutfitSuggestion, with replacement: GarmentItem, items: [GarmentItem], preferences: StylePreferences, wearEvents: [WearEvent], context: RecommendationContext) -> OutfitSuggestion? {
        guard replacement.availability == .active,
              let oldItem = items.first(where: { $0.id == replacedID }),
              oldItem.category == replacement.category,
              suggestion.itemIDs.contains(replacedID),
              !suggestion.itemIDs.contains(replacement.id) else { return nil }
        let selected = suggestion.itemIDs.compactMap { id in items.first(where: { $0.id == id }) }.map { $0.id == replacedID ? replacement : $0 }
        guard selected.count == suggestion.itemIDs.count, !Self.hasPrimaryConflict(selected) else { return nil }
        let recentIDs = Set(wearEvents.prefix(3).flatMap(\.itemIDs))
        return makeSuggestion(selected, preferences: preferences, recentIDs: recentIDs, context: context, recommendationID: suggestion.recommendationID ?? UUID(), source: suggestion.source)
    }

    static func validationMessage(lockedItems: [GarmentItem], requestedSlots: [RecommendationSlot]) -> String? {
        guard lockedItems.count <= 3 else { return "Lock up to three garments." }
        guard lockedItems.allSatisfy({ $0.availability == .active }) else { return "Only available garments can be locked." }
        if hasPrimaryConflict(lockedItems) { return "Choose one dress or one top and one bottom." }
        let counts = Dictionary(grouping: lockedItems, by: \.category).mapValues(\.count)
        if counts.values.contains(where: { $0 > 1 }) { return "Lock only one garment in each role." }
        let selectedSlotCategory = requestedSlots.first.map(category(for:)) ?? ""
        if !selectedSlotCategory.isEmpty, counts[selectedSlotCategory, default: 0] > 0 { return "That role is already locked. Choose another open slot." }
        return nil
    }

    static func validationMessage(lockedItems: [GarmentItem], requestedSlots: [RecommendationSlot], allItems: [GarmentItem]) -> String? {
        if let issue = validationMessage(lockedItems: lockedItems, requestedSlots: requestedSlots) { return issue }
        let lockedPrimary = lockedItems.filter { ["Top", "Bottom", "Dress", "One-piece outfit"].contains($0.category) }
        let requestedPrimaryOpen = lockedPrimary.isEmpty && requestedSlots.contains { [.completeLook, .chooseForMe].contains($0) }
        if requestedPrimaryOpen {
            let active = allItems.filter { $0.availability == .active }
            guard active.contains(where: { ["Dress", "One-piece outfit"].contains($0.category) })
                    || (active.contains(where: { $0.category == "Top" }) && active.contains(where: { $0.category == "Bottom" })) else {
                return "Add an available top and bottom or a dress to complete this look."
            }
        }
        return nil
    }

    private func fullLookBases(locked: [GarmentItem], byCategory: [String: [GarmentItem]]) -> [[GarmentItem]] {
        let lockedPrimary = locked.filter { ["Top", "Bottom", "Dress", "One-piece outfit"].contains($0.category) }
        if lockedPrimary.contains(where: { $0.category == "Dress" || $0.category == "One-piece outfit" }) {
            return [lockedPrimary]
        }
        let tops = lockedPrimary.first(where: { $0.category == "Top" }).map { [$0] } ?? (byCategory["Top"] ?? [])
        let bottoms = lockedPrimary.first(where: { $0.category == "Bottom" }).map { [$0] } ?? (byCategory["Bottom"] ?? [])
        var bases = (byCategory["Dress"] ?? []).map { [$0] } + (byCategory["One-piece outfit"] ?? []).map { [$0] }
        for top in tops {
            for bottom in bottoms { bases.append([top, bottom]) }
        }
        bases = bases.filter { base in
            lockedPrimary.allSatisfy { lockedItem in base.contains(where: { $0.id == lockedItem.id }) }
        }
        if bases.isEmpty, !lockedPrimary.isEmpty { return [lockedPrimary] }
        if bases.isEmpty, !locked.isEmpty { return [[]] }
        return bases
    }

    private func merge(base: [GarmentItem], locked: [GarmentItem]) -> [GarmentItem] {
        var result = base
        for item in locked where !result.contains(where: { $0.id == item.id }) {
            guard !result.contains(where: { $0.category == item.category }) else { return [] }
            result.append(item)
        }
        return Self.hasPrimaryConflict(result) ? [] : result
    }

    private func slotVariations(base: [GarmentItem], categories: [String], byCategory: [String: [GarmentItem]], mandatory: Bool) -> [[GarmentItem]] {
        var optionsByCategory: [[GarmentItem?]] = []
        let selectedCategories = Set(base.map(\.category))
        if mandatory && categories.contains(where: { selectedCategories.contains($0) }) { return [] }
        for category in categories where !selectedCategories.contains(category) {
            let choices = Array((byCategory[category] ?? []).prefix(8))
            guard !mandatory || !choices.isEmpty else { return [] }
            optionsByCategory.append((mandatory ? [] : [nil]) + choices.map(Optional.some))
        }
        guard !mandatory || !optionsByCategory.isEmpty else { return [] }
        var results: [[GarmentItem]] = []
        func append(_ index: Int, _ candidate: [GarmentItem]) {
            guard results.count < 64 else { return }
            guard index < optionsByCategory.count else { results.append(candidate); return }
            for option in optionsByCategory[index] { append(index + 1, candidate + (option.map { [$0] } ?? [])) }
        }
        append(0, base)
        return results
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

    private func makeSuggestion(_ items: [GarmentItem], preferences: StylePreferences, recentIDs: Set<UUID>, context: RecommendationContext, recommendationID: UUID, source: RecommendationSource = .localRules) -> OutfitSuggestion {
        let ids = items.map(\.id)
        let occasion = context.occasion?.lowercased()
        let requestedDressCode = context.dressCodeNote?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let requestedFormality = context.formality ?? preferences.preferredFormality
        let occasionMatches = occasion.map { requested in items.filter { matchesOccasion($0, requested: requested) }.count } ?? 0
        let dressCodeMatches = requestedDressCode.map { requested in items.filter { matchesOccasion($0, requested: requested) }.count } ?? 0
        let occasionConflicts = occasion.map { requested in
            items.filter { hasOccasionSignal($0) && !matchesOccasion($0, requested: requested) }.count
        } ?? 0
        let colorMatches = items.filter { item in
            guard let color = item.color?.lowercased() else { return false }
            return (context.preferredColors + preferences.preferredColors).contains { $0.lowercased() == color }
        }.count
        let preferredCategories = items.filter { preferences.preferredCategories.contains($0.category) }.count
        let recentCount = items.filter { recentIDs.contains($0.id) }.count
        let repeatScore: Int
        switch context.repeatFrequency == .any ? preferences.repeatFrequency : context.repeatFrequency {
        case .any: repeatScore = 0
        case .avoidRecent: repeatScore = -recentCount * 3
        case .repeatRecent: repeatScore = recentCount * 2
        }
        let warmth = context.warmth == .any ? preferences.warmthPreference : context.warmth
        let usableWeather = context.weatherFreshness == .stale || context.weatherFreshness == .unavailable ? nil : context.weather
        let weatherScore = weatherAdjustment(for: items, weather: usableWeather, warmth: warmth, tolerateRain: context.tolerateRain || preferences.prefersRainTolerance)
        let constraints = constraintFactors(for: items, preferences: preferences, context: context)
        let practicality = practicalityAdjustment(for: items)
        let formality = formalityAdjustment(for: items, desired: requestedFormality)
        let calendarAdjustment = calendarAdjustment(for: items, periods: context.calendarBusyPeriods)
        let score = occasionMatches * 4 + dressCodeMatches * 2 - occasionConflicts * 3 + colorMatches * 2 + preferredCategories + weatherScore + practicality.score + formality.score + repeatScore + calendarAdjustment + constraints.reduce(0) { $0 + $1.value }
        var factors: [RecommendationFactor] = []
        if let occasion = context.occasion {
            factors.append(RecommendationFactor(name: "occasion", value: occasionMatches * 4 - occasionConflicts * 3, reason: "Compared item tags and classification metadata with the selected occasion: \(occasion)."))
        }
        if let requestedDressCode, !requestedDressCode.isEmpty { factors.append(RecommendationFactor(name: "dressCode", value: dressCodeMatches * 2, reason: "Compared known garment tags and classification metadata with your dress-code note: \(requestedDressCode).")) }
        if context.weatherFreshness == .stale { factors.append(RecommendationFactor(name: "weatherFreshness", value: 0, reason: "Weather data is stale; refresh it before relying on weather-sensitive choices.")) }
        if context.weatherFreshness == .cached { factors.append(RecommendationFactor(name: "weatherFreshness", value: 0, reason: "Weather data is cached from an earlier refresh.")) }
        if colorMatches > 0 { factors.append(RecommendationFactor(name: "preferredColors", value: colorMatches * 2, reason: "Matched \(colorMatches) item color(s) to saved or selected color preferences.")) }
        if preferredCategories > 0 { factors.append(RecommendationFactor(name: "preferredCategories", value: preferredCategories, reason: "Matched \(preferredCategories) item(s) to saved category preferences.")) }
        if context.anchorItemID != nil { factors.append(RecommendationFactor(name: "anchor", value: 0, reason: "Includes the garment you selected as the starting piece.")) }
        if context.weather != nil, context.weatherFreshness != .stale { factors.append(RecommendationFactor(name: "weather", value: weatherScore, reason: "Adjusted for the supplied weather snapshot and its garment layers.")) }
        factors.append(RecommendationFactor(name: "recentWear", value: repeatScore, reason: recentCount == 0 ? "No candidate items appear in the three most recent wear events." : "Applied the selected or saved repeat preference to \(recentCount) recently worn item(s)."))
        if !context.calendarBusyPeriods.isEmpty {
            factors.append(RecommendationFactor(name: "calendarAvailability", value: calendarAdjustment, reason: "Considered \(context.calendarBusyPeriods.count) selected busy period(s) without reading or storing event titles."))
        }
        factors.append(contentsOf: constraints)
        factors.append(RecommendationFactor(name: "completeness", value: practicality.score, reason: practicality.note + "."))
        if formality.score != 0 { factors.append(RecommendationFactor(name: "formality", value: formality.score, reason: formality.note + ".")) }
        let names = items.map(\.name).joined(separator: " with ")
        let explanation: String
        var reasons: [String] = []
        if occasionMatches > 0, let occasion { reasons.append("has \(occasionMatches) piece\(occasionMatches == 1 ? "" : "s") suited to \(occasion)") }
        if formality.score > 0 { reasons.append(formality.note) }
        if practicality.score > 0 { reasons.append(practicality.note) }
        if repeatScore < 0 { reasons.append("gives recently worn pieces a break") }
        explanation = "\((reasons.first ?? "a simple combination from your wardrobe").capitalized) with \(names)."
        let weatherNote = usableWeather.map { " Weather context: \($0.description), \(Int($0.temperatureCelsius.rounded()))°C in \($0.location.normalizedCity)." } ?? ""
        return OutfitSuggestion(id: stableID(for: ids), itemIDs: ids, score: score, explanation: explanation + weatherNote, factors: factors, recommendationID: recommendationID, source: source)
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

    private func weatherAdjustment(for items: [GarmentItem], weather: WeatherSnapshot?, warmth: WarmthPreference, tolerateRain: Bool) -> Int {
        guard let weather else { return 0 }
        let categories = items.map(\.category)
        var adjustment = 0
        if weather.temperatureCelsius < 15, categories.contains("Outerwear") { adjustment += 2 }
        if weather.temperatureCelsius > 24, categories.contains("Outerwear") { adjustment -= 2 }
        if warmth == .preferWarm, weather.temperatureCelsius < 20 {
            adjustment += items.filter { ($0.classification?.suggestion.warmth ?? "").localizedCaseInsensitiveContains("warm") || $0.category == "Outerwear" }.count
        }
        if warmth == .preferLight, weather.temperatureCelsius > 20 {
            adjustment += items.filter { ($0.classification?.suggestion.warmth ?? "").localizedCaseInsensitiveContains("light") }.count
        }
        if weather.condition == .rain || weather.condition == .thunderstorm {
            if categories.contains("Outerwear") { adjustment += 2 }
            if tolerateRain { adjustment += items.filter { $0.tags.contains(where: { $0.localizedCaseInsensitiveContains("rain") || $0.localizedCaseInsensitiveContains("waterproof") }) }.count * 2 }
        }
        return adjustment
    }

    private func constraintFactors(for items: [GarmentItem], preferences: StylePreferences, context: RecommendationContext) -> [RecommendationFactor] {
        var factors: [RecommendationFactor] = []
        if preferences.prefersWalkingComfort || context.prioritizeWalkingComfort {
            let comfortable = items.filter { item in
                item.category == "Shoes" && (item.tags + (item.classification?.suggestion.styleKeywords ?? [])).contains { ["walking", "comfortable", "sneaker", "trainer"].contains($0.lowercased()) }
            }.count
            factors.append(RecommendationFactor(name: "walkingComfort", value: comfortable * 2, reason: comfortable > 0 ? "Matched walking-comfort tags on footwear." : "No selected footwear has a walking-comfort tag."))
        }
        let desiredFormality = context.formality ?? preferences.preferredFormality
        if let desired = desiredFormality, !desired.isEmpty {
            let matches = items.filter { $0.classification?.suggestion.formality?.caseInsensitiveCompare(desired) == .orderedSame }.count
            factors.append(RecommendationFactor(name: "formalityPreference", value: matches * 2, reason: "Matched saved formality preference: \(desired)."))
        }
        let desiredFootwear = context.footwearPreference ?? preferences.footwearPreference
        if let desired = desiredFootwear, !desired.isEmpty {
            let matches = items.filter { $0.category == "Shoes" && ($0.name.localizedCaseInsensitiveContains(desired) || $0.tags.contains(where: { $0.localizedCaseInsensitiveContains(desired) })) }.count
            factors.append(RecommendationFactor(name: "footwearPreference", value: matches * 2, reason: "Compared owned footwear names and tags with your preference: \(desired)."))
        }
        return factors
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

    private func formalityAdjustment(for items: [GarmentItem], desired: String?) -> (score: Int, note: String) {
        let values = items.compactMap { $0.classification?.suggestion.formality?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if let desired = desired?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !desired.isEmpty {
            let matches = values.filter { $0 == desired }.count
            let conflicts = values.count - matches
            let score = matches * 2 - conflicts * 2
            return (score, matches > 0 ? "matches the \(desired) formality preference" : "does not match the \(desired) formality preference")
        }
        guard values.count >= 2, Set(values).count == 1, let value = values.first else { return (0, "") }
        return (2, "keeps the formality consistently \(value)")
    }

    private func calendarAdjustment(for items: [GarmentItem], periods: [CalendarBusyPeriod]) -> Int {
        guard !periods.isEmpty else { return 0 }
        let hasEveningEvent = periods.contains { period in
            guard !period.isAllDay else { return false }
            let hour = Calendar.current.component(.hour, from: period.startDate)
            return hour >= 17 || hour < 8
        }
        guard hasEveningEvent else { return 0 }
        return items.filter { item in
            (item.tags + (item.classification?.suggestion.occasions ?? [])).contains { ["evening", "formal"].contains($0.lowercased()) }
        }.count
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
