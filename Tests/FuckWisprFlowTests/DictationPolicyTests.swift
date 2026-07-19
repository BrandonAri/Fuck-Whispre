import XCTest
@testable import FuckWisprFlow

final class DictationPolicyTests: XCTestCase {
    func testPressShorterThanHalfSecondIsRejected() {
        XCTAssertFalse(DictationPolicy.shouldTranscribe(holdDuration: 0.499))
    }

    func testExactlyHalfSecondIsAlwaysTranscribed() {
        XCTAssertTrue(DictationPolicy.shouldTranscribe(holdDuration: 0.5))
    }

    func testLongSilentRecordingIsStillTranscribed() {
        XCTAssertTrue(DictationPolicy.shouldTranscribe(holdDuration: 3.0))
    }

    func testBundledModelUsesMultilingualAutoDetection() {
        XCTAssertEqual(ModelManager.bundledDefault.language, .multilingual)
        XCTAssertEqual(ModelManager.bundledDefault.filename, "ggml-base.bin")
        XCTAssertEqual(TranscriptionLanguage.allCases, [.multilingual])
        XCTAssertEqual(TranscriptionLanguage.multilingual.whisperArgument, "auto")
    }
}
