import AVFoundation
import Foundation

enum VoiceInputError: LocalizedError, Equatable {
    case permissionDenied
    case recordingUnavailable
    case invalidFormat(sampleRate: Double, channels: Int)
    case durationExceeded
    case noRecording
    case runtimeUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Microphone access is off. You can still type your request."
        case .recordingUnavailable: "Voice recording is unavailable right now. You can still type your request."
        case let .invalidFormat(sampleRate, channels): "The recording format is \(Int(sampleRate)) Hz with \(channels) channel(s); voice input needs 16 kHz mono PCM audio."
        case .durationExceeded: "Voice requests are limited to 10 seconds."
        case .noRecording: "There is no voice recording to send."
        case .runtimeUnavailable: "Voice input is recorded locally, but the on-device audio runtime has not been qualified yet. Your recording was deleted; you can still type your request."
        }
    }
}

struct VoiceRecording: Equatable {
    let url: URL
    let duration: TimeInterval
}

protocol VoiceRecordingPermission {
    func requestRecordPermission() async -> Bool
}

struct SystemVoiceRecordingPermission: VoiceRecordingPermission {
    func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
    }
}

protocol VoiceRuntimeSubmitting {
    func submit(audio: VoiceRecording) async throws -> String
}

struct UnqualifiedVoiceRuntime: VoiceRuntimeSubmitting {
    func submit(audio: VoiceRecording) async throws -> String { throw VoiceInputError.runtimeUnavailable }
}

@MainActor
final class VoiceInput: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let targetSampleRate = 16_000.0
    static let targetChannels = 1
    static let maximumDuration: TimeInterval = 10

    @Published private(set) var isRecording = false
    @Published private(set) var statusMessage: String?

    private let permission: any VoiceRecordingPermission
    private let fileManager: FileManager
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var startedAt: Date?
    private var isFinishing = false
    private var wantsRecording = false
    private var interruptionObserver: NSObjectProtocol?

    init(permission: any VoiceRecordingPermission = SystemVoiceRecordingPermission(), fileManager: FileManager = .default) {
        self.permission = permission
        self.fileManager = fileManager
        super.init()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: rawValue) == .began else { return }
            Task { @MainActor [weak self] in self?.handleInterruption() }
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    func begin() async {
        guard !isRecording else { return }
        wantsRecording = true
        guard await permission.requestRecordPermission() else {
            wantsRecording = false
            statusMessage = VoiceInputError.permissionDenied.localizedDescription
            return
        }
        guard wantsRecording else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
            let url = fileManager.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).wav")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Self.targetSampleRate,
                AVNumberOfChannelsKey: Self.targetChannels,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = false
            guard recorder.record(forDuration: Self.maximumDuration) else { throw VoiceInputError.recordingUnavailable }
            self.recorder = recorder
            recordingURL = url
            startedAt = Date()
            isRecording = true
            statusMessage = "Listening… release when you’re done."
        } catch {
            cleanup()
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func finish() -> VoiceRecording? {
        wantsRecording = false
        guard isRecording, let recorder, let url = recordingURL, let startedAt else { return nil }
        isFinishing = true
        recorder.stop()
        self.recorder = nil
        self.isRecording = false
        defer {
            self.startedAt = nil
            self.isFinishing = false
        }
        let duration = Date().timeIntervalSince(startedAt)
        guard duration <= Self.maximumDuration + 0.25 else {
            cleanup(url: url)
            statusMessage = VoiceInputError.durationExceeded.localizedDescription
            return nil
        }
        do {
            try Self.validateFormat(at: url)
            recordingURL = nil
            deactivateAudioSession()
            statusMessage = nil
            return VoiceRecording(url: url, duration: duration)
        } catch {
            cleanup(url: url)
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    func cancel() {
        wantsRecording = false
        isFinishing = true
        recorder?.stop()
        cleanup()
        isFinishing = false
        statusMessage = "Voice input cancelled."
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.handleRecordingFinished(successfully: flag) }
    }

    private func handleRecordingFinished(successfully flag: Bool) {
        guard !isFinishing else { return }
        isRecording = false
        if !flag {
            cleanup()
            statusMessage = VoiceInputError.recordingUnavailable.localizedDescription
        } else {
            cleanup()
            statusMessage = VoiceInputError.durationExceeded.localizedDescription
        }
    }

    static func validateFormat(at url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let format = file.fileFormat
        let description = format.streamDescription.pointee
        let isExpectedPCM = description.mFormatID == kAudioFormatLinearPCM
            && format.commonFormat == .pcmFormatInt16
            && description.mBitsPerChannel == 16
            && format.isInterleaved
        guard isExpectedPCM,
              abs(format.sampleRate - targetSampleRate) < 1,
              format.channelCount == AVAudioChannelCount(targetChannels) else {
            throw VoiceInputError.invalidFormat(sampleRate: format.sampleRate, channels: Int(format.channelCount))
        }
    }

    func cleanup() { cleanup(url: recordingURL) }

    private func cleanup(url: URL?) {
        recorder?.stop()
        recorder = nil
        isRecording = false
        recordingURL = nil
        startedAt = nil
        wantsRecording = false
        if let url { try? fileManager.removeItem(at: url) }
        deactivateAudioSession()
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handleInterruption() {
        guard isRecording || wantsRecording else { return }
        let url = recordingURL
        isFinishing = true
        cleanup(url: url)
        isFinishing = false
        statusMessage = "Recording stopped by an audio interruption. Your recording was deleted; you can still type your request."
    }
}
