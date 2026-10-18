import XCTest
import UIKit
@testable import WardrobeAI

final class BatchGarmentCaptureTests: XCTestCase {
    func testQueueClassifiesOneImageAtATimeAndContinuesAfterFailure() async throws {
        let classifier = RecordingClassifier(outcomes: [.success("Top"), .failure])
        let queue = BatchGarmentClassificationQueue(classifier: GarmentClassificationCoordinator(classifier: classifier))
        let results = await queue.classify([makeEntry(), makeEntry()]) { _, _ in }

        let maximumConcurrentRequests = await classifier.maximumConcurrentRequests
        let requestCount = await classifier.requestCount
        XCTAssertEqual(maximumConcurrentRequests, 1)
        XCTAssertEqual(requestCount, 2)
        guard case .succeeded = results[0].state else { return XCTFail("Expected first crop to succeed") }
        guard case .failed = results[1].state else { return XCTFail("Expected second crop to retain its error") }
    }

    func testDraftFactoryPreservesValidatedSuggestionAndHasManualFallback() throws {
        let suggestion = try GarmentClassificationSuggestion(category: "Top", color: "Navy", tags: ["work"])
        let provenance = ClassificationProvenance(modelID: "test", modelRevision: "1", route: "test", classifiedAt: .now, suggestion: suggestion, wasEditedBeforeSave: false)
        let classified = BatchClassificationEntry(candidate: makeCandidate(), state: .succeeded(provenance))

        XCTAssertEqual(BatchGarmentDraftFactory.draft(for: classified, ordinal: 2).name, "Top 2")
        XCTAssertEqual(BatchGarmentDraftFactory.draft(for: classified, ordinal: 2).tags, ["work"])
        XCTAssertEqual(BatchGarmentDraftFactory.draft(for: makeEntry(), ordinal: 3).name, "Garment 3")
    }

    private func makeEntry() -> BatchClassificationEntry { BatchClassificationEntry(candidate: makeCandidate()) }

    private func makeCandidate() -> GarmentCaptureCandidate {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return GarmentCaptureCandidate(kind: .foreground, image: image, data: image.pngData()!, swatch: AverageSwatch(red: 0, green: 0, blue: 1))
    }
}

private actor RecordingClassifier: GarmentClassifying {
    enum Outcome { case success(String), failure }
    private var outcomes: [Outcome]
    private(set) var requestCount = 0
    private(set) var maximumConcurrentRequests = 0
    private var activeRequests = 0

    init(outcomes: [Outcome]) { self.outcomes = outcomes }

    func classify(imageData: Data) async throws -> ClassificationProvenance {
        requestCount += 1; activeRequests += 1
        maximumConcurrentRequests = max(maximumConcurrentRequests, activeRequests)
        defer { activeRequests -= 1 }
        try await Task.sleep(for: .milliseconds(10))
        switch outcomes.removeFirst() {
        case let .success(category):
            let suggestion = try GarmentClassificationSuggestion(category: category)
            return ClassificationProvenance(modelID: "test", modelRevision: "1", route: "test", classifiedAt: .now, suggestion: suggestion, wasEditedBeforeSave: false)
        case .failure: throw GarmentClassificationError.unavailable
        }
    }
}
