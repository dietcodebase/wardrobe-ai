import SwiftUI
import UIKit

/// Shared visual tokens for the assistant surface, adapted from Cornholio's
/// quiet ink/paper/signal system and kept native to iOS.
private enum WardrobeDesign {
    enum Color {
        static let ink = SwiftUI.Color(red: 0.10, green: 0.10, blue: 0.09)
        static let paper = SwiftUI.Color(red: 0.98, green: 0.97, blue: 0.94)
        static let canvas = SwiftUI.Color(uiColor: .systemGroupedBackground)
        static let card = SwiftUI.Color(uiColor: .secondarySystemGroupedBackground)
        static let signal = SwiftUI.Color(red: 0.78, green: 0.25, blue: 0.15)
        static let moss = SwiftUI.Color(red: 0.22, green: 0.38, blue: 0.28)
        static let quiet = SwiftUI.Color(red: 0.38, green: 0.37, blue: 0.34)
        static let hairline = SwiftUI.Color.black.opacity(0.10)
    }
    enum Space {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }
    enum Radius { static let chip: CGFloat = 12; static let card: CGFloat = 20 }
    static func display(_ size: CGFloat = 26) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static func body(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .regular, design: .rounded) }
    static func metadata(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .semibold, design: .monospaced) }
}

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
    @State private var isTaggingDemo = false
    @State private var demoStatus: String?

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
        .navigationTitle("Wardrobe AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Your wardrobe", action: showWardrobe)
                    Button("Saved outfits", action: showOutfits)
                    Button("Add a garment", action: showAddGarment)
                    Divider()
                    Button("Load photo demo", action: loadDemoWardrobe)
                    Button("Tag stored photos with Gemma", action: tagDemoWardrobe)
                        .disabled(isTaggingDemo || !OllamaConfiguration.saved().isConfigured)
                    Divider()
                    Button("Local AI status", action: showModelStatus)
                } label: {
                    Label("Wardrobe actions", systemImage: "square.grid.2x2")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
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
                Image(systemName: "sparkles")
                    .font(WardrobeDesign.display(18))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(WardrobeDesign.Color.ink.gradient, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wardrobe, understood").font(WardrobeDesign.display(20))
                    Text(connectionLabel).font(WardrobeDesign.metadata()).foregroundStyle(WardrobeDesign.Color.quiet)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Label("\(store.allGarments.count) pieces", systemImage: "tshirt")
                Divider().frame(height: 14)
                Label("Ask, compare, decide", systemImage: "arrow.triangle.branch")
            }
            .font(WardrobeDesign.metadata())
            .foregroundStyle(WardrobeDesign.Color.quiet)
        }
        .padding(WardrobeDesign.Space.lg)
        .background(WardrobeDesign.Color.paper, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
    }

    private var connectionLabel: String {
        OllamaConfiguration.saved().isConfigured ? "Gemma 4 is ready to help" : "Private wardrobe context • offline fallback ready"
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Start with your moment.")
                .font(WardrobeDesign.display(25))
            Text("Tell me the occasion, weather, mood, or a piece you want to wear. I’ll compare only what you own and explain the choice in plain language.")
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                PromptChip("Work today", icon: "briefcase") { ask("Suggest an outfit for work today and explain why it works") }
                PromptChip("Weekend plans", icon: "figure.walk") { ask("Build a relaxed weekend outfit from what I own") }
                PromptChip("Dress around a piece", icon: "tshirt") { ask("What can I wear with one of my favorite pieces?") }
                PromptChip("Find a gap", icon: "magnifyingglass") { ask("What kinds of occasions is my wardrobe best prepared for?") }
            }
            if store.allGarments.isEmpty {
                HStack {
                    Button("Load 13 demo photos") { loadDemoWardrobe() }
                        .buttonStyle(.borderedProminent)
                    Button("Add a garment", action: showAddGarment)
                        .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 10) {
                    Button(isTaggingDemo ? "Gemma is tagging…" : "Auto-tag photos with Gemma") { tagDemoWardrobe() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isTaggingDemo || !OllamaConfiguration.saved().isConfigured)
                    if isTaggingDemo { ProgressView().controlSize(.small) }
                }
                if !OllamaConfiguration.saved().isConfigured {
                    Text("Add your Ollama URL in Assistant settings to run Gemma vision tagging.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let demoStatus {
                Text(demoStatus).font(.footnote).foregroundStyle(.secondary)
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
            Label("Add a few garments and I’ll make owned-item outfit ideas.", systemImage: "tshirt")
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
                    try? store.saveSuggestion(suggestion)
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
                    Image(systemName: "arrow.up").fontWeight(.bold)
                }
                .buttonStyle(.borderedProminent)
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

    private func loadDemoWardrobe() {
        do {
            try store.installDemoWardrobe()
            guard OllamaConfiguration.saved().isConfigured else {
                demoStatus = "13 demo photos are ready. Add your Ollama URL to enrich them with Gemma."
                return
            }
            demoStatus = "13 demo photos are ready. Gemma is enriching their tags…"
            tagDemoWardrobe()
        } catch {
            demoStatus = error.localizedDescription
        }
    }

    private func tagDemoWardrobe() {
        guard !isTaggingDemo else { return }
        isTaggingDemo = true
        demoStatus = "Gemma is reviewing each stored garment photo…"
        Task {
            do {
                let count = try await store.tagDemoWardrobe()
                demoStatus = "Gemma enriched " + String(count) + " demo photo" + (count == 1 ? "" : "s") + " with editable attributes."
            } catch is CancellationError {
                demoStatus = "Gemma tagging was cancelled. Existing tags are kept."
            } catch {
                demoStatus = error.localizedDescription
            }
            isTaggingDemo = false
        }
    }
}

private struct MessageBubble: View {
    let message: StylistChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            Text(message.text)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .background(message.role == .user ? WardrobeDesign.Color.ink : WardrobeDesign.Color.card, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
            if message.role == .assistant { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.role == .user ? "You: \(message.text)" : "Stylist: \(message.text)")
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
                Image(systemName: "sparkles")
                    .foregroundStyle(WardrobeDesign.Color.signal)
                Text(suggestion.explanation)
                    .font(WardrobeDesign.body(14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: WardrobeDesign.Space.sm) {
                Button(action: save) {
                    Label("Save outfit", systemImage: "bookmark")
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
                    Image(systemName: symbol)
                        .font(.title2)
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

    private var symbol: String {
        switch item.category {
        case "Shoes": return "shoeprints.fill"
        case "Accessory": return "bag.fill"
        case "Outerwear": return "jacket.fill"
        case "Bottom": return "rectangle.portrait"
        default: return "tshirt.fill"
        }
    }
}

private struct PromptChip: View {
    let title: String
    let icon: String
    let action: () -> Void

    init(_ title: String, icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 9)
        }
        .buttonStyle(.bordered)
    }
}

private struct AssistantSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OllamaConfiguration.endpointKey) private var endpoint = ""
    @AppStorage(OllamaConfiguration.modelKey) private var model = OllamaConfiguration.defaultModel
    @State private var connectionStatus: String?
    @State private var isTestingConnection = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Remote Ollama") {
                    TextField("Server URL", text: $endpoint)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Model", text: $model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button {
                        testConnection()
                    } label: {
                        if isTestingConnection {
                            HStack { ProgressView(); Text("Checking connection…") }
                        } else {
                            Label("Test Ollama connection", systemImage: "network")
                        }
                    }
                    .disabled(isTestingConnection)
                    if let connectionStatus {
                        Text(connectionStatus)
                            .font(.footnote)
                            .foregroundStyle(connectionStatus.hasPrefix("Connected") ? .green : .red)
                    }
                    Text("Use a reachable HTTP(S) URL. Your wardrobe context is sent only to this configured server.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Assistant settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func testConnection() {
        let configuration = OllamaConfiguration(endpointText: endpoint, model: model)
        isTestingConnection = true
        connectionStatus = nil
        Task {
            defer { isTestingConnection = false }
            do {
                connectionStatus = try await OllamaClient().verifyConnection(configuration: configuration)
            } catch {
                connectionStatus = error.localizedDescription
            }
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
