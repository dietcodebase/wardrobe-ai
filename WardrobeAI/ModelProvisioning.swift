import CryptoKit
import Foundation

enum ModelID: String, CaseIterable, Identifiable, Sendable {
    case e2b
    case embedding
    case e4b

    var id: String { rawValue }
}

struct ModelDescriptor: Equatable, Sendable, Identifiable {
    let id: ModelID
    let filename: String
    let expectedBytes: Int64
    let sha256: String
    let downloadURL: URL

    static let qualifiedCandidates: [ModelDescriptor] = [
        ModelDescriptor(id: .e2b, filename: "gemma-4-E2B-it-gpu.litertlm", expectedBytes: 2_008_432_640, sha256: "a53a59001894c58e6bdb5b9b227709f91a2e3e556baa7d85acf9c55402ba5cf5", downloadURL: URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1/gemma-4-E2B-it-gpu.litertlm")!),
        ModelDescriptor(id: .embedding, filename: "embeddinggemma-2-740m.litertlm", expectedBytes: 484_622_336, sha256: "e7a8a2204f91e0f96e92960e84a09a89212e1633dcb7575a9bf3378b4df77f4c", downloadURL: URL(string: "https://huggingface.co/litert-community/embeddinggemma-2-740m-litert-lm/resolve/24d962e906c7d332c6428e71c9676855024569e2/embeddinggemma-2-740m.litertlm")!),
        ModelDescriptor(id: .e4b, filename: "gemma-4-E4B-it-gpu.litertlm", expectedBytes: 2_969_059_328, sha256: "4912bb5a9c30993c51a7711f763212077458529312175df0573a78323a2bb7ff", downloadURL: URL(string: "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/2eee7ac325f20eb8c9ac1d0e972f7c84663062da/gemma-4-E4B-it-gpu.litertlm")!)
    ]
}

enum ModelProvisioningError: LocalizedError, Equatable {
    case unknownModel
    case notAFile
    case insufficientDiskSpace(required: Int64, available: Int64)
    case incorrectSize(expected: Int64, actual: Int64)
    case incorrectChecksum
    case missingVerifiedModel
    case downloadInterrupted

    var errorDescription: String? {
        switch self {
        case .unknownModel: "This model is not supported by the pinned runtime manifest."
        case .notAFile: "Choose a model file, not a folder."
        case let .insufficientDiskSpace(required, available): "This model needs \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)) of free space; only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) is available."
        case let .incorrectSize(expected, actual): "The model size is \(ByteCountFormatter.string(fromByteCount: actual, countStyle: .file)), but \(ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)) was expected."
        case .incorrectChecksum: "The model checksum did not match the pinned manifest."
        case .missingVerifiedModel: "No verified model is available. Import or download it again."
        case .downloadInterrupted: "The download was interrupted. You can resume it when a connection is available."
        }
    }
}

struct VerifiedModel: Equatable, Sendable {
    let descriptor: ModelDescriptor
    let fileURL: URL
    let verifiedAt: Date
}

protocol ModelFileVerifying: Sendable {
    func verify(_ fileURL: URL, against descriptor: ModelDescriptor) throws
}

struct SHA256ModelFileVerifier: ModelFileVerifying {
    func verify(_ fileURL: URL, against descriptor: ModelDescriptor) throws {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ModelProvisioningError.notAFile }
        let actualBytes = Int64(values.fileSize ?? 0)
        guard actualBytes == descriptor.expectedBytes else {
            throw ModelProvisioningError.incorrectSize(expected: descriptor.expectedBytes, actual: actualBytes)
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(descriptor.sha256) == .orderedSame else {
            throw ModelProvisioningError.incorrectChecksum
        }
    }
}

struct ModelStore: Sendable {
    let rootURL: URL
    let fileManager: FileManager
    let verifier: any ModelFileVerifying

    init(rootURL: URL, fileManager: FileManager = .default, verifier: any ModelFileVerifying = SHA256ModelFileVerifier()) throws {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.verifier = verifier
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = rootURL
        try mutableRoot.setResourceValues(values)
    }

    static func applicationSupport() throws -> ModelStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return try ModelStore(rootURL: base.appending(path: "WardrobeAI/Models", directoryHint: .isDirectory))
    }

    func verifiedModel(for descriptor: ModelDescriptor) throws -> VerifiedModel? {
        let url = destination(for: descriptor)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            try verifier.verify(url, against: descriptor)
            return VerifiedModel(descriptor: descriptor, fileURL: url, verifiedAt: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        } catch {
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    func importVerifiedFile(at sourceURL: URL, as descriptor: ModelDescriptor) throws -> VerifiedModel {
        try requireSpace(for: descriptor)
        try verifier.verify(sourceURL, against: descriptor)
        let destination = destination(for: descriptor)
        let temporary = rootURL.appending(path: ".\(UUID().uuidString).importing")
        try fileManager.copyItem(at: sourceURL, to: temporary)
        do {
            try verifier.verify(temporary, against: descriptor)
            if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
            try fileManager.moveItem(at: temporary, to: destination)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDestination = destination
            try mutableDestination.setResourceValues(values)
            return VerifiedModel(descriptor: descriptor, fileURL: destination, verifiedAt: Date())
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    func remove(_ descriptor: ModelDescriptor) throws {
        let url = destination(for: descriptor)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func destination(for descriptor: ModelDescriptor) -> URL {
        rootURL.appending(path: "\(descriptor.id.rawValue).litertlm")
    }

    private func requireSpace(for descriptor: ModelDescriptor) throws {
        let values = try rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        guard available >= descriptor.expectedBytes else {
            throw ModelProvisioningError.insufficientDiskSpace(required: descriptor.expectedBytes, available: available)
        }
    }
}
