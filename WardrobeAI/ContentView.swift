import SwiftUI
import Iconoir

struct IconoirIcon: View {
    let icon: Iconoir
    let size: CGFloat

    init(_ icon: Iconoir, size: CGFloat = 18) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        icon.asImage
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct IconoirLabel: View {
    let title: String
    let icon: Iconoir

    var body: some View {
        HStack(spacing: 7) {
            IconoirIcon(icon, size: 16)
            Text(title)
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case wardrobe = "Wardrobe"
    case looks = "Looks"

    var id: String { rawValue }
    var symbol: String { switch self { case .today: "sparkles"; case .wardrobe: "tshirt"; case .looks: "square.grid.2x2" } }
    var message: String { switch self { case .today: "Plan a look from what you own"; case .wardrobe: "Your wardrobe starts here"; case .looks: "Your saved looks and plans live here" } }
}

struct ContentView: View {
    @ObservedObject var store: WardrobeStore
    @ObservedObject var modelManager: ModelManager
    @State private var selectedTab: AppTab = .today
    @State private var showingAddGarment = false
    @State private var showingModelStatus = false
    @State private var showingStylist = false
    @State private var showingAISettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView(
                    store: store,
                    showWardrobe: { selectedTab = .wardrobe },
                    showLooks: { selectedTab = .looks },
                    addGarment: { showingAddGarment = true },
                    askStylist: { showingStylist = true },
                    configureOllama: { showingAISettings = true }
                )
            }
            .tabItem { Label { Text("Today") } icon: { IconoirIcon(.sparks, size: 16) } }
            .tag(AppTab.today)

            NavigationStack {
                WardrobeView(store: store)
            }
            .tabItem { Label { Text("Wardrobe") } icon: { IconoirIcon(.shirt, size: 16) } }
            .tag(AppTab.wardrobe)

            NavigationStack {
                OutfitView(store: store)
            }
            .tabItem { Label { Text("Looks") } icon: { IconoirIcon(.viewGrid, size: 16) } }
            .tag(AppTab.looks)
        }
        .tint(WardrobeDesign.Color.signal)
        .preferredColorScheme(.dark)
        .font(WardrobeDesign.body())
        .sheet(isPresented: $showingAddGarment) { GarmentEditor(store: store) }
        .sheet(isPresented: $showingModelStatus) {
            NavigationStack { ModelStatusView(manager: modelManager, store: store).navigationTitle("Local AI") }
        }
        .sheet(isPresented: $showingStylist) {
            NavigationStack {
                AssistantConversationView(
                    store: store,
                    showWardrobe: { showingStylist = false; selectedTab = .wardrobe },
                    showOutfits: { showingStylist = false; selectedTab = .looks },
                    showAddGarment: { showingStylist = false; showingAddGarment = true },
                    showModelStatus: { showingStylist = false; showingModelStatus = true }
                )
            }
        }
        .sheet(isPresented: $showingAISettings) { AssistantSettingsView() }
    }
}

private struct TodayView: View {
    @ObservedObject var store: WardrobeStore
    let showWardrobe: () -> Void
    let showLooks: () -> Void
    let addGarment: () -> Void
    let askStylist: () -> Void
    let configureOllama: () -> Void

    @State private var occasion = "Everyday"
    @State private var anchorItemID: UUID?
    @State private var refinedSuggestions: [OutfitSuggestion] = []
    @State private var isRefining = false
    @State private var message: String?

    private var heuristicSuggestions: [OutfitSuggestion] {
        (try? store.recommendations(for: occasion == "Everyday" ? nil : occasion, anchorItemID: anchorItemID)) ?? []
    }

    private var suggestions: [OutfitSuggestion] {
        refinedSuggestions.isEmpty ? heuristicSuggestions : refinedSuggestions
    }

