import Foundation
import Combine

enum WardrobeStoreError: LocalizedError {
    case imageStorageUnavailable

    var errorDescription: String? {
        switch self {
        case .imageStorageUnavailable: "Photo storage is unavailable. Your garment was not saved. Try again after freeing device storage or restarting the app."
        }
    }
}

@MainActor
final class WardrobeStore: ObservableObject {
    @Published private(set) var items: [GarmentItem] = []
    @Published private(set) var errorMessage: String?
    @Published var searchText = "" { didSet { loadItems() } }
    @Published var selectedCategory: String? { didSet { loadItems() } }
    @Published var selectedTag: String? { didSet { loadItems() } }

    let repository: WardrobeRepository
    private let imageCoordinator: GarmentImageCoordinator?

    init(repository: WardrobeRepository, imageStore: WardrobeImageStore? = nil) {
        self.repository = repository
        self.imageCoordinator = imageStore.map { GarmentImageCoordinator(repository: repository, imageStore: $0) }
        loadItems()
    }

    var availableTags: [String] {
        Array(Set(items.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func item(id: UUID) -> GarmentItem? {
        try? repository.item(id: id)
    }

    func loadItems() {
        do {
            items = try repository.items(matching: searchText, category: selectedCategory, tag: selectedTag)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ item: GarmentItem?, imageData: Data? = nil) throws {
        if let item {
            if let imageData {
                guard let imageCoordinator else { throw WardrobeStoreError.imageStorageUnavailable }
                _ = try imageCoordinator.updateItem(item, replacingImageWith: imageData)
            } else {
                _ = try repository.updateItem(item)
            }
        }
        loadItems()
    }

    func create(_ draft: GarmentDraft) throws {
        _ = try repository.createItem(draft)
        loadItems()
    }

    func create(_ draft: GarmentDraft, imageData: Data?) throws {
        if let imageData {
            guard let imageCoordinator else { throw WardrobeStoreError.imageStorageUnavailable }
            _ = try imageCoordinator.createItem(draft, imageData: imageData)
        } else {
            _ = try repository.createItem(draft)
        }
        loadItems()
    }

    func replaceImage(for item: GarmentItem, with imageData: Data) throws -> GarmentItem {
        guard let imageCoordinator else { throw WardrobeStoreError.imageStorageUnavailable }
        let updated = try imageCoordinator.replaceImage(for: item.id, with: imageData)
        loadItems()
        return updated
    }

    func imageData(for item: GarmentItem) -> Data? {
        guard let path = item.imagePath, let imageCoordinator else { return nil }
        return try? imageCoordinator.imageData(at: path)
    }

    func delete(_ item: GarmentItem) throws {
        if let imageCoordinator { try imageCoordinator.deleteItem(id: item.id) }
        else { try repository.deleteItem(id: item.id) }
        loadItems()
    }
}
