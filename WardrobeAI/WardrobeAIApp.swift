import SwiftUI

@main
struct WardrobeAIApp: App {
    @StateObject private var store: WardrobeStore

    init() {
        let directory = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = directory?.appending(path: "WardrobeAI/wardrobe.sqlite") ?? FileManager.default.temporaryDirectory.appending(path: "wardrobe.sqlite")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let database = try! WardrobeDatabase.makeQueue(at: url)
        _store = StateObject(wrappedValue: WardrobeStore(repository: WardrobeRepository(database: database)))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
