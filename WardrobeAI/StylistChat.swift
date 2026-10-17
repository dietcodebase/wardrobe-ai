import SwiftUI

enum StylistTool: String, Codable, CaseIterable, Sendable {
    case searchWardrobe
    case recentWear
    case context
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
            return .context(plans: Array(store.outfitPlans.prefix(5)))
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
    private var responseTask: Task<Void, Never>?

    init(store: WardrobeStore) { toolbox = StylistToolbox(store: store) }

    func send(_ input: String) {
        let request = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isResponding else { return }
        messages.append(.init(role: .user, text: request))
        toolbox.resetCallCount()
        isResponding = true
        responseTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isResponding = false }
            let response: String
            if request.localizedCaseInsensitiveContains("recent") || request.localizedCaseInsensitiveContains("wore") {
                response = self.wearSummary()
            } else if request.localizedCaseInsensitiveContains("plan") || request.localizedCaseInsensitiveContains("calendar") {
                response = self.contextSummary()
            } else {
                response = self.searchSummary(for: request)
            }
            await self.stream(response)
        }
    }

    func cancel() {
        responseTask?.cancel()
        responseTask = nil
        isResponding = false
    }

    func requestWear(for outfit: Outfit) { pendingWearOutfit = outfit }

    func confirmWear() {
        guard let outfit = pendingWearOutfit else { return }
        defer { pendingWearOutfit = nil }
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

    private func stream(_ response: String) async {
        messages.append(.init(role: .assistant, text: ""))
        let index = messages.index(before: messages.endIndex)
        for word in response.split(separator: " ") {
            guard !Task.isCancelled else {
                messages.remove(at: index)
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
