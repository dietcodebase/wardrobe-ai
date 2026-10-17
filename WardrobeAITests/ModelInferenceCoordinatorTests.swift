import XCTest
@testable import WardrobeAI

final class ModelInferenceCoordinatorTests: XCTestCase {
    func testSwitchingModelsUnloadsBeforeLoadingNextEngine() async throws {
        let loader = RecordingLoader()
        let coordinator = ModelInferenceCoordinator(loader: loader)
        let first = verified(.e2b)
        let second = verified(.embedding)

        _ = try await coordinator.withEngine(for: first) { _ in "first" }
        _ = try await coordinator.withEngine(for: second) { _ in "second" }

        let events = await loader.events()
        XCTAssertEqual(events, ["load:e2b", "unload:e2b", "load:embedding"])
    }

    func testExplicitUnloadReleasesActiveEngine() async throws {
        let loader = RecordingLoader()
        let coordinator = ModelInferenceCoordinator(loader: loader)
        _ = try await coordinator.withEngine(for: verified(.e2b)) { _ in () }
        await coordinator.unload()

        let events = await loader.events()
        XCTAssertEqual(events, ["load:e2b", "unload:e2b"])
    }

    private func verified(_ id: ModelID) -> VerifiedModel {
        let descriptor = ModelDescriptor(id: id, filename: "\(id.rawValue).litertlm", expectedBytes: 1, sha256: "test", downloadURL: URL(string: "https://example.com/\(id.rawValue)")!)
        return VerifiedModel(descriptor: descriptor, fileURL: URL(fileURLWithPath: "/tmp/\(id.rawValue)"), verifiedAt: .now)
    }
}

private actor EventLog {
    private var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func all() -> [String] { values }
}

private final class RecordingLoader: ModelEngineLoading, @unchecked Sendable {
    private let log = EventLog()
    func load(_ model: VerifiedModel) async throws -> any ModelEngine {
        await log.append("load:\(model.descriptor.id.rawValue)")
        return RecordingEngine(id: model.descriptor.id, log: log)
    }
    func events() async -> [String] { await log.all() }
}

private final class RecordingEngine: ModelEngine, @unchecked Sendable {
    let id: ModelID
    let log: EventLog
    init(id: ModelID, log: EventLog) { self.id = id; self.log = log }
    func unload() async { await log.append("unload:\(id.rawValue)") }
}
