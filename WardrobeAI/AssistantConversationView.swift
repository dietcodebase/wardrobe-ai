import SwiftUI
import UIKit
import Iconoir

/// The app's primary surface. The assistant has the conversation, while the
/// wardrobe remains the owned-item source of truth behind every suggestion.
struct AssistantConversationView: View {
    @ObservedObject var store: WardrobeStore
    let showWardrobe: () -> Void
    let showOutfits: () -> Void
    let showAddGarment: () -> Void
    let showModelStatus: () -> Void

    @StateObject private var chat: StylistChat
    @State private var draft = ""
    @State private var showingSettings = false
    @State private var shouldShowIdeas = false

    init(
        store: WardrobeStore,
        showWardrobe: @escaping () -> Void,
        showOutfits: @escaping () -> Void,
        showAddGarment: @escaping () -> Void,
        showModelStatus: @escaping () -> Void
    ) {
        self.store = store
        self.showWardrobe = showWardrobe
        self.showOutfits = showOutfits
        self.showAddGarment = showAddGarment
        self.showModelStatus = showModelStatus
        _chat = StateObject(wrappedValue: StylistChat(store: store))
    }

    private var suggestions: [OutfitSuggestion] {
        (try? store.recommendations(for: nil))?.prefix(2).map { $0 } ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            conversation
            composer
        }
        .background(WardrobeDesign.Color.canvas)
        .navigationTitle("ootd.ai")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Your wardrobe", action: showWardrobe)
                    Button("Saved outfits", action: showOutfits)
                    Button("Add a garment", action: showAddGarment)
                    Divider()
                    Button("Local AI status", action: showModelStatus)
                } label: {
                    IconoirLabel(title: "Wardrobe actions", icon: .viewGrid)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: {
                    IconoirIcon(.settings, size: 20)
                }
                .accessibilityLabel("Assistant settings")
            }
        }
        .sheet(isPresented: $showingSettings) { AssistantSettingsView() }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    header
                    if chat.messages.isEmpty {
                        welcome
                    } else {
                        ForEach(chat.messages) { message in
                            MessageBubble(message: message)
                            if message.role == .assistant, shouldShowIdeas, message.id == chat.messages.last?.id {
                                recommendationCards
                            }
                        }
                    }
                    if chat.isResponding {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Finding a grounded answer…").foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                    }
                }
                .padding(WardrobeDesign.Space.md)
            }
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("conversation-end", anchor: .bottom) }
            }
            .onChange(of: chat.isResponding) { _, _ in
                withAnimation { proxy.scrollTo("conversation-end", anchor: .bottom) }
            }
            .overlay(alignment: .bottom) { Color.clear.frame(height: 1).id("conversation-end") }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconoirIcon(.sparks, size: 20)
                    .font(WardrobeDesign.display(18))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(WardrobeDesign.Color.ink.gradient, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("ootd.ai").font(WardrobeDesign.display(20))
                    Text(connectionLabel).font(WardrobeDesign.metadata()).foregroundStyle(WardrobeDesign.Color.quiet)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                IconoirLabel(title: "\(store.allGarments.count) pieces", icon: .shirt)
                Divider().frame(height: 14)
                IconoirLabel(title: "Ask, compare, decide", icon: .gitBranch)
            }
            .font(WardrobeDesign.metadata())
            .foregroundStyle(WardrobeDesign.Color.quiet)
        }
        .padding(WardrobeDesign.Space.lg)
        .background(WardrobeDesign.Color.paper, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
    }

    private var connectionLabel: String { "Private wardrobe context" }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start with your moment.")
                .font(WardrobeDesign.display(25))
            Text("Tell me the occasion, weather, mood, or a piece you want to wear. I’ll compare only what you own and explain the choice in plain language.")
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                PromptChip("Work today", icon: .suitcase) { ask("Suggest an outfit for work today and explain why it works") }
                PromptChip("Weekend plans", icon: .walking) { ask("Build a relaxed weekend outfit from what I own") }
                PromptChip("Dress around a piece", icon: .shirt) { ask("What can I wear with one of my favorite pieces?") }
                PromptChip("Find a gap", icon: .search) { ask("What kinds of occasions is my wardrobe best prepared for?") }
            }
            if store.allGarments.isEmpty {
                HStack {
                    Button("Add a garment", action: showAddGarment)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Outfit ideas use your saved wardrobe. Gemma responses remain unavailable until the iPhone 17 device check passes.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(WardrobeDesign.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityIdentifier("assistant-welcome")
    }

    @ViewBuilder
    private var recommendationCards: some View {
        if suggestions.isEmpty {
            IconoirLabel(title: "Add a few garments and I’ll make owned-item outfit ideas.", icon: .shirt)
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text("Ready-to-compare")
                    .font(WardrobeDesign.metadata(12))
                    .textCase(.uppercase)
                    .foregroundStyle(WardrobeDesign.Color.quiet)
                Spacer()
                Text("owned pieces")
                    .font(WardrobeDesign.metadata(10))
                    .foregroundStyle(WardrobeDesign.Color.quiet)
            }
            ForEach(suggestions) { suggestion in
                OutfitRecommendationCard(suggestion: suggestion, store: store) {
                    _ = try? store.saveSuggestion(suggestion)
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about your wardrobe", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(WardrobeDesign.Color.paper, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
                .accessibilityIdentifier("assistant-prompt")
            if chat.isResponding {
                Button("Cancel", action: chat.cancel).buttonStyle(.bordered)
            } else {
                Button(action: { ask(draft) }) {
                    IconoirIcon(.arrowUp, size: 16)
                        .foregroundStyle(WardrobeDesign.Color.canvas)
                }
                .buttonStyle(.borderedProminent)
                .tint(WardrobeDesign.Color.ink)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send prompt")
            }
        }
        .padding(12)
        .background(.bar)
    }

    private func ask(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        shouldShowIdeas = Self.isRecommendationPrompt(trimmed)
        chat.send(trimmed)
        draft = ""
    }

    private static func isRecommendationPrompt(_ prompt: String) -> Bool {
        let lowercased = prompt.lowercased()
        return ["wear", "dress", "outfit", "style", "recommend"].contains { lowercased.contains($0) }
    }

}

private struct MessageBubble: View {
    let message: StylistChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            Group {
                if message.role == .assistant {
                    StylistResponseView(text: message.text)
                } else {
                    Text(message.text)
                        .font(WardrobeDesign.body())
                        .foregroundStyle(WardrobeDesign.Color.canvas)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: 430, alignment: .leading)
            .background(message.role == .user ? WardrobeDesign.Color.ink : WardrobeDesign.Color.card, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
            if message.role == .assistant { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.role == .user ? "You: \(message.text)" : "Stylist: \(message.text)")
    }
}

struct StylistResponseView: View {
    struct Section: Identifiable {
        let id = UUID()
        let heading: String?
        let body: String
    }

    let text: String

    private var sections: [Section] {
        var result: [Section] = []
        var heading: String?
        var body: [String] = []
        func flush() {
            let value = body.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { result.append(Section(heading: heading, body: value)) }
            body.removeAll()
        }
        for line in StylistResponseFormatter.clean(text).components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasSuffix(":") && trimmed.count < 42 {
                flush()
                heading = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                body.append(trimmed)
            }
        }
        flush()
        return result.isEmpty ? [Section(heading: nil, body: StylistResponseFormatter.clean(text))] : result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                VStack(alignment: .leading, spacing: 4) {
                    if let heading = section.heading {
                        Text(heading.uppercased())
                            .font(WardrobeDesign.metadata(10))
                            .foregroundStyle(WardrobeDesign.Color.quiet)
                            .tracking(0.7)
                    }
                    Text(section.body)
                        .font(WardrobeDesign.body(15))
                        .foregroundStyle(WardrobeDesign.Color.ink)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 9)
                if index < sections.count - 1 {
                    Divider().overlay(WardrobeDesign.Color.hairline)
                }
            }
        }
    }
}

