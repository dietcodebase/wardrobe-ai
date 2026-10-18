import XCTest
@testable import WardrobeAI

final class VoiceInputTests: XCTestCase {
    func testVoiceErrorsKeepTextInputAvailable() {
        XCTAssertEqual(VoiceInputError.permissionDenied.errorDescription, "Microphone access is off. You can still type your request.")
        XCTAssertTrue(VoiceInputError.runtimeUnavailable.errorDescription?.contains("can still type") == true)
    }

    @MainActor
    func testVoiceFormatContractIsSixteenKilohertzMono() {
        let sampleRate = VoiceInput.targetSampleRate
        let channels = VoiceInput.targetChannels
        let duration = VoiceInput.maximumDuration
        XCTAssertEqual(sampleRate, 16_000)
        XCTAssertEqual(channels, 1)
        XCTAssertEqual(duration, 10)
    }
}
