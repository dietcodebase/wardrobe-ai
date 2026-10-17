import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum ModelRuntimePolicy {
    /// M06 is authorized against the M01 probe results while combined memory and
    /// capture-switch measurements remain outstanding. See docs/m06-evidence.md.
    static let deviceQualificationPassed = true
}

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

protocol ModelFileVerifying {
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

struct ModelStore {
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
        try ensureCapacity(for: descriptor)
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

    func ensureCapacity(for descriptor: ModelDescriptor) throws {
        let values = try rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        guard available >= descriptor.expectedBytes else {
            throw ModelProvisioningError.insufficientDiskSpace(required: descriptor.expectedBytes, available: available)
        }
    }
}

enum ModelTransferStatus: Equatable {
    case notPresent
    case downloading(progress: Double)
    case interrupted
    case available(VerifiedModel)
    case failed(String)
}

@MainActor
final class ModelManager: ObservableObject {
    @Published private(set) var provisioningMessage: String?
    let downloads: ModelDownloadController?

    private let store: ModelStore?
    private var observers: [NSObjectProtocol] = []

    init(store: ModelStore? = try? .applicationSupport()) {
        self.store = store
        self.downloads = store.map(ModelDownloadController.init)
        if store == nil { provisioningMessage = "Secure model storage is unavailable. Your manual wardrobe is still available." }
        downloads?.refresh()
        let center = NotificationCenter.default
        observers = [center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.releaseForSystemPressure() } }]
#if canImport(UIKit)
        observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.releaseForSystemPressure() } })
#endif
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func importModel(at fileURL: URL, descriptor: ModelDescriptor) {
        guard ModelRuntimePolicy.deviceQualificationPassed else {
            provisioningMessage = "Model provisioning stays disabled until M01 qualifies this device and runtime combination."
            return
        }
        guard let store else { return }
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
        do {
            let model = try store.importVerifiedFile(at: fileURL, as: descriptor)
            downloads?.recordImported(model)
            provisioningMessage = "\(descriptor.id.rawValue.uppercased()) was verified and stored locally."
        } catch {
            provisioningMessage = error.localizedDescription
        }
    }

    func releaseForSystemPressure() {
        Task { await ModelRuntime.shared.unload() }
        provisioningMessage = "Released the local model after memory or thermal pressure."
    }

    func reportProvisioningFailure(_ error: Error) {
        provisioningMessage = error.localizedDescription
    }
}

@MainActor
final class ModelDownloadController: NSObject, ObservableObject {
    @Published private(set) var statusByModel: [ModelID: ModelTransferStatus] = [:]

    private let store: ModelStore
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    private var descriptorsByTaskID: [Int: ModelDescriptor] = [:]
    private var tasksByModel: [ModelID: URLSessionDownloadTask] = [:]

    init(store: ModelStore) {
        self.store = store
        super.init()
    }

    func refresh() {
        for descriptor in ModelDescriptor.qualifiedCandidates {
            statusByModel[descriptor.id] = (try? store.verifiedModel(for: descriptor)).flatMap { $0.map(ModelTransferStatus.available) } ?? .notPresent
        }
    }

    func recordImported(_ model: VerifiedModel) {
        statusByModel[model.descriptor.id] = .available(model)
    }

    func download(_ descriptor: ModelDescriptor) {
        do {
            try store.ensureCapacity(for: descriptor)
            let task = session.downloadTask(with: descriptor.downloadURL)
            descriptorsByTaskID[task.taskIdentifier] = descriptor
            tasksByModel[descriptor.id] = task
            statusByModel[descriptor.id] = .downloading(progress: 0)
            task.resume()
        } catch {
            statusByModel[descriptor.id] = .failed(error.localizedDescription)
        }
    }

    func cancel(_ descriptor: ModelDescriptor) {
        guard let task = tasksByModel[descriptor.id] else { return }
        let resumeURL = resumeDataURL(for: descriptor)
        task.cancel(byProducingResumeData: { [weak self] data in
            guard let self else { return }
            if let data { try? data.write(to: resumeURL, options: .atomic) }
            Task { @MainActor in self.statusByModel[descriptor.id] = .interrupted }
        })
    }

