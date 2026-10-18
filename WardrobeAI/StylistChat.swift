import SwiftUI
import Security

enum OpenRouterSettings {
    static let enabledKey = "openrouter-fallback-enabled"
    static let modelKey = "openrouter-fallback-model"
    static let keychainAccount = "openrouter-api-key"
    static let defaultModel = "google/gemma-4-26b-a4b-it"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var model: String {
        let value = UserDefaults.standard.string(forKey: modelKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? defaultModel : value
    }

    static func apiKey() -> String? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Bundle.main.bundleIdentifier ?? "com.wardrobeai.ootd1", kSecAttrAccount: keychainAccount, kSecReturnData: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static func saveAPIKey(_ value: String) {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Bundle.main.bundleIdentifier ?? "com.wardrobeai.ootd1", kSecAttrAccount: keychainAccount]
        if key.isEmpty { SecItemDelete(query as CFDictionary); return }
        let attributes: [CFString: Any] = [kSecValueData: Data(key.utf8)]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var add = query; add[kSecValueData] = Data(key.utf8); SecItemAdd(add as CFDictionary, nil)
        }
    }
}

enum OpenRouterError: LocalizedError {
    case missingKey, invalidResponse, server(String)
    var errorDescription: String? {
        switch self { case .missingKey: "Add an OpenRouter API key in Cloud fallback settings."; case .invalidResponse: "OpenRouter returned an unreadable response."; case let .server(message): "OpenRouter: \(message)" }
    }
}

struct OpenRouterChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: Content

        init(role: String, content: String) {
            self.role = role
            self.content = .text(content)
        }

        init(role: String, content: Content) {
            self.role = role
            self.content = content
        }
    }

    enum Content: Encodable {
        case text(String)
        case parts([Part])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .text(value): try container.encode(value)
            case let .parts(value): try container.encode(value)
            }
        }
    }

    struct Part: Encodable {
        let type: String
        let text: String?
        let imageURL: String?

        enum CodingKeys: String, CodingKey { case type, text, imageURL = "image_url" }

        static func text(_ value: String) -> Part { Part(type: "text", text: value, imageURL: nil) }
        static func image(_ value: String) -> Part { Part(type: "image_url", text: nil, imageURL: value) }
    }

    let model: String; let messages: [Message]; let maxTokens: Int; let temperature: Double
    enum CodingKeys: String, CodingKey { case model, messages, maxTokens = "max_tokens", temperature }
}

struct OpenRouterChatResponse: Decodable {
    struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
    struct APIError: Decodable { let message: String? }
    let choices: [Choice]?; let error: APIError?
}

protocol CloudStylistResponding: Sendable { func reply(prompt: String, wardrobe: [GarmentItem]) async throws -> String }

struct OpenRouterClient: CloudStylistResponding {
    func reply(prompt: String, wardrobe: [GarmentItem]) async throws -> String {
        let inventory = wardrobe.prefix(24).map { "\($0.name) (\($0.category), \($0.color ?? "unspecified"))" }.joined(separator: "; ")
        let system = "You are a concise wardrobe stylist. Only recommend items from this owned inventory: \(inventory.isEmpty ? "No items supplied" : inventory). Do not claim to perform actions or record wear. If nothing fits, say so."
        let payload = OpenRouterChatRequest(model: OpenRouterSettings.model, messages: [.init(role: "system", content: system), .init(role: "user", content: prompt)], maxTokens: 180, temperature: 0.4)
        return try await Self.complete(payload)
    }

    static func complete(_ payload: OpenRouterChatRequest) async throws -> String {
        guard let key = OpenRouterSettings.apiKey() else { throw OpenRouterError.missingKey }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"; request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenRouterError.invalidResponse }
        let decoded = try? JSONDecoder().decode(OpenRouterChatResponse.self, from: data)
        guard (200...299).contains(http.statusCode) else { throw OpenRouterError.server(decoded?.error?.message ?? "HTTP \(http.statusCode)") }
        guard let text = decoded?.choices?.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { throw OpenRouterError.invalidResponse }
        return text
    }
}

enum StylistTool: String, Codable, CaseIterable, Sendable {
    case searchWardrobe
    case recentWear
    case context
    case recommendations
    case wearToday

    var isWrite: Bool { self == .wearToday }
}

struct StylistToolCall: Codable, Equatable, Sendable {
    let tool: StylistTool
    let query: String?
    let outfitID: UUID?

    init(tool: StylistTool, query: String? = nil, outfitID: UUID? = nil) {
        self.tool = tool
        self.query = query
        self.outfitID = outfitID
    }
}

enum StylistToolError: LocalizedError, Equatable {
    case callLimitReached
    case invalidArguments(String)
    case unknownOutfit
    case writeRequiresConfirmation

