import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case wardrobe = "Wardrobe"
    case outfits = "Outfits"
    case stylist = "Stylist"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .wardrobe: "tshirt"
        case .outfits: "square.grid.2x2"
        case .stylist: "sparkles"
        }
    }

    var message: String {
        switch self {
        case .wardrobe: "Your wardrobe starts here"
        case .outfits: "Your saved outfits will appear here"
        case .stylist: "Your personal stylist is coming soon"
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    ContentUnavailableView(tab.message, systemImage: tab.symbol)
                        .navigationTitle(tab.rawValue)
                }
                .tabItem { Label(tab.rawValue, systemImage: tab.symbol) }
            }
        }
    }
}
