import Combine
import Foundation
import XCTest
@testable import WardrobeAI

final class ModelProvisioningTests: XCTestCase {
    @MainActor
    func testManagerPublishesNestedTransferUpdatesForStylistView() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ModelStore(rootURL: directory, verifier: StubVerifier())
        let manager = ModelManager(store: store)
        let changed = expectation(description: "Stylist receives transfer change")
        let observation = manager.objectWillChange.sink { changed.fulfill() }
        let model = VerifiedModel(descriptor: descriptor(bytes: 5, hash: "valid"), fileURL: directory.appending(path: "test"), verifiedAt: Date())

        manager.downloads?.recordImported(model)

        wait(for: [changed], timeout: 1)
        XCTAssertEqual(manager.downloads?.statusByModel[.e2b], .available(model))
        withExtendedLifetime(observation) { }
    }

    @MainActor
    func testImportPublishesBusyFailureAndReadyStatesAndRejectsOverlappingActions() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ModelManager(store: try ModelStore(rootURL: directory, verifier: StubVerifier()))
        let downloads = try XCTUnwrap(manager.downloads)
        let descriptor = descriptor(bytes: 5, hash: "valid")
        var changes = 0
        let observation = manager.objectWillChange.sink { changes += 1 }

        XCTAssertTrue(downloads.beginImport(descriptor))
        XCTAssertEqual(downloads.statusByModel[.e2b], .verifying)
        XCTAssertFalse(downloads.beginImport(descriptor))
        downloads.download(descriptor)
        downloads.resume(descriptor)
        XCTAssertEqual(downloads.statusByModel[.e2b], .verifying)
        downloads.recordImportFailure(ModelProvisioningError.incorrectChecksum, descriptor: descriptor)
        XCTAssertEqual(downloads.statusByModel[.e2b], .failed(ModelProvisioningError.incorrectChecksum.localizedDescription))
        XCTAssertTrue(downloads.beginImport(descriptor))
        let model = VerifiedModel(descriptor: descriptor, fileURL: directory.appending(path: "test"), verifiedAt: Date())
        downloads.recordImported(model)
        XCTAssertEqual(downloads.statusByModel[.e2b], .available(model))
        XCTAssertEqual(changes, 4)
        withExtendedLifetime(observation) { }
    }

    func testUnverifiedExistingModelIsRemovedAtStartup() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let descriptor = descriptor(bytes: 3, hash: "valid")
        let store = try ModelStore(rootURL: directory, verifier: StubVerifier())
        try Data([0, 1, 2]).write(to: store.destination(for: descriptor))

        XCTAssertNil(try store.verifiedModel(for: descriptor))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.destination(for: descriptor).path))
    }

    func testImportCopiesOnlyVerifiedFilesAndKeepsSource() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "chosen.litertlm")
        try Data("valid".utf8).write(to: source)
        let descriptor = descriptor(bytes: 5, hash: "valid")
        let store = try ModelStore(rootURL: directory.appending(path: "Models"), verifier: StubVerifier())

        let imported = try store.importVerifiedFile(at: source, as: descriptor)

        XCTAssertEqual(try Data(contentsOf: imported.fileURL), Data("valid".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(try XCTUnwrap(imported.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup))
    }

    func testWrongSizeIsRejectedBeforeImport() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "wrong.litertlm")
        try Data([0, 1]).write(to: source)
        let descriptor = descriptor(bytes: 3, hash: "valid")
        let store = try ModelStore(rootURL: directory.appending(path: "Models"), verifier: StubVerifier())

        XCTAssertThrowsError(try store.importVerifiedFile(at: source, as: descriptor)) { error in
            XCTAssertEqual(error as? ModelProvisioningError, .incorrectSize(expected: 3, actual: 2))
        }
    }

    func testCompletedDownloadIsVerifiedAndMovedWithoutCopyingTheSource() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "completed-download.litertlm")
        try Data("valid".utf8).write(to: source)
        let descriptor = descriptor(bytes: 5, hash: "valid")
        let store = try ModelStore(rootURL: directory.appending(path: "Models"), verifier: StubVerifier())

        let installed = try store.adoptVerifiedDownload(at: source, as: descriptor)

        XCTAssertEqual(try Data(contentsOf: installed.fileURL), Data("valid".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    private func descriptor(bytes: Int64, hash: String) -> ModelDescriptor {
        ModelDescriptor(id: .e2b, filename: "test.litertlm", expectedBytes: bytes, sha256: hash, downloadURL: URL(string: "https://example.com/test")!)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct StubVerifier: ModelFileVerifying {
    func verify(_ fileURL: URL, against descriptor: ModelDescriptor) throws {
        let data = try Data(contentsOf: fileURL)
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        let bytes = Int64(values.fileSize ?? 0)
        guard bytes == descriptor.expectedBytes else {
            throw ModelProvisioningError.incorrectSize(expected: descriptor.expectedBytes, actual: bytes)
        }
        guard String(data: data, encoding: .utf8) == descriptor.sha256 else {
            throw ModelProvisioningError.incorrectChecksum
        }
    }
}
