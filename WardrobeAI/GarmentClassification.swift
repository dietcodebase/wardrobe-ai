import Foundation

/// The bounded set of fields a classifier may suggest. This is deliberately
/// smaller than the editable garment record: model text is never written to
/// storage until it has passed validation and the person has reviewed it.
struct GarmentClassificationSuggestion: Codable, Equatable, Sendable {
    let category: String
    let color: String?
    let tags: [String]
    let materialGuess: String?

    init(category: String, color: String? = nil, tags: [String] = [], materialGuess: String? = nil) throws {
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GarmentTaxonomy.isKnownCategory(normalizedCategory) else {
            throw GarmentClassificationError.unknownCategory(normalizedCategory)
        }
        self.category = normalizedCategory
        self.color = Self.boundedOptional(color, field: "color", limit: 40)
        self.tags = try Self.boundedTags(tags)
        self.materialGuess = Self.boundedOptional(materialGuess, field: "material", limit: 40)
    }

    private static func boundedTags(_ tags: [String]) throws -> [String] {
        guard tags.count <= 8 else { throw GarmentClassificationError.tooManyTags }
        var unique: [String] = []
        for tag in tags {
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized.count <= 32 else { throw GarmentClassificationError.invalidTag }
            if !unique.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
                unique.append(normalized)
            }
        }
        return unique
    }

    private static func boundedOptional(_ value: String?, field: String, limit: Int) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(limit))
    }
}

struct ClassificationProvenance: Codable, Equatable, Sendable {
    let modelID: String
    let modelRevision: String
    let route: String
    let classifiedAt: Date
    let suggestion: GarmentClassificationSuggestion
    var wasEditedBeforeSave: Bool
}

enum GarmentClassificationError: LocalizedError, Equatable {
    case malformedResponse
    case unknownCategory(String)
    case tooManyTags
    case invalidTag
    case unavailable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .malformedResponse: "The local model returned an unusable suggestion. You can enter garment details manually."
        case .unknownCategory: "The local model suggested a category this wardrobe does not support. You can enter garment details manually."
        case .tooManyTags, .invalidTag: "The local model returned unusable tags. You can enter garment details manually."
        case .unavailable: "Automatic suggestions are unavailable. You can still save this garment manually."
        case .timedOut: "Automatic suggestions took too long. You can still save this garment manually."
        }
    }
}

enum GarmentClassificationResponse {
    private struct Payload: Decodable {
        let category: String
        let color: String?
        let tags: [String]?
        let materialGuess: String?
    }

    static func decode(_ text: String) throws -> GarmentClassificationSuggestion {
        guard let data = text.data(using: .utf8), let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw GarmentClassificationError.malformedResponse
        }
        return try GarmentClassificationSuggestion(
            category: payload.category,
            color: payload.color,
            tags: payload.tags ?? [],
            materialGuess: payload.materialGuess
        )
    }
}

protocol GarmentClassifying: Sendable {
    func classify(imageData: Data) async throws -> ClassificationProvenance
}

struct UnavailableGarmentClassifier: GarmentClassifying {
    func classify(imageData: Data) async throws -> ClassificationProvenance {
        throw GarmentClassificationError.unavailable
    }
}

actor GarmentClassificationCoordinator {
    private let classifier: any GarmentClassifying
    private let timeout: Duration

    init(classifier: any GarmentClassifying = UnavailableGarmentClassifier(), timeout: Duration = .seconds(12)) {
        self.classifier = classifier
        self.timeout = timeout
    }

    func classify(imageData: Data) async throws -> ClassificationProvenance {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: ClassificationProvenance.self) { group in
            group.addTask { try await self.classifier.classify(imageData: imageData) }
            group.addTask {
                try await Task.sleep(for: self.timeout)
                throw GarmentClassificationError.timedOut
            }
            guard let result = try await group.next() else { throw GarmentClassificationError.unavailable }
            group.cancelAll()
            return result
        }
    }
}