    private var suggestionInputID: String {
        let garments = store.allGarments.map { "\($0.id.uuidString):\($0.updatedAt.timeIntervalSinceReferenceDate)" }.joined(separator: "|")
        let wears = store.wearEvents.map { "\($0.id.uuidString):\($0.wornAt.timeIntervalSinceReferenceDate)" }.joined(separator: "|")
        return [occasion, anchorItemID?.uuidString ?? "none", garments, wears].joined(separator: "#")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WardrobeDesign.Space.lg) {
                header
                if store.allGarments.isEmpty {
                    firstGarment
                } else {
                    lookControls
                    recommendations
                    quickActions
                }
            }
            .padding(WardrobeDesign.Space.md)
        }
        .background(WardrobeDesign.Color.canvas)
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: configureOllama) { IconoirIcon(.settings, size: 20) }
                    .accessibilityLabel("Configure Ollama server")
            }
        }
        .alert("Outfit update", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(message ?? "") }
        .task(id: suggestionInputID) { await refineSuggestions(inputID: suggestionInputID) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dress with less guesswork.")
                .font(WardrobeDesign.display(30))
            Text(store.allGarments.isEmpty ? "Add a few pieces and your wardrobe becomes a useful source of outfit ideas." : "Choose the moment. We’ll build a complete look from the pieces you own.")
                .font(WardrobeDesign.body(16))
                .foregroundStyle(WardrobeDesign.Color.quiet)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WardrobeDesign.Space.lg)
        .background(WardrobeDesign.Color.paper, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
    }

    private var firstGarment: some View {
        VStack(alignment: .leading, spacing: 14) {
            IconoirIcon(.shirt, size: 26).foregroundStyle(WardrobeDesign.Color.signal)
            Text("Start with a piece you wear often.").font(WardrobeDesign.display(22))
            Text("A photo is fastest. You can correct every suggested detail before saving.")
                .foregroundStyle(WardrobeDesign.Color.quiet)
            Button(action: addGarment) {
                IconoirLabel(title: "Add your first garment", icon: .plus).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WardrobeDesign.Color.ink)
            Button("Browse wardrobe", action: showWardrobe).buttonStyle(.bordered)
        }
        .padding(WardrobeDesign.Space.lg)
        .background(WardrobeDesign.Color.card, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
    }

    private var lookControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plan a look").font(WardrobeDesign.display(22))
            Picker("Occasion", selection: $occasion) {
                ForEach(GarmentTaxonomy.occasions, id: \.self) { Text($0) }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Occasion")
            Picker("Start with", selection: $anchorItemID) {
                Text("Any piece").tag(Optional<UUID>.none)
                ForEach(store.allGarments) { item in Text(item.name).tag(Optional(item.id)) }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Garment to wear")
        }
        .padding(WardrobeDesign.Space.md)
        .background(WardrobeDesign.Color.paper, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var recommendations: some View {
        if suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("A few more pieces will unlock a complete look.").font(WardrobeDesign.body(17).weight(.semibold))
                Text("Add tops, bottoms, and footwear so the planner has enough to combine.").foregroundStyle(WardrobeDesign.Color.quiet)
                Button("Add a garment", action: addGarment).buttonStyle(.bordered)
            }
            .padding(WardrobeDesign.Space.md)
            .background(WardrobeDesign.Color.card, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
        } else {
            HStack {
                Text("Your options").font(WardrobeDesign.display(22))
                Spacer()
                if isRefining { ProgressView().controlSize(.small).accessibilityLabel("Refining outfit ideas") }
            }
            ForEach(suggestions.prefix(3)) { suggestion in
                TodaySuggestionCard(suggestion: suggestion, store: store, save: { save(suggestion) }, wear: { wear(suggestion) })
            }
        }
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: askStylist) { IconoirLabel(title: "Ask stylist", icon: .sparks).frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button(action: showLooks) { IconoirLabel(title: "Saved looks", icon: .viewGrid).frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            Button(action: configureOllama) {
                IconoirLabel(title: OllamaConfiguration.saved().isConfigured ? "Ollama server configured" : "Connect an Ollama server", icon: .network)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func save(_ suggestion: OutfitSuggestion) {
        do { _ = try store.saveSuggestion(suggestion); message = "Saved to Looks. You can plan it or record a wear there." }
        catch { message = error.localizedDescription }
    }

    private func wear(_ suggestion: OutfitSuggestion) {
        do { _ = try store.wearSuggestion(suggestion); message = "Recorded as worn today." }
        catch { message = error.localizedDescription }
    }

    @MainActor
    private func refineSuggestions(inputID: String) async {
        if let anchorItemID, store.item(id: anchorItemID) == nil { self.anchorItemID = nil; return }
        let candidates = heuristicSuggestions
        refinedSuggestions = []
        guard !candidates.isEmpty else { return }
        isRefining = true
        defer { if suggestionInputID == inputID { isRefining = false } }
        do {
            let contextOccasion = occasion == "Everyday" ? "unspecified everyday" : occasion
            let anchorContext: String
            if let anchorItemID, let anchor = store.item(id: anchorItemID) {
                anchorContext = "; anchor=\(anchor.name) (\(anchor.category))"
            } else {
                anchorContext = ""
            }
            let context = "occasion=\(contextOccasion)\(anchorContext)"
            let refined = try await OllamaOutfitAdvisor().recommendations(candidates: candidates, items: store.allGarments, context: context)
            guard !Task.isCancelled, suggestionInputID == inputID else { return }
            refinedSuggestions = refined
        } catch {
            // The deterministic planner remains visible when the optional local model is unavailable.
        }
    }
}

private struct TodaySuggestionCard: View {
    let suggestion: OutfitSuggestion
    @ObservedObject var store: WardrobeStore
    let save: () -> Void
    let wear: () -> Void

    private var names: [String] { suggestion.itemIDs.compactMap { store.item(id: $0)?.name } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(names.joined(separator: " · ")).font(WardrobeDesign.body(17).weight(.semibold))
            Text(suggestion.explanation).font(WardrobeDesign.body(14)).foregroundStyle(WardrobeDesign.Color.quiet)
            HStack {
                Button("Save", action: save).buttonStyle(.bordered)
                Button("Wear today", action: wear).buttonStyle(.borderedProminent).tint(WardrobeDesign.Color.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WardrobeDesign.Space.md)
        .background(WardrobeDesign.Color.card, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous).stroke(WardrobeDesign.Color.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Outfit idea: \(names.joined(separator: ", ")). \(suggestion.explanation)")
    }
}

private struct WardrobeView: View {
    @ObservedObject var store: WardrobeStore
    @State private var isAdding = false
    @State private var isPhotoCapture = false
    @State private var isBatchCapturing = false
    @State private var isShowingPreferences = false
    @State private var selectedItem: GarmentItem?
    @State private var captureForEditing: GarmentCaptureCandidate?
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        Group {
            if let error = store.errorMessage {
                ContentUnavailableView {
                    IconoirLabel(title: "Couldn’t load wardrobe", icon: .warningTriangle)
                } description: {
                    Text(error)
                }
            } else if store.items.isEmpty {
                PhotoFirstEmptyState(startPhotoFlow: { isPhotoCapture = true }, startBatch: { isBatchCapturing = true })
            } else {
                ScrollView {
                    Button(action: { isPhotoCapture = true }) {
                        HStack(spacing: WardrobeDesign.Space.sm) {
                            IconoirIcon(.plus, size: 22)
                                .font(.title2.weight(.semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add a garment from a photo").font(WardrobeDesign.body(16).weight(.semibold))
                                Text("We’ll suggest the details, then you review them.").font(WardrobeDesign.body(13)).foregroundStyle(WardrobeDesign.Color.quiet)
                            }
                            Spacer()
                            IconoirIcon(.navArrowRight).foregroundStyle(WardrobeDesign.Color.quiet)
                        }
                        .padding(WardrobeDesign.Space.md)
                        .foregroundStyle(WardrobeDesign.Color.ink)
                        .background(WardrobeDesign.Color.card, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .padding(.top, 8)
                        if let message = store.searchModeMessage {
                IconoirLabel(title: message, icon: .textMagnifyingGlass)
                                .font(.footnote).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top, 8)
                                .accessibilityLabel("Search mode: \(message)")
                        }
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.items) { item in
                            Button { selectedItem = item } label: { GarmentCard(item: item, store: store) }
                                .buttonStyle(.plain).accessibilityLabel("\(item.name), \(item.category)")
                        }
                    }.padding()
                }
            }
        }
        .navigationTitle("Wardrobe")
        .font(WardrobeDesign.body())
        .searchable(text: $store.searchText, prompt: "Search garments, colors, tags, or describe a garment")
        .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu { Button("All categories") { store.selectedCategory = nil }; Divider(); ForEach(GarmentTaxonomy.categories, id: \.self) { category in Button(category) { store.selectedCategory = category } } } label: {
                    IconoirLabel(title: store.selectedCategory ?? "Filter", icon: .filterListCircle)
                    }.accessibilityLabel("Filter by category")
                }
                ToolbarItem(placement: .topBarTrailing) { Button { isShowingPreferences = true } label: { IconoirIcon(.user, size: 20) }.accessibilityLabel("Style profile") }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add from photo") { isPhotoCapture = true }
                        Button("Enter manually") { isAdding = true }
                        Button("Add several photos") { isBatchCapturing = true }
                    } label: { IconoirIcon(.plus, size: 22) }
                    .accessibilityLabel("Add a garment")
                }
        }
        .safeAreaInset(edge: .bottom) { if !store.availableTags.isEmpty { TagFilter(tags: store.availableTags, selected: $store.selectedTag) } }
        .sheet(isPresented: $isAdding) { GarmentEditor(store: store) }
        .sheet(isPresented: $isPhotoCapture) { GarmentCaptureSheet { captureForEditing = $0 } }
        .sheet(item: $captureForEditing) { candidate in GarmentEditor(store: store, initialCapture: candidate) }
        .sheet(isPresented: $isBatchCapturing) { BatchGarmentCaptureSheet(store: store) }
        .sheet(item: $selectedItem) { item in GarmentDetail(item: item, store: store) }
        .sheet(isPresented: $isShowingPreferences) { StyleProfileEditor(store: store) }
    }
}

private struct PhotoFirstEmptyState: View {
    let startPhotoFlow: () -> Void
    let startBatch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WardrobeDesign.Space.lg) {
            Spacer()
            IconoirIcon(.camera, size: 28)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(WardrobeDesign.Color.ink)
                .frame(width: 72, height: 72)
                .background(WardrobeDesign.Color.card, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
            Text("Start with one photo.")
                .font(WardrobeDesign.display(30))
            Text("Upload or take a clear photo of a garment. We’ll propose the details, and you approve them before it enters your wardrobe.")
                .font(WardrobeDesign.body(16))
                .foregroundStyle(WardrobeDesign.Color.quiet)
            Button(action: startPhotoFlow) {
                IconoirLabel(title: "Upload garment photo", icon: .mediaImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WardrobeDesign.Color.ink)
            .foregroundStyle(WardrobeDesign.Color.canvas)
            Button("Add several photos", action: startBatch)
                .buttonStyle(.bordered)
                .tint(WardrobeDesign.Color.quiet)
            Spacer()
        }
        .padding(WardrobeDesign.Space.xl)
    }
}

private struct TagFilter: View {
    let tags: [String]
    @Binding var selected: String?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack {
            Button("All tags") { selected = nil }.buttonStyle(.bordered).tint(selected == nil ? WardrobeDesign.Color.signal : WardrobeDesign.Color.quiet)
            ForEach(tags, id: \.self) { tag in Button(tag) { selected = tag }.buttonStyle(.bordered).tint(selected == tag ? WardrobeDesign.Color.signal : WardrobeDesign.Color.quiet) }
        }.padding(.horizontal).padding(.vertical, 8) }
        .background(WardrobeDesign.Color.paper).accessibilityElement(children: .contain).accessibilityLabel("Filter by tag")
    }
}

private struct GarmentCard: View {
    let item: GarmentItem
    @ObservedObject var store: WardrobeStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GarmentThumbnail(item: item, store: store).frame(height: 132)
            Text(item.name).font(WardrobeDesign.body(16).weight(.semibold)).lineLimit(2)
            Text(item.category.uppercased()).font(WardrobeDesign.metadata(10)).foregroundStyle(WardrobeDesign.Color.quiet)
            if let color = item.color, !color.isEmpty { Text(color).font(WardrobeDesign.body(12)).foregroundStyle(WardrobeDesign.Color.quiet) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(WardrobeDesign.Color.card, in: RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WardrobeDesign.Radius.card, style: .continuous).stroke(WardrobeDesign.Color.hairline))
    }
}

private struct GarmentThumbnail: View {
    let item: GarmentItem
    @ObservedObject var store: WardrobeStore
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 16).fill(WardrobeDesign.Color.canvas)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 16)) }
                else { IconoirIcon(.shirt, size: 34).foregroundStyle(.secondary) }
            }
            .clipped()
            .task(id: item.imagePath) { image = store.imageData(for: item).flatMap(UIImage.init(data:)) }
            .accessibilityHidden(true)
    }
}