    var errorDescription: String? {
        switch self {
        case .callLimitReached: "The stylist reached its tool-call limit and stopped safely."
        case let .invalidArguments(message): message
        case .unknownOutfit: "That outfit is no longer in your wardrobe."
        case .writeRequiresConfirmation: "Recording wear requires your confirmation."
        }
    }
}

enum StylistToolResult: Equatable, Sendable {
    case garments([GarmentItem])
    case wear([WearEvent])
    case context(plans: [OutfitPlan])
    case recommendations([OutfitSuggestion])
    case wearRecorded(WearEvent)
}

@MainActor
final class StylistToolbox {
    private let store: WardrobeStore
    private(set) var callCount = 0
    let maximumCallCount: Int

    init(store: WardrobeStore, maximumCallCount: Int = 3) {
        self.store = store
        self.maximumCallCount = maximumCallCount
    }

    func resetCallCount() { callCount = 0 }
    func itemName(_ id: UUID) -> String? { store.item(id: id)?.name }
    func ownedGarments() -> [GarmentItem] { store.allGarments }

    func execute(_ call: StylistToolCall, confirmedByUser: Bool = false) throws -> StylistToolResult {
        guard callCount < maximumCallCount else { throw StylistToolError.callLimitReached }
        callCount += 1

        switch call.tool {
        case .searchWardrobe:
            let query = call.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !query.isEmpty else { throw StylistToolError.invalidArguments("Enter what you want to find in your wardrobe.") }
            return .garments(try store.repository.items(matching: query, category: nil, tag: nil))
        case .recentWear:
            return .wear(Array(store.wearEvents.prefix(5)))
        case .context:
            let upcoming = store.outfitPlans.filter { $0.scheduledFor >= Date() }.sorted { $0.scheduledFor < $1.scheduledFor }
            return .context(plans: Array(upcoming.prefix(5)))
        case .recommendations:
            return .recommendations(try store.recommendations(for: nil).prefix(3).map { $0 })
        case .wearToday:
            guard confirmedByUser else { throw StylistToolError.writeRequiresConfirmation }
            guard let outfitID = call.outfitID else { throw StylistToolError.invalidArguments("Choose a saved outfit before recording wear.") }
            guard let outfit = store.outfits.first(where: { $0.id == outfitID }) else { throw StylistToolError.unknownOutfit }
            return .wearRecorded(try store.wearToday(outfit))
        }
    }
}

struct StylistChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
}

@MainActor
final class StylistChat: ObservableObject {
    @Published private(set) var messages: [StylistChatMessage] = []
    @Published private(set) var pendingWearOutfit: Outfit?
    @Published private(set) var isResponding = false

    private let toolbox: StylistToolbox
    private let cloudResponder: any CloudStylistResponding
    private var responseTask: Task<Void, Never>?
    private var activeResponseID: UUID?

    init(store: WardrobeStore, cloudResponder: any CloudStylistResponding = OpenRouterClient()) {
        toolbox = StylistToolbox(store: store)
        self.cloudResponder = cloudResponder
    }

