import Foundation

@MainActor
final class WardrobeStore: ObservableObject {
    @Published private(set) var items: [GarmentItem] = []
    @Published private(set) var errorMessage: String?
    @Published var searchText = "" { didSet { loadItems() } }
    @Published var selectedCategory: String? { didSet { loadItems() } }
    @Published var selectedTag: String? { didSet { loadItems() } }

    let repository: WardrobeRepository

    init(repository: WardrobeRepository) {
        self.repository = repository
        loadItems()
    }

    var availableTags: [String] {
        Array(Set(items.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func loadItems() {
        do {
            items = try repository.items(matching: searchText, category: selectedCategory, tag: selectedTag)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ item: GarmentItem?) throws {
        if let item {
            _ = try repository.updateItem(item)
        }
        loadItems()
    }

    func create(_ draft: GarmentDraft) throws {
        _ = try repository.createItem(draft)
        loadItems()
    }

    func delete(_ item: GarmentItem) throws {
        try repository.deleteItem(id: item.id)
        loadItems()
    }
}
