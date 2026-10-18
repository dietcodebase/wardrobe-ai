import Foundation
import SwiftUI
import Iconoir

/// Persisted connection details for an Ollama server. The endpoint is intentionally
/// user-configured: a device's `localhost` is not the same machine as a remote
/// Ollama host, and the app must never guess a private network address.
struct OllamaConfiguration: Equatable, Sendable {
    static let endpointKey = "ollama-endpoint"
    static let modelKey = "ollama-model"
    static let defaultModel = "gemma4:latest"

    let endpoint: URL?
    let model: String

    init(endpointText: String, model: String = OllamaConfiguration.defaultModel) {
        let trimmedEndpoint = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = URL(string: trimmedEndpoint)
        endpoint = candidate.flatMap { url in
            guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
            return url
        }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = trimmedModel.isEmpty ? Self.defaultModel : trimmedModel
    }

    static func saved(defaults: UserDefaults = .standard) -> OllamaConfiguration {
        OllamaConfiguration(
            endpointText: defaults.string(forKey: endpointKey) ?? "",
            model: defaults.string(forKey: modelKey) ?? defaultModel
        )
    }

    var isConfigured: Bool { endpoint != nil }

    private func apiURL(_ route: String) -> URL? {
        guard let endpoint else { return nil }
        let base = endpoint.path.hasSuffix("/") ? endpoint : endpoint.appendingPathComponent("")
        // Accept either an Ollama server root or a copied /api URL.
        return base.path.hasSuffix("/api/") || base.path.hasSuffix("/api")
            ? base.appendingPathComponent(route)
            : base.appendingPathComponent("api/" + route)
    }

    var chatURL: URL? { apiURL("chat") }
    var tagsURL: URL? { apiURL("tags") }
}

enum OllamaError: LocalizedError, Equatable {
    case notConfigured
    case invalidResponse
    case server(statusCode: Int, message: String)
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Add your remote Ollama server URL to use Gemma 4."
        case .invalidResponse: "Ollama returned an unreadable response."
        case let .server(statusCode, message): "Ollama returned HTTP \(statusCode): \(message)"
        case let .modelUnavailable(model): "The server is reachable, but \(model) is not installed. Run: ollama pull \(model)"
        }
    }
}

protocol OllamaTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionOllamaTransport: OllamaTransport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

enum StylistResponseFormatter {
    static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "```", with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { rawLine in
                var line = rawLine.trimmingCharacters(in: .whitespaces)
                line = line.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
                line = line.replacingOccurrences(of: "^[-*•]\\s+", with: "", options: .regularExpression)
                line = line.replacingOccurrences(of: "^\\d+[.)]\\s+", with: "", options: .regularExpression)
                line = line.replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "__", with: "")
                    .replacingOccurrences(of: "`", with: "")
                return line
            }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OllamaClient: Sendable {
    private let transport: any OllamaTransport

    init(transport: any OllamaTransport = URLSessionOllamaTransport()) {
        self.transport = transport
    }

    /// Checks the configured server without sending wardrobe data or running inference.
    func verifyConnection(configuration: OllamaConfiguration) async throws -> String {
        guard let url = configuration.tagsURL else { throw OllamaError.notConfigured }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await transport.send(request)
        guard let http = response as? HTTPURLResponse else { throw OllamaError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(OllamaErrorResponse.self, from: data).error) ?? "Request failed"
            let server = http.value(forHTTPHeaderField: "Server") ?? "unknown server"
            throw OllamaError.server(statusCode: http.statusCode, message: "\(message) at \(url.absoluteString) [\(server)]")
        }
        let models = try JSONDecoder().decode(OllamaTagsResponse.self, from: data).models
        guard models.contains(where: { $0.name == configuration.model || $0.model == configuration.model }) else {
            throw OllamaError.modelUnavailable(configuration.model)
        }
        return "Connected to Ollama • \(configuration.model) is ready"
    }

    func reply(to requestText: String, configuration: OllamaConfiguration, wardrobeContext: String) async throws -> String {
        guard let url = configuration.chatURL else { throw OllamaError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(OllamaChatRequest(
            model: configuration.model,
            stream: false,
            messages: [
                .init(role: "system", content: "You are ootd.ai, a concise, practical wardrobe stylist. Use only the supplied wardrobe context and never claim an item is owned unless it appears there. Recommend 1–3 named owned-item outfits with a short rationale grounded in color, formality, layering, season, occasion, or recent wear, plus one alternative when useful. Do not reveal private chain-of-thought, invent facts, or record wear; the app asks for confirmation separately. Return plain text only: no Markdown, no bullets, no asterisks, no code fences. Structure the answer with short uppercase section labels ending in a colon, such as BEST PICK:, WHY IT WORKS:, ALTERNATIVE:, and NEXT STEP:."),
                .init(role: "user", content: "Wardrobe context:\n\(wardrobeContext)\n\nRequest: \(requestText)")
            ]
        ))

        let (data, response) = try await transport.send(request)
        guard let http = response as? HTTPURLResponse else { throw OllamaError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(OllamaErrorResponse.self, from: data).error) ?? "Request failed"
            throw OllamaError.server(statusCode: http.statusCode, message: message)
        }
        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        let text = StylistResponseFormatter.clean(decoded.message.content)
        guard !text.isEmpty else { throw OllamaError.invalidResponse }
        return text
    }
}

