import CryptoKit
import Foundation
import LiteRTLM
import UIKit

struct Artifact: Decodable {
    let id: String
    let filename: String
    let bytes: Int64
    let sha256: String
}

struct ProbeManifest: Decodable {
    let models: [Artifact]
}

enum ProbeMode: String, CaseIterable, Identifiable {
    case text, image, audio, tools, embedding
    var id: String { rawValue }
}

struct ProbeReport: Codable {
    let environment: [String: String]
    let samples: [ProbeSample]
}

struct ProbeSample: Codable {
    let phase: String
    let iteration: Int
    let seconds: Double
    let thermalState: Int
    let result: String
}

// A single actor owns every engine operation. No wardrobe records or write tools.
actor RuntimeProbe {
    private var samples: [ProbeSample] = []
    private let output: URL
    private let cache: URL
    private var environment: [String: String] = [:]

    init(output: URL, cache: URL) {
        self.output = output
        self.cache = cache
    }

    func run(folder: URL, mode: ProbeMode, e4b: Bool, mtp: Bool) async throws {
        samples = []
        environment = ["os": ProcessInfo.processInfo.operatingSystemVersionString,
                       "runtimeRevision": "c1312ccd68050838dd2dc109e7f8443056ae6546",
                       "startedUTC": ISO8601DateFormatter().string(from: Date()),
                       "mode": mode.rawValue, "mtp": String(mtp), "e4b": String(e4b),
                       "backend": "Metal", "contextTokens": "4096",
                       "visionBackend": mode == .image ? "cpu" : (mode == .embedding ? "gpu" : "disabled"),
                       "audioBackend": mode == .audio ? "cpu" : "disabled"]
        var system = utsname()
        uname(&system)
        environment["hardware"] = withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let manifestURL = Bundle.main.url(forResource: "artifacts", withExtension: "json")!
        let manifest = try JSONDecoder().decode(ProbeManifest.self, from: Data(contentsOf: manifestURL))
        let id = mode == .embedding ? "embedding" : (e4b ? "e4b" : "e2b")
        let artifact = manifest.models.first { $0.id == id }!
        try verify(folder.appendingPathComponent(artifact.filename), artifact: artifact)
        try record("verified-\(id)-\(artifact.sha256)-mtp-\(mtp)", 0, 0, "metadata only")
        ExperimentalFlags.optIntoExperimentalAPIs()
        ExperimentalFlags.enableSpeculativeDecoding = mtp
        // The first load uses a new cache; the second reuses it. Neither implies OS page-cache eviction.
        do {
            for pass in 0..<2 {
                try Task.checkCancellation()
                if mode == .embedding {
                    try await embeddings(folder: folder, artifact: artifact, pass: pass)
                } else {
                    try await generation(folder: folder, artifact: artifact, mode: mode, pass: pass)
                }
            }
            try record("suite-complete", 0, 0, "Review semantic quality and external memory evidence")
        } catch {
            try record("suite-failed", 0, 0, String(describing: error))
            throw error
        }
    }

    private func verify(_ url: URL, artifact: Artifact) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard try file.seekToEnd() == UInt64(artifact.bytes) else { throw ProbeError.invalidArtifact }
        try file.seek(toOffset: 0)
        var hasher = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        guard hasher.finalize().map({ String(format: "%02x", $0) }).joined() == artifact.sha256 else {
            throw ProbeError.invalidArtifact
        }
    }

    private func generation(folder: URL, artifact: Artifact, mode: ProbeMode, pass: Int) async throws {
        // Scope release: conversations retain the engine; both must leave this function before switching.
        let config = try EngineConfig(
            modelPath: folder.appendingPathComponent(artifact.filename).path,
            backend: .gpu, visionBackend: mode == .image ? .cpu() : nil,
            audioBackend: mode == .audio ? .cpu() : nil,
            maxNumTokens: 4096, cacheDir: cache.path)
        let start = ProcessInfo.processInfo.systemUptime
        let engine = Engine(engineConfig: config)
        try await engine.initialize()
        try record("load-\(pass)", 0, ProcessInfo.processInfo.systemUptime - start, "initialized")
        for iteration in 1...10 {
            try Task.checkCancellation()
            let started = ProcessInfo.processInfo.systemUptime
            var contents = [Content.text("Reply with the word ready.")]
            switch mode {
            case .image:
                let image = try preparedImage(folder: folder, iteration: iteration)
                contents = [.imageFile(image.path), .text("Describe the garment category and color in one sentence.")]
            case .audio:
                // Fixture contract: <=10 seconds, mono PCM16 WAV at 16 kHz; qualify decoder acceptance separately.
                let audio = folder.appendingPathComponent(String(format: "audio-%02d.wav", iteration))
                guard FileManager.default.fileExists(atPath: audio.path) else { throw ProbeError.missingFixture }
                contents = [.audioFile(audio.path), .text("Transcribe this recording.")]
            case .tools:
                await ToolWitness.shared.reset()
                contents = [.text("Call probe_echo once, then repeat its returned value.")]
            default: break
            }
            let conversation = try await engine.createConversation(with: ConversationConfig(
                tools: mode == .tools ? [ProbeEcho()] : [],
                thinkingConfig: ThinkingConfig(enableThinking: false, thinkingTokenBudget: 0)))
            do {
                let response = try await conversation.sendMessage(Message(contents: contents), maxOutputTokens: 128)
                let calls = await ToolWitness.shared.count
                let result = "toolCalls=\(calls); final=\(response.toString)"
                try record("\(mode.rawValue)-\(pass)", iteration, ProcessInfo.processInfo.systemUptime - started, result)
            } catch {
                try record("\(mode.rawValue)-\(pass)", iteration, ProcessInfo.processInfo.systemUptime - started, "ERROR: \(error)")
                throw error
            }
        }
    }

    private func embeddings(folder: URL, artifact: Artifact, pass: Int) async throws {
        let engine = EmbeddingEngine(config: .init(
            modelPath: folder.appendingPathComponent(artifact.filename).path,
            backend: .gpu, visionBackend: .gpu, cacheDir: cache.path))
        do {
            let start = ProcessInfo.processInfo.systemUptime
            try await engine.initialize()
            try record("embedding-load-\(pass)", 0, ProcessInfo.processInfo.systemUptime - start, "initialized")
            for iteration in 1...10 {
                try Task.checkCancellation()
                let started = ProcessInfo.processInfo.systemUptime
                let image = try preparedImage(folder: folder, iteration: iteration)
                let text = try await engine.computeEmbedding(contents: [.text("task: search query | text: red shirt")],
                                                             options: .init(normalize: true))
                let picture = try await engine.computeEmbedding(contents: [.imageFile(image.path)],
                                                                options: .init(normalize: true))
                for vector in [text.embedding, picture.embedding] {
                    guard vector.count == 768, vector.allSatisfy({ $0.isFinite }),
                          vector.contains(where: { $0 != 0 }) else { throw ProbeError.invalidEmbedding }
                }
                try record("embedding-\(pass)", iteration, ProcessInfo.processInfo.systemUptime - started, "two valid 768D vectors; relevance untested")
            }
            await engine.close()
        } catch {
            await engine.close()
            throw error
        }
    }

    private func preparedImage(folder: URL, iteration: Int) throws -> URL {
        let source = folder.appendingPathComponent(String(format: "image-%02d.jpg", iteration))
        guard let image = UIImage(contentsOfFile: source.path), image.size.width > 0, image.size.height > 0 else {
            throw ProbeError.missingFixture
        }
        let scale = min(1, 768 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let data = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.85) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        let target = cache.appendingPathComponent("prepared.jpg")
        try data.write(to: target, options: .atomic)
        return target
    }

    private func record(_ phase: String, _ iteration: Int, _ seconds: Double, _ result: String) throws {
        samples.append(ProbeSample(phase: phase, iteration: iteration, seconds: seconds,
                                   thermalState: ProcessInfo.processInfo.thermalState.rawValue, result: result))
        // Persist after every operation so a later termination cannot erase completed measurements.
        try JSONEncoder().encode(ProbeReport(environment: environment, samples: samples))
            .write(to: output, options: .atomic)
    }
}

enum ProbeError: Error {
    case invalidArtifact, missingFixture, invalidEmbedding
}

actor ToolWitness {
    static let shared = ToolWitness()
    private(set) var count = 0
    func reset() { count = 0 }
    func called() { count += 1 }
}

struct ProbeEcho: Tool {
    static let name = "probe_echo"
    static let description = "Return a fixed qualification token. No side effects."
    init() {}
    func run() async throws -> Any {
        await ToolWitness.shared.called()
        return ["value": "wardrobe-probe-ok"]
    }
}
