import Foundation
import UIKit
import Vision

/// The bounded set of fields a classifier may suggest. This is deliberately
/// smaller than the editable garment record: model text is never written to
/// storage until it has passed validation and the person has reviewed it.
struct GarmentClassificationSuggestion: Codable, Equatable, Sendable {
    let category: String
    let color: String?
    let tags: [String]
    let materialGuess: String?
    let garmentType: String?
    let pattern: String?
    let fit: String?
    let formality: String?
    let seasons: [String]
    let occasions: [String]

    init(
        category: String,
        color: String? = nil,
        tags: [String] = [],
        materialGuess: String? = nil,
        garmentType: String? = nil,
        pattern: String? = nil,
        fit: String? = nil,
        formality: String? = nil,
        seasons: [String] = [],
        occasions: [String] = []
    ) throws {
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GarmentTaxonomy.isKnownCategory(normalizedCategory) else {
            throw GarmentClassificationError.unknownCategory(normalizedCategory)
        }
        self.category = normalizedCategory
        self.color = Self.boundedOptional(color, field: "color", limit: 40)
        self.tags = try Self.boundedTags(tags)
        self.materialGuess = Self.boundedOptional(materialGuess, field: "material", limit: 40)
        self.garmentType = Self.boundedOptional(garmentType, field: "garment type", limit: 48)
        self.pattern = Self.boundedOptional(pattern, field: "pattern", limit: 32)
        self.fit = Self.boundedOptional(fit, field: "fit", limit: 32)
        self.formality = Self.boundedOptional(formality, field: "formality", limit: 32)
        self.seasons = try Self.boundedValues(seasons, limit: 4, field: "season")
        self.occasions = try Self.boundedValues(occasions, limit: 4, field: "occasion")
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

    private static func boundedValues(_ values: [String], limit: Int, field: String) throws -> [String] {
        guard values.count <= limit else { throw GarmentClassificationError.tooManyAttributes(field) }
        var unique: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized.count <= 32 else { throw GarmentClassificationError.invalidAttribute(field) }
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
    case tooManyAttributes(String)
    case invalidAttribute(String)
    case unavailable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .malformedResponse: "The local model returned an unusable suggestion. You can enter garment details manually."
        case .unknownCategory: "The local model suggested a category this wardrobe does not support. You can enter garment details manually."
        case .tooManyTags, .invalidTag, .tooManyAttributes, .invalidAttribute: "The local model returned unusable garment attributes. You can enter garment details manually."
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
        let garmentType: String?
        let pattern: String?
        let fit: String?
        let formality: String?
        let seasons: [String]?
        let occasions: [String]?
    }

    static func decode(_ text: String) throws -> GarmentClassificationSuggestion {
        guard let data = text.data(using: .utf8), let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw GarmentClassificationError.malformedResponse
        }
        return try GarmentClassificationSuggestion(
            category: payload.category,
            color: payload.color,
            tags: payload.tags ?? [],
            materialGuess: payload.materialGuess,
            garmentType: payload.garmentType,
            pattern: payload.pattern,
            fit: payload.fit,
            formality: payload.formality,
            seasons: payload.seasons ?? [],
            occasions: payload.occasions ?? []
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

/// A bounded vision request to the same configured Ollama/Gemma endpoint used
/// by the stylist. The model output is validated before it reaches local data.
struct OllamaGarmentClassifier: GarmentClassifying {
    private let configuration: OllamaConfiguration
    private let transport: any OllamaTransport

    init(configuration: OllamaConfiguration = .saved(), transport: any OllamaTransport = URLSessionOllamaTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    func classify(imageData: Data) async throws -> ClassificationProvenance {
        guard let url = configuration.chatURL else { throw GarmentClassificationError.unavailable }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaVisionRequest(
            model: configuration.model,
            stream: false,
            format: "json",
            think: false,
            messages: [
                .init(role: "system", content: "You tag one clothing item. Return JSON only with category, color, tags, materialGuess, garmentType, pattern, fit, formality, seasons, occasions. category must be one of Top, Bottom, Dress, One-piece outfit, Outerwear, Shoes, Accessory. Use concise strings. tags max 8; seasons and occasions max 4 each. Never infer a body or person.", images: nil),
                .init(role: "user", content: "Classify the garment in this image.", images: [imageData.base64EncodedString()])
            ]
        ))
        let (data, response) = try await transport.send(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GarmentClassificationError.unavailable
        }
        let payload = try JSONDecoder().decode(OllamaVisionResponse.self, from: data)
        let suggestion = try GarmentClassificationResponse.decode(payload.message.content)
        return ClassificationProvenance(
            modelID: configuration.model,
            modelRevision: "ollama",
            route: "remote-ollama-vision",
            classifiedAt: Date(),
            suggestion: suggestion,
            wasEditedBeforeSave: false
        )
    }
}

private struct OllamaVisionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
        let images: [String]?
    }
    let model: String
    let stream: Bool
    let format: String
    let think: Bool
    let messages: [Message]
}

private struct OllamaVisionResponse: Decodable {
    struct Message: Decodable { let content: String }
    let message: Message
}

enum VisionClassificationMapping {
    static func suggestion(for labels: [String]) throws -> GarmentClassificationSuggestion {
        let normalized = labels.map { $0.lowercased() }
        let category: String?
        if contains(normalized, any: ["t-shirt", "shirt", "blouse", "sweater", "hoodie", "top"]) { category = "Top" }
        else if contains(normalized, any: ["trousers", "pants", "jeans", "skirt", "shorts", "bottom"]) { category = "Bottom" }
        else if contains(normalized, any: ["dress", "jumpsuit"]) { category = "Dress" }
        else if contains(normalized, any: ["coat", "jacket", "cardigan", "outerwear"]) { category = "Outerwear" }
        else if contains(normalized, any: ["shoe", "sneaker", "boot", "sandal", "footwear"]) { category = "Shoes" }
        else if contains(normalized, any: ["bag", "hat", "scarf", "belt", "accessory"]) { category = "Accessory" }
        else { category = nil }
        guard let category else { throw GarmentClassificationError.unavailable }
        let tags = Array(labels.prefix(3)).map { $0.replacingOccurrences(of: "_", with: " ") }
        return try GarmentClassificationSuggestion(category: category, tags: tags)
    }

    private static func contains(_ labels: [String], any terms: [String]) -> Bool {
        labels.contains { label in terms.contains { label.localizedCaseInsensitiveContains($0) } }
    }
}

struct VisionGarmentClassifier: GarmentClassifying {
    func classify(imageData: Data) async throws -> ClassificationProvenance {
        try Task.checkCancellation()
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw GarmentClassificationError.malformedResponse
        }
        try Task.checkCancellation()
        let request = VNClassifyImageRequest()
        try await withTaskCancellationHandler {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } onCancel: {
            request.cancel()
        }
        try Task.checkCancellation()
        let labels = (request.results ?? [])
            .filter { $0.confidence >= 0.2 }
            .map(\.identifier)
        let suggestion = try VisionClassificationMapping.suggestion(for: labels)
        return ClassificationProvenance(
            modelID: "apple-vision",
            modelRevision: "VNClassifyImageRequest",
            route: "local-vision-observation",
            classifiedAt: Date(),
            suggestion: suggestion,
            wasEditedBeforeSave: false
        )
    }
}

actor GarmentClassificationCoordinator {
    private let classifier: any GarmentClassifying
    private let timeout: Duration

    init(classifier: any GarmentClassifying = OllamaGarmentClassifier(), timeout: Duration = .seconds(30)) {
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
