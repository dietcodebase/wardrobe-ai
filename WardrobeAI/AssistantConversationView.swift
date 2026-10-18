import SwiftUI

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
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Wardrobe AI")
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
                .padding(16)
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
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.indigo.gradient, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text("Your personal stylist").font(.headline)
                Text(connectionLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var connectionLabel: String {
        OllamaConfiguration.saved().isConfigured ? "Gemma 4 is ready to help" : "Private wardrobe context • offline fallback ready"
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What are you dressing for?")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Ask naturally. I’ll only recommend pieces from your wardrobe, and I’ll keep wear logging separate from a suggestion.")
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 8) {
                PromptChip("Dress me for work", icon: "briefcase") { ask("Dress me for work") }
                PromptChip("What should I wear today?", icon: "sun.max") { ask("What should I wear today?") }
                PromptChip("Build a weekend outfit", icon: "figure.walk") { ask("Build a weekend outfit") }
                PromptChip("Find something blue", icon: "magnifyingglass") { ask("Find something blue") }
            }
            if store.allGarments.isEmpty {
                Button("Add your first garment", action: showAddGarment)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
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
            Text("Owned-item ideas").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(suggestions) { suggestion in
                VStack(alignment: .leading, spacing: 6) {
                    Text(suggestion.itemIDs.compactMap { store.item(id: $0)?.name }.joined(separator: " + "))
                        .font(.headline)
                    Text(suggestion.explanation).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about your wardrobe", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
}

private struct MessageBubble: View {
    let message: StylistChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            Text(message.text)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .background(message.role == .user ? Color.indigo : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if message.role == .assistant { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.role == .user ? "You: \(message.text)" : "Stylist: \(message.text)")
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Remote Ollama") {
                    TextField("Server URL", text: $endpoint)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Model", text: $model)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Use a reachable HTTP(S) URL. Your wardrobe context is sent only to this configured server.")
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
