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

    var body: some View {
        TabView {
            WardrobeView(store: store).tabItem { Label(AppTab.wardrobe.rawValue, systemImage: AppTab.wardrobe.symbol) }
            placeholder(for: .outfits).tabItem { Label(AppTab.outfits.rawValue, systemImage: AppTab.outfits.symbol) }
            placeholder(for: .stylist).tabItem { Label(AppTab.stylist.rawValue, systemImage: AppTab.stylist.symbol) }
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
                    ContentUnavailableView { Label("No garments yet", systemImage: "tshirt") } description: { Text("Add the first item in your wardrobe.") } actions: {
                        Button("Add garment") { isAdding = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView { LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.items) { item in
                            Button { selectedItem = item } label: { GarmentCard(item: item) }
                                .buttonStyle(.plain).accessibilityLabel("\\(item.name), \\(item.category)")
                        }
                    }.padding() }
                }
            }
            .navigationTitle("Wardrobe")
            .searchable(text: $store.searchText, prompt: "Search garments, colors, tags")
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
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .tertiarySystemFill)).frame(height: 132)
                .overlay(Image(systemName: "tshirt").font(.largeTitle).foregroundStyle(.secondary)).accessibilityHidden(true)
            Text(item.name).font(.headline).lineLimit(2)
            Text(item.category).font(.subheadline).foregroundStyle(.secondary)
            if let color = item.color, !color.isEmpty { Text(color).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