private struct OutfitRecommendationCard: View {
    let suggestion: OutfitSuggestion
    @ObservedObject var store: WardrobeStore
    let save: () -> Void

    private var items: [GarmentItem] {
        suggestion.itemIDs.compactMap { store.item(id: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WardrobeDesign.Space.md) {
            OutfitPreview(items: items, store: store)

            VStack(alignment: .leading, spacing: WardrobeDesign.Space.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(WardrobeDesign.display(21))
                        .foregroundStyle(WardrobeDesign.Color.ink)
                    Spacer()
                    Text("\(suggestion.score) fit")
                        .font(WardrobeDesign.metadata())
                        .foregroundStyle(WardrobeDesign.Color.moss)
                }
                Text(itemSummary)
                    .font(WardrobeDesign.metadata())
                    .foregroundStyle(WardrobeDesign.Color.quiet)
                    .lineLimit(2)
            }

            HStack(alignment: .top, spacing: WardrobeDesign.Space.sm) {
                IconoirIcon(.sparks, size: 16)
                    .foregroundStyle(WardrobeDesign.Color.signal)
                Text(suggestion.explanation)
                    .font(WardrobeDesign.body(14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: WardrobeDesign.Space.sm) {
                Button(action: save) {
                    IconoirLabel(title: "Save outfit", icon: .bookmark)
                        .foregroundStyle(WardrobeDesign.Color.canvas)
                }
                .buttonStyle(.borderedProminent)
                .tint(WardrobeDesign.Color.ink)
                Text("Save keeps it ready; it never logs wear.")
                    .font(WardrobeDesign.metadata(10))
                    .foregroundStyle(WardrobeDesign.Color.quiet)
            }
        }
        .padding(WardrobeDesign.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WardrobeDesign.Color.paper, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous).stroke(WardrobeDesign.Color.hairline))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
    }

    private var title: String {
        if items.contains(where: { $0.category == "Dress" || $0.category == "One-piece outfit" }) { return "One-piece, finished" }
        if items.contains(where: { $0.category == "Outerwear" }) { return "Layered and ready" }
        return "A considered everyday set"
    }

    private var itemSummary: String {
        items.map { $0.name }.joined(separator: "  ·  ")
    }
}

private struct OutfitPreview: View {
    let items: [GarmentItem]
    @ObservedObject var store: WardrobeStore

