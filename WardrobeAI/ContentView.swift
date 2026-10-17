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

    var body: some View {
        TabView {
            WardrobeView(store: store).tabItem { Label(AppTab.wardrobe.rawValue, systemImage: AppTab.wardrobe.symbol) }
            OutfitView(store: store).tabItem { Label(AppTab.outfits.rawValue, systemImage: AppTab.outfits.symbol) }
            NavigationStack { ModelStatusView(manager: modelManager, store: store).navigationTitle(AppTab.stylist.rawValue) }
                .tabItem { Label(AppTab.stylist.rawValue, systemImage: AppTab.stylist.symbol) }
        }
    }

    private func placeholder(for tab: AppTab) -> some View {
        NavigationStack { ContentUnavailableView(tab.message, systemImage: tab.symbol).navigationTitle(tab.rawValue) }
    }
}

private struct WardrobeView: View {
    @ObservedObject var store: WardrobeStore
    @State private var isAdding = false
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
                            Button("Add garment") { isAdding = true }.buttonStyle(.borderedProminent)
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
            .searchable(text: $store.searchText, prompt: "Search garments, colors, tags, or describe a garment")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu { Button("All categories") { store.selectedCategory = nil }; Divider(); ForEach(GarmentTaxonomy.categories, id: \.self) { category in Button(category) { store.selectedCategory = category } } } label: {
                        Label(store.selectedCategory ?? "Category", systemImage: "line.3.horizontal.decrease.circle")
                    }.accessibilityLabel("Filter by category")
                }
                ToolbarItem(placement: .topBarTrailing) { Button { isShowingPreferences = true } label: { Label("Style profile", systemImage: "person.crop.circle") } }
                ToolbarItem(placement: .topBarTrailing) { Button { isAdding = true } label: { Label("Add garment", systemImage: "plus") } }
            }
            .safeAreaInset(edge: .bottom) { if !store.availableTags.isEmpty { TagFilter(tags: store.availableTags, selected: $store.selectedTag) } }
            .sheet(isPresented: $isAdding) { GarmentEditor(store: store) }
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
        .background(.bar).accessibilityElement(children: .contain).accessibilityLabel("Filter by tag")
    }
}

private struct GarmentCard: View {
    let item: GarmentItem
    @ObservedObject var store: WardrobeStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GarmentThumbnail(item: item, store: store).frame(height: 132)
            Text(item.name).font(.headline).lineLimit(2)
            Text(item.category).font(.subheadline).foregroundStyle(.secondary)
            if let color = item.color, !color.isEmpty { Text(color).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct GarmentThumbnail: View {
    let item: GarmentItem
    @ObservedObject var store: WardrobeStore
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .tertiarySystemFill))
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 16)) }
                else { Image(systemName: "tshirt").font(.largeTitle).foregroundStyle(.secondary) }
            }
            .clipped()
            .task(id: item.imagePath) { image = store.imageData(for: item).flatMap(UIImage.init(data:)) }
            .accessibilityHidden(true)
    }
}