    func send(_ input: String) {
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isResponding else { return }
        messages.append(.init(role: .user, text: request))
        toolbox.resetCallCount()
        isResponding = true
        let responseID = UUID()
        activeResponseID = responseID
        responseTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.activeResponseID == responseID {
                    self.activeResponseID = nil
                    self.responseTask = nil
                    self.isResponding = false
                }
            }
            guard !Task.isCancelled, self.activeResponseID == responseID else { return }
            let localResponse: String
            if request.localizedCaseInsensitiveContains("recent") || request.localizedCaseInsensitiveContains("wore") {
                localResponse = self.wearSummary()
            } else if request.localizedCaseInsensitiveContains("plan") || request.localizedCaseInsensitiveContains("calendar") {
                localResponse = self.contextSummary()
            } else if Self.isRecommendationRequest(request) {
                localResponse = self.recommendationSummary()
            } else {
                localResponse = self.searchSummary(for: Self.searchTerms(from: request))
            }
            let response = await self.cloudFallback(for: request, localResponse: localResponse)
            await self.stream(response, responseID: responseID)
        }
    }

    func cancel() {
        responseTask?.cancel()
        activeResponseID = nil
        responseTask = nil
        isResponding = false
    }

    func requestWear(for outfit: Outfit) { pendingWearOutfit = outfit }

    func confirmWear() {
        guard let outfit = pendingWearOutfit else { return }
        defer { pendingWearOutfit = nil }
        toolbox.resetCallCount()
        do {
            _ = try toolbox.execute(.init(tool: .wearToday, outfitID: outfit.id), confirmedByUser: true)
            messages.append(.init(role: .assistant, text: "Recorded \(outfit.name) as worn today."))
        } catch { messages.append(.init(role: .assistant, text: error.localizedDescription)) }
    }

    func dismissWearConfirmation() { pendingWearOutfit = nil }

    private func searchSummary(for query: String) -> String {
        do {
            guard case let .garments(items) = try toolbox.execute(.init(tool: .searchWardrobe, query: query)) else { return "" }
            let names = items.prefix(5).map(\.name)
            return names.isEmpty ? "I couldn’t find owned garments matching that. Try a color, category, or tag." : "I found: \(names.joined(separator: ", "))."
        } catch { return error.localizedDescription }
    }

    private func wearSummary() -> String {
        do {
            guard case let .wear(events) = try toolbox.execute(.init(tool: .recentWear)) else { return "" }
            return events.isEmpty ? "No wear has been recorded yet." : "You have \(events.count) recent wear record\(events.count == 1 ? "" : "s")."
        } catch { return error.localizedDescription }
    }

    private func contextSummary() -> String {
        do {
            guard case let .context(plans) = try toolbox.execute(.init(tool: .context)) else { return "" }
            return plans.isEmpty ? "You have no upcoming in-app outfit plans." : "You have \(plans.count) upcoming outfit plan\(plans.count == 1 ? "" : "s")."
        } catch { return error.localizedDescription }
    }

    private func recommendationSummary() -> String {
        do {
            guard case let .recommendations(suggestions) = try toolbox.execute(.init(tool: .recommendations)) else { return "" }
            guard !suggestions.isEmpty else { return "Add a few garments to get owned-item outfit suggestions." }
            return "Try: " + suggestions.map { suggestion in
                suggestion.itemIDs.compactMap { toolbox.itemName($0) }.joined(separator: " + ")
            }.filter { !$0.isEmpty }.joined(separator: "; ") + "."
        } catch { return error.localizedDescription }
    }

    private func cloudFallback(for request: String, localResponse: String) async -> String {
        guard OpenRouterSettings.isEnabled,
              localResponse.contains("couldn’t find") || localResponse.contains("Add a few garments")
        else { return localResponse }
        do { return try await cloudResponder.reply(prompt: request, wardrobe: toolbox.ownedGarments()) }
        catch { return "\(localResponse) Cloud fallback is unavailable: \(error.localizedDescription)" }
    }

    private static func isRecommendationRequest(_ request: String) -> Bool {
        let normalized = request.lowercased()
        return ["what should i wear", "recommend", "outfit", "style me"].contains(where: normalized.contains)
    }

    private static func searchTerms(from request: String) -> String {
        let wordsToRemove: Set<String> = ["find", "search", "show", "look", "for", "my", "me", "do", "i", "own", "have", "a", "an", "the", "please", "some", "any", "in", "wardrobe"]
        let terms = request.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { !wordsToRemove.contains($0.lowercased()) }
        return terms.joined(separator: " ")
    }

    private func stream(_ response: String, responseID: UUID) async {
        messages.append(.init(role: .assistant, text: ""))
        let messageID = messages[messages.index(before: messages.endIndex)].id
        for word in response.split(separator: " ") {
            guard !Task.isCancelled, activeResponseID == responseID,
                  let index = messages.firstIndex(where: { $0.id == messageID }) else {
                if let index = messages.firstIndex(where: { $0.id == messageID }) {
                    messages.remove(at: index)
                }
                return
            }
            messages[index].text += (messages[index].text.isEmpty ? "" : " ") + word
            try? await Task.sleep(for: .milliseconds(12))
        }
    }
}

struct StylistChatView: View {
    @ObservedObject var store: WardrobeStore
    @StateObject private var chat: StylistChat
    @State private var draft = ""

    init(store: WardrobeStore) {
        self.store = store
        _chat = StateObject(wrappedValue: StylistChat(store: store))
    }

    var body: some View {
        Section("Ask your stylist") {
            ForEach(chat.messages.suffix(6)) { message in
                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                    Text(message.role == .user ? "You" : "Stylist").font(.caption).foregroundStyle(.secondary)
                    Text(message.text).frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                }
                .accessibilityElement(children: .combine)
            }
            HStack {
                TextField("Find a garment, recent wear, or plans", text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                if chat.isResponding {
                    Button("Cancel", action: chat.cancel)
                } else {
                    Button("Send") { chat.send(draft); draft = "" }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if !store.outfits.isEmpty {
                Menu("Record wear…") {
                    ForEach(store.outfits) { outfit in
                        Button(outfit.name) { chat.requestWear(for: outfit) }
                    }
                }
            }
            Text("The stylist can search owned garments and read recent wear or in-app plans. It cannot record wear until you confirm a saved outfit.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .confirmationDialog("Record this outfit as worn today?", isPresented: Binding(get: { chat.pendingWearOutfit != nil }, set: { if !$0 { chat.dismissWearConfirmation() } }), titleVisibility: .visible) {
            Button("Wear today") { chat.confirmWear() }
            Button("Cancel", role: .cancel) { chat.dismissWearConfirmation() }
        } message: {
            Text(chat.pendingWearOutfit?.name ?? "")
        }
    }
}