    var body: some View {
        HStack(spacing: WardrobeDesign.Space.xs) {
            ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
                GarmentPreviewTile(item: item, store: store, prominence: index == 0 ? .hero : .support)
            }
            if items.count > 4 {
                Text("+\(items.count - 4)")
                    .font(WardrobeDesign.metadata())
                    .foregroundStyle(WardrobeDesign.Color.quiet)
                    .frame(width: 40, height: 92)
                    .background(WardrobeDesign.Color.canvas, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.chip))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GarmentPreviewTile: View {
    enum Prominence { case hero, support }
    let item: GarmentItem
    @ObservedObject var store: WardrobeStore
    let prominence: Prominence
    @State private var image: UIImage?

    private var width: CGFloat { prominence == .hero ? 148 : 82 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    IconoirIcon(icon, size: 28)
                        .foregroundStyle(WardrobeDesign.Color.quiet)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(WardrobeDesign.Color.canvas)
                }
            }
            .frame(width: width, height: 92)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: WardrobeDesign.Radius.chip, style: .continuous))

            Text(item.category)
                .font(WardrobeDesign.metadata(9))
                .foregroundStyle(WardrobeDesign.Color.quiet)
                .lineLimit(1)
        }
        .task(id: item.imagePath) {
            image = store.imageData(for: item).flatMap(UIImage.init(data:))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.category): \(item.name)")
    }

    private var icon: Iconoir {
        switch item.category {
        case "Shoes": return .shirt
        case "Accessory": return .bag
        case "Outerwear": return .shirt
        case "Bottom": return .viewColumns2
        default: return .shirt
        }
    }
}

private struct PromptChip: View {
    let title: String
    let icon: Iconoir
    let action: () -> Void

    init(_ title: String, icon: Iconoir, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            IconoirLabel(title: title, icon: icon).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 9)
        }
        .buttonStyle(.bordered)
    }
}

struct AssistantSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Privacy") {
                    IconoirLabel(title: "Wardrobe requests stay on this phone", icon: .shieldCheck)
                    Text("The stylist currently uses owned-item rules and local history. Gemma responses require physical-device qualification.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Assistant settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + (x == 0 ? 0 : spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