    func resume(_ descriptor: ModelDescriptor) {
        let resumeURL = resumeDataURL(for: descriptor)
        guard let data = try? Data(contentsOf: resumeURL) else {
            download(descriptor)
            return
        }
        let task = session.downloadTask(withResumeData: data)
        descriptorsByTaskID[task.taskIdentifier] = descriptor
        tasksByModel[descriptor.id] = task
        statusByModel[descriptor.id] = .downloading(progress: 0)
        task.resume()
    }

    private func resumeDataURL(for descriptor: ModelDescriptor) -> URL {
        store.rootURL.appending(path: "\(descriptor.id.rawValue).resume")
    }

    private func finishDownload(at location: URL, descriptor: ModelDescriptor) {
        defer {
            tasksByModel[descriptor.id] = nil
            try? FileManager.default.removeItem(at: resumeDataURL(for: descriptor))
        }
        do {
            statusByModel[descriptor.id] = .available(try store.importVerifiedFile(at: location, as: descriptor))
        } catch {
            statusByModel[descriptor.id] = .failed(error.localizedDescription)
        }
    }
}

extension ModelDownloadController: URLSessionDownloadDelegate, URLSessionTaskDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        Task { @MainActor in
            guard let descriptor = self.descriptorsByTaskID[downloadTask.taskIdentifier] else { return }
            self.statusByModel[descriptor.id] = .downloading(progress: Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Task { @MainActor in
            guard let descriptor = self.descriptorsByTaskID.removeValue(forKey: downloadTask.taskIdentifier) else { return }
            self.finishDownload(at: location, descriptor: descriptor)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            guard let descriptor = self.descriptorsByTaskID.removeValue(forKey: task.taskIdentifier) else { return }
            self.tasksByModel[descriptor.id] = nil
            if (error as NSError).code == NSURLErrorCancelled {
                self.statusByModel[descriptor.id] = .interrupted
            } else {
                self.statusByModel[descriptor.id] = .failed(error.localizedDescription)
            }
        }
    }
}

enum ModelRuntimeError: LocalizedError {
    case unqualifiedRuntime

    var errorDescription: String? {
        "No production inference adapter is configured yet. Your manual wardrobe remains available."
    }
}

protocol ModelEngine: AnyObject, Sendable {
    func unload() async
}

protocol ModelEngineLoading: Sendable {
    func load(_ model: VerifiedModel) async throws -> any ModelEngine
}

struct UnqualifiedModelEngineLoader: ModelEngineLoading {
    func load(_ model: VerifiedModel) async throws -> any ModelEngine {
        throw ModelRuntimeError.unqualifiedRuntime
    }
}

private actor InferenceGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        guard isLocked else { isLocked = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func leave() {
        if waiters.isEmpty { isLocked = false }
        else { waiters.removeFirst().resume() }
    }
}

actor ModelInferenceCoordinator {
    private let loader: any ModelEngineLoading
    private let gate = InferenceGate()
    private var active: (model: VerifiedModel, engine: any ModelEngine)?

    init(loader: any ModelEngineLoading = UnqualifiedModelEngineLoader()) {
        self.loader = loader
    }

    func withEngine<Result: Sendable>(for model: VerifiedModel, operation: @Sendable (any ModelEngine) async throws -> Result) async throws -> Result {
        await gate.enter()
        do {
            let engine = try await prepareEngine(for: model)
            let result = try await operation(engine)
            await gate.leave()
            return result
        } catch {
            await gate.leave()
            throw error
        }
    }

    func unload() async {
        await gate.enter()
        if let active {
            await active.engine.unload()
            self.active = nil
        }
        await gate.leave()
    }

    private func prepareEngine(for model: VerifiedModel) async throws -> any ModelEngine {
        if let active, active.model.descriptor.id == model.descriptor.id { return active.engine }
        if let active {
            await active.engine.unload()
            self.active = nil
        }
        let engine = try await loader.load(model)
        active = (model, engine)
        return engine
    }
}

enum ModelRuntime {
    static let shared = ModelInferenceCoordinator()
}
