import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case wardrobe = "Wardrobe"
    case outfits = "Outfits"
    case stylist = "Stylist"

    var id: String { rawValue }
    var symbol: String { switch self { case .wardrobe: "tshirt"; case .outfits: "square.grid.2x2"; case .stylist: "sparkles" } }
    var message: String { switch self { case .wardrobe: "Your wardrobe starts here"; case .outfits: "Your saved outfits will appear here"; case .stylist: "Your personal stylist is coming soon" } }
}

struct ContentView: View {
    @ObservedObject var store: WardrobeStore
    @ObservedObject var modelManager: ModelManager
    @State private var selectedTab: AppTab = .stylist
    @State private var showingAddGarment = false
    @State private var showingModelStatus = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                WardrobeView(store: store)
            }
            .tabItem { Label("Wardrobe", systemImage: AppTab.wardrobe.symbol) }
            .tag(AppTab.wardrobe)

            NavigationStack {
                OutfitView(store: store)
            }
            .tabItem { Label("Outfits", systemImage: AppTab.outfits.symbol) }
            .tag(AppTab.outfits)

            NavigationStack {
                AssistantConversationView(
                    store: store,
                    showWardrobe: { selectedTab = .wardrobe },
                    showOutfits: { selectedTab = .outfits },
                    showAddGarment: { showingAddGarment = true },
                    showModelStatus: { showingModelStatus = true }
                )
            }
            .tabItem { Label("Stylist", systemImage: AppTab.stylist.symbol) }
            .tag(AppTab.stylist)
        }
        .tint(WardrobeDesign.Color.signal)
        .preferredColorScheme(.dark)
        .font(WardrobeDesign.body())
        .sheet(isPresented: $showingAddGarment) { GarmentEditor(store: store) }
        .sheet(isPresented: $showingModelStatus) {
            NavigationStack { ModelStatusView(manager: modelManager, store: store).navigationTitle("Local AI") }
        }
    }
}

private struct WardrobeView: View {
    @ObservedObject var store: WardrobeStore
    @State private var isAdding = false
    @State private var isBatchCapturing = false
    @State private var isShowingPreferences = false
    @State private var selectedItem: GarmentItem?
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if let error = store.errorMessage {
                    ContentUnavailableView("Couldn’t load wardrobe", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if store.items.isEmpty {
                    ContentUnavailableView {
                        Label(store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No garments yet" : "No matching garments", systemImage: "tshirt")
                    } description: {
                        VStack(spacing: 8) {
                            Text(store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add the first item in your wardrobe." : "Try a different search or clear your filters.")
                            if let message = store.searchModeMessage {
                                Label(message, systemImage: "text.magnifyingglass")
                                    .font(.footnote).foregroundStyle(.secondary)
                                    .accessibilityLabel("Search mode: \(message)")
                            }
                        }
                    } actions: {
                        if store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(spacing: 12) {
                                Button("Add garment") { isAdding = true }.buttonStyle(.borderedProminent)
                                Button("Capture batch") { isBatchCapturing = true }.buttonStyle(.bordered)
                            }
                        }
                    }
                } else {
                    ScrollView {
                        if let message = store.searchModeMessage {
                            Label(message, systemImage: "text.magnifyingglass")
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
                        Label(store.selectedCategory ?? "Category", systemImage: "line.3.horizontal.decrease.circle")
                    }.accessibilityLabel("Filter by category")
                }
                ToolbarItem(placement: .topBarTrailing) { Button { isShowingPreferences = true } label: { Label("Style profile", systemImage: "person.crop.circle") } }
                ToolbarItem(placement: .topBarTrailing) { Button { isBatchCapturing = true } label: { Label("Capture batch", systemImage: "rectangle.3.group") } }
                ToolbarItem(placement: .topBarTrailing) { Button { isAdding = true } label: { Label("Add garment", systemImage: "plus") } }
            }
            .safeAreaInset(edge: .bottom) { if !store.availableTags.isEmpty { TagFilter(tags: store.availableTags, selected: $store.selectedTag) } }
            .sheet(isPresented: $isAdding) { GarmentEditor(store: store) }
            .sheet(isPresented: $isBatchCapturing) { BatchGarmentCaptureSheet(store: store) }
            .sheet(item: $selectedItem) { item in GarmentDetail(item: item, store: store) }
            .sheet(isPresented: $isShowingPreferences) { StyleProfileEditor(store: store) }
        }
    }
}

private struct TagFilter: View {
    let tags: [String]
    @Binding var selected: String?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack {
            Button("All tags") { selected = nil }.buttonStyle(.bordered).tint(selected == nil ? .accentColor : .secondary)
            ForEach(tags, id: \.self) { tag in Button(tag) { selected = tag }.buttonStyle(.bordered).tint(selected == tag ? .accentColor : .secondary) }
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
                else { Image(systemName: "tshirt").font(.largeTitle).foregroundStyle(.secondary) }
            }
            .clipped()
            .task(id: item.imagePath) { image = store.imageData(for: item).flatMap(UIImage.init(data:)) }
            .accessibilityHidden(true)
    }
}
