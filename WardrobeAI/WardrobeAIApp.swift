import SwiftUI
import GRDB

@main
struct WardrobeAIApp: App {
    @StateObject private var store: WardrobeStore
    @StateObject private var modelManager: ModelManager

    init() {
        let directory = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = directory?.appending(path: "WardrobeAI/wardrobe.sqlite") ?? FileManager.default.temporaryDirectory.appending(path: "wardrobe.sqlite")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let database = Self.openDatabase(at: url)
        let imageStore = try? WardrobeImageStore.applicationSupport()
        _store = StateObject(wrappedValue: WardrobeStore(repository: WardrobeRepository(database: database), imageStore: imageStore))
        _modelManager = StateObject(wrappedValue: ModelManager())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, modelManager: modelManager)
        }
    }

    private static func openDatabase(at url: URL) -> DatabaseQueue {
        if let database = try? WardrobeDatabase.makeQueue(at: url) { return database }
        // A damaged or unavailable Application Support directory must not turn
        // into a launch crash. Keep the app usable for this session instead.
        if let database = try? WardrobeDatabase.makeInMemoryQueue() { return database }
        fatalError("Unable to initialize the local wardrobe database.")
    }
}
