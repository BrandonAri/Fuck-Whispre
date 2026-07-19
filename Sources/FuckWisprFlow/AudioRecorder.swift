import AVFoundation
import Foundation

final class AudioRecorder: @unchecked Sendable {
    struct Result: Sendable {
        let file: URL
        let hasSpeech: Bool
    }

    var onLevel: (@Sendable (Float) -> Void)?
    enum RecorderError: LocalizedError {
        case alreadyRecording
        case notRecording

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: "A recording is already active."
            case .notRecording: "There is no active recording."
            }
        }
    }

    private let engine = AVAudioEngine()
    private var outputFile: AVAudioFile?
    private var outputURL: URL?
    private let speechLock = NSLock()
    private var speechFrameCount = 0

    func start() throws {
        guard !engine.isRunning else { throw RecorderError.alreadyRecording }
        speechLock.withLock { speechFrameCount = 0 }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fuck-wispr-flow-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? file.write(from: buffer)
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for index in 0..<count {
                sum += samples[index] * samples[index]
            }
            let rms = sqrt(sum / Float(count))
            let decibels = 20 * log10(max(rms, 0.000_01))
            if decibels > -42 {
                self.speechLock.withLock { self.speechFrameCount += 1 }
            }
            let normalized = min(1, max(0.04, (decibels + 52) / 52))
            self.onLevel?(normalized)
        }
        outputFile = file
        outputURL = url
        engine.prepare()
        try engine.start()
    }

    func stop() throws -> Result {
        guard engine.isRunning, let url = outputURL else { throw RecorderError.notRecording }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        outputFile = nil
        outputURL = nil
        let hasSpeech = speechLock.withLock { speechFrameCount >= 3 }
        return Result(file: url, hasSpeech: hasSpeech)
    }

    func cancel() -> URL? {
        let url = outputURL
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        outputFile = nil
        outputURL = nil
        return url
    }
}
