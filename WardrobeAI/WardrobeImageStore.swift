import Foundation

struct WardrobeImageStore {
    enum ImageStoreError: Error, Equatable {
        case invalidRelativePath
    }

    private let rootURL: URL
    private let fileManager: FileManager

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    static func applicationSupport(fileManager: FileManager = .default) throws -> WardrobeImageStore {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return WardrobeImageStore(rootURL: applicationSupport.appending(path: "WardrobeAI"), fileManager: fileManager)
    }

    func store(_ data: Data, fileExtension: String = "jpg") throws -> String {
        let relativePath = "images/\(UUID().uuidString.lowercased()).\(fileExtension)"
        let destination = try url(for: relativePath)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return relativePath
    }

    func data(at relativePath: String) throws -> Data? {
        let url = try url(for: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func remove(_ relativePath: String) throws {
        let url = try url(for: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    @discardableResult
    func recoverOrphanedFiles(referencing paths: Set<String>) throws -> [String] {
        let imagesURL = rootURL.appending(path: "images")
        guard fileManager.fileExists(atPath: imagesURL.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(
            at: imagesURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var removed: [String] = []
        for file in files {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relativePath = "images/\(file.lastPathComponent)"
            if !paths.contains(relativePath) {
                try fileManager.removeItem(at: file)
                removed.append(relativePath)
            }
        }
        return removed.sorted()
    }

    private func url(for relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !relativePath.hasPrefix("/") else {
            throw ImageStoreError.invalidRelativePath
        }
        let url = rootURL.appending(path: relativePath).standardizedFileURL
        guard url.path.hasPrefix(rootURL.path + "/") else { throw ImageStoreError.invalidRelativePath }
        return url
    }
}

final class GarmentImageCoordinator {
    private let repository: WardrobeRepository
    private let imageStore: WardrobeImageStore

    init(repository: WardrobeRepository, imageStore: WardrobeImageStore) {
        self.repository = repository
        self.imageStore = imageStore
    }

    func createItem(_ draft: GarmentDraft, imageData: Data? = nil) throws -> GarmentItem {
        var draft = draft
        let newImagePath = try imageData.map { try imageStore.store($0) }
        draft.imagePath = newImagePath ?? draft.imagePath
        do {
            return try repository.createItem(draft)
        } catch {
            if let newImagePath { try? imageStore.remove(newImagePath) }
            throw error
        }
    }

    func replaceImage(for itemID: UUID, with data: Data) throws -> GarmentItem {
        guard var item = try repository.item(id: itemID) else { throw WardrobeRepositoryError.itemNotFound(itemID) }
        let oldImagePath = item.imagePath
        let newImagePath = try imageStore.store(data)
        item.imagePath = newImagePath
        do {
            let updated = try repository.updateItem(item)
            if let oldImagePath { try? imageStore.remove(oldImagePath) }
            return updated
        } catch {
            try? imageStore.remove(newImagePath)
            throw error
        }
    }

    func deleteItem(id: UUID) throws {
        let imagePath = try repository.item(id: id)?.imagePath
        try repository.deleteItem(id: id)
        if let imagePath { try? imageStore.remove(imagePath) }
    }

    func recoverOrphanedImages() throws -> [String] {
        let paths = try Set(repository.allItems().compactMap(\.imagePath))
        return try imageStore.recoverOrphanedFiles(referencing: paths)
    }
}
