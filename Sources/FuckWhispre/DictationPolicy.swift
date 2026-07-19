import Foundation

enum DictationPolicy {
    static let minimumHoldDuration: TimeInterval = 0.5

    static func shouldTranscribe(holdDuration: TimeInterval) -> Bool {
        holdDuration >= minimumHoldDuration
    }
}
