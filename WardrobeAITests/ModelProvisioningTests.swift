import Foundation
import XCTest
@testable import WardrobeAI

final class ModelProvisioningTests: XCTestCase {
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
        try Data([0, 1, 2]).write(to: source)
        let descriptor = descriptor(bytes: 3, hash: "valid")
        let store = try ModelStore(rootURL: directory.appending(path: "Models"), verifier: StubVerifier())

        let imported = try store.importVerifiedFile(at: source, as: descriptor)

        XCTAssertEqual(try Data(contentsOf: imported.fileURL), Data([0, 1, 2]))
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
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        let bytes = Int64(values.fileSize ?? 0)
        guard bytes == descriptor.expectedBytes else {
            throw ModelProvisioningError.incorrectSize(expected: descriptor.expectedBytes, actual: bytes)
        }
    }
}
