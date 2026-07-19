import XCTest
@testable import FuckWisprFlow

final class AudioRecorderTests: XCTestCase {
    func testRoomNoiseIsRejected() {
        XCTAssertFalse(
            AudioRecorder.containsMeaningfulAudio(
                rms: amplitude(decibels: -65.59),
                peak: amplitude(decibels: -53.32)
            )
        )
    }

    func testQuietSpeechIsAccepted() {
        XCTAssertTrue(
            AudioRecorder.containsMeaningfulAudio(
                rms: amplitude(decibels: -59.38),
                peak: amplitude(decibels: -37.70)
            )
        )
    }

    func testEmptyAudioIsRejected() {
        XCTAssertFalse(AudioRecorder.containsMeaningfulAudio(rms: 0, peak: 0))
    }

    private func amplitude(decibels: Float) -> Float {
        pow(10, decibels / 20)
    }
}
