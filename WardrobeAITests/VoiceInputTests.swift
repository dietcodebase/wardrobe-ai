import XCTest
@testable import WardrobeAI

final class VoiceInputTests: XCTestCase {
    func testVoiceErrorsKeepTextInputAvailable() {
        XCTAssertEqual(VoiceInputError.permissionDenied.errorDescription, "Microphone access is off. You can still type your request.")
        XCTAssertTrue(VoiceInputError.runtimeUnavailable.errorDescription?.contains("can still type") == true)
    }

    func testVoiceFormatContractIsSixteenKilohertzMono() {
        XCTAssertEqual(VoiceInput.targetSampleRate, 16_000)
        XCTAssertEqual(VoiceInput.targetChannels, 1)
        XCTAssertEqual(VoiceInput.maximumDuration, 10)
    }
}