private struct OllamaChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let stream: Bool
    let messages: [Message]
}

private struct OllamaChatResponse: Decodable {
    struct Message: Decodable { let content: String }
    let message: Message
}

private struct OllamaErrorResponse: Decodable { let error: String }
private struct OllamaTagsResponse: Decodable {
    struct Model: Decodable { let name: String; let model: String? }
    let models: [Model]
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
    private let store: WardrobeStore
    private let voiceRuntime: any VoiceRuntimeSubmitting
    private let ollama: OllamaClient
    private var responseTask: Task<Void, Never>?
    private var activeResponseID: UUID?

    init(store: WardrobeStore, voiceRuntime: any VoiceRuntimeSubmitting = UnqualifiedVoiceRuntime(), ollama: OllamaClient = OllamaClient()) {
        self.store = store
        toolbox = StylistToolbox(store: store)
        self.voiceRuntime = voiceRuntime
        self.ollama = ollama
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
            let response = await self.response(for: request)
            await self.stream(response, responseID: responseID)
        }
    }

    func cancel() {
        responseTask?.cancel()
        activeResponseID = nil
        responseTask = nil
        isResponding = false
    }

    func sendVoice(_ recording: VoiceRecording) async {
        guard !isResponding else { return }
        messages.append(.init(role: .user, text: "Voice request (\(Int(recording.duration.rounded())) seconds)"))
        isResponding = true
        defer { isResponding = false }
        do {
            let response = try await voiceRuntime.submit(audio: recording)
            messages.append(.init(role: .assistant, text: response))
        } catch {
            messages.append(.init(role: .assistant, text: error.localizedDescription))
        }
        try? FileManager.default.removeItem(at: recording.url)
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

    private func response(for request: String) async -> String {
        let configuration = OllamaConfiguration.saved()
        guard configuration.isConfigured else { return localResponse(for: request) }
        do {
            return try await ollama.reply(
                to: request,
                configuration: configuration,
                wardrobeContext: wardrobeContext()
            )
        } catch is CancellationError {
            return ""
        } catch {
            // The local responder keeps core wardrobe actions useful during a
            // transient server outage, while making the source unambiguous.
            return "Gemma 4 is unavailable (\(error.localizedDescription)). \(localResponse(for: request))"
        }
    }

    private func localResponse(for request: String) -> String {
        if request.localizedCaseInsensitiveContains("recent") || request.localizedCaseInsensitiveContains("wore") {
            return wearSummary()
        } else if request.localizedCaseInsensitiveContains("plan") || request.localizedCaseInsensitiveContains("calendar") {
            return contextSummary()
        } else if Self.isRecommendationRequest(request) {
            return recommendationSummary()
        }
        return searchSummary(for: Self.searchTerms(from: request))
    }

    private func wardrobeContext() -> String {
        let garments = store.allGarments.prefix(40).map { item -> String in
            let classification = item.classification?.suggestion
            var details: [String] = [item.name, item.category]
            Self.append(item.color, to: &details)
            if let classification {
                Self.append(classification.garmentType, to: &details)
                Self.append(classification.colorFamily, to: &details)
                Self.append(classification.materialGuess, to: &details)
                Self.append(classification.pattern, to: &details)
                Self.append(classification.texture, to: &details)
                Self.append(classification.silhouette, to: &details)
                Self.append(classification.fit, to: &details)
                Self.append(classification.formality, to: &details)
                Self.append(classification.layering, to: &details)
                Self.append(classification.warmth, to: &details)
                details.append(contentsOf: classification.seasons)
                details.append(contentsOf: classification.occasions)
                details.append(contentsOf: classification.styleKeywords)
                details.append(contentsOf: classification.pairingNotes)
            }
            details.append(contentsOf: item.tags)
            let cleanedDetails = details.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return cleanedDetails.filter { !$0.isEmpty }.joined(separator: " — ")
        }
        let upcoming = store.outfitPlans
            .filter { $0.scheduledFor >= Date() }
            .sorted { $0.scheduledFor < $1.scheduledFor }
            .prefix(5)
            .map { "\($0.occasion ?? "Unspecified occasion") on \($0.scheduledFor.formatted(date: .abbreviated, time: .omitted))" }
        return "Owned garments: \(garments.isEmpty ? "none recorded" : garments.joined(separator: "; "))\nUpcoming plans: \(upcoming.isEmpty ? "none" : upcoming.joined(separator: "; "))"
    }

    private static func append(_ value: String?, to details: inout [String]) {
        guard let value else { return }
        details.append(value)
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
        guard !response.isEmpty, !Task.isCancelled, activeResponseID == responseID else { return }
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
    @StateObject private var voice = VoiceInput()
    @AppStorage(OllamaConfiguration.endpointKey) private var ollamaEndpoint = ""
    @AppStorage(OllamaConfiguration.modelKey) private var ollamaModel = OllamaConfiguration.defaultModel

    init(store: WardrobeStore) {
        self.store = store
        _chat = StateObject(wrappedValue: StylistChat(store: store))
    }

    var body: some View {
        Section("Remote AI") {
            TextField("Ollama server URL", text: $ollamaEndpoint)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityIdentifier("ollama-endpoint")
            TextField("Model", text: $ollamaModel)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("ollama-model")
            let configuration = OllamaConfiguration(endpointText: ollamaEndpoint, model: ollamaModel)
            if ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Gemma 4 is the default once you enter your remote Ollama server URL. Until then, the stylist uses its offline wardrobe rules.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if configuration.isConfigured {
                IconoirLabel(title: "Gemma 4 is the preferred stylist responder.", icon: .network)
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                IconoirLabel(title: "Enter a full HTTP(S) server URL, such as https://ollama.example.net.", icon: .warningTriangle)
                    .font(.footnote).foregroundStyle(WardrobeDesign.Color.quiet)
            }
        }

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
            HStack {
                Button(voice.isRecording ? "Recording…" : "Hold to talk", action: {})
                .onLongPressGesture(minimumDuration: 0.1, maximumDistance: 50, pressing: { pressing in
                    if pressing {
                        Task { await voice.begin() }
                    } else if let recording = voice.finish() {
                        Task { await chat.sendVoice(recording) }
                    }
                }, perform: {})
                .disabled(chat.isResponding)
                .accessibilityHint("Press and hold to record a voice request. Release to send it to the local runtime.")
                if voice.isRecording {
                    Button("Cancel voice") { voice.cancel() }
                }
            }
            if let status = voice.statusMessage {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
            if !store.outfits.isEmpty {
                Menu("Record wear…") {
                    ForEach(store.outfits) { outfit in
                        Button(outfit.name) { chat.requestWear(for: outfit) }
                    }
                }
            }
            Text("The remote stylist receives only the wardrobe names, categories, colors, and upcoming in-app plans needed to answer. It cannot record wear until you confirm a saved outfit.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .confirmationDialog("Record this outfit as worn today?", isPresented: Binding(get: { chat.pendingWearOutfit != nil }, set: { if !$0 { chat.dismissWearConfirmation() } }), titleVisibility: .visible) {
            Button("Wear today") { chat.confirmWear() }
            Button("Cancel", role: .cancel) { chat.dismissWearConfirmation() }
        } message: {
            Text(chat.pendingWearOutfit?.name ?? "")
        }
        .onDisappear { voice.cleanup() }
    }
}
