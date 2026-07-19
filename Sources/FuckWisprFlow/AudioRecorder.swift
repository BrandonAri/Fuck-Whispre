import AVFoundation
import Foundation

final class AudioRecorder: @unchecked Sendable {
    struct Result: Sendable {
        let file: URL
        let hasSpeech: Bool
        let duration: TimeInterval
        let rmsDecibels: Float
        let peakDecibels: Float
        let frameCount: Int64
    }

    var onLevel: (@Sendable (Float) -> Void)?
    enum RecorderError: LocalizedError {
        case alreadyRecording
        case notRecording
        case invalidInput
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: "A recording is already active."
            case .notRecording: "There is no active recording."
            case .invalidInput: "The selected microphone is not providing audio."
            case .writeFailed(let detail): "The recording could not be saved: \(detail)"
            }
        }
    }

    private struct CaptureStats {
        var frameCount: Int64 = 0
        var sampleCount: Int64 = 0
        var sumOfSquares: Double = 0
        var peak: Float = 0
        var writeError: String?
    }

    private let engine = AVAudioEngine()
    private var outputFile: AVAudioFile?
    private var outputURL: URL?
    private let captureLock = NSLock()
    private var captureStats = CaptureStats()
    private var sampleRate: Double = 0

    func start() throws {
        guard !engine.isRunning else { throw RecorderError.alreadyRecording }
        captureLock.withLock { captureStats = CaptureStats() }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError.invalidInput
        }
        sampleRate = format.sampleRate
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fuck-wispr-flow-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            do {
                try file.write(from: buffer)
            } catch {
                self.captureLock.withLock {
                    if self.captureStats.writeError == nil {
                        self.captureStats.writeError = error.localizedDescription
                    }
                }
            }

            guard let channels = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            guard frameCount > 0, channelCount > 0 else { return }

            var sumOfSquares: Double = 0
            var peak: Float = 0
            for channelIndex in 0..<channelCount {
                let samples = channels[channelIndex]
                for frameIndex in 0..<frameCount {
                    let sample = samples[frameIndex]
                    sumOfSquares += Double(sample * sample)
                    peak = max(peak, abs(sample))
                }
            }
            let sampleCount = Int64(frameCount * channelCount)
            self.captureLock.withLock {
                self.captureStats.frameCount += Int64(frameCount)
                self.captureStats.sampleCount += sampleCount
                self.captureStats.sumOfSquares += sumOfSquares
                self.captureStats.peak = max(self.captureStats.peak, peak)
            }

            let rms = sqrt(Float(sumOfSquares / Double(sampleCount)))
            let decibels = 20 * log10(max(rms, 0.000_01))
            let normalized = min(1, max(0.025, (decibels + 64) / 54))
            self.onLevel?(normalized)
        }
        outputFile = file
        outputURL = url
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            outputFile = nil
            outputURL = nil
            engine.reset()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func stop() throws -> Result {
        guard engine.isRunning, let url = outputURL else { throw RecorderError.notRecording }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        outputFile = nil
        outputURL = nil
        engine.reset()
        onLevel?(0)

        let stats = captureLock.withLock { captureStats }
        if let writeError = stats.writeError {
            try? FileManager.default.removeItem(at: url)
            throw RecorderError.writeFailed(writeError)
        }

        let rms = stats.sampleCount > 0
            ? Float(sqrt(stats.sumOfSquares / Double(stats.sampleCount)))
            : 0
        let duration = sampleRate > 0 ? Double(stats.frameCount) / sampleRate : 0
        return Result(
            file: url,
            hasSpeech: Self.containsMeaningfulAudio(rms: rms, peak: stats.peak),
            duration: duration,
            rmsDecibels: Self.decibels(rms),
            peakDecibels: Self.decibels(stats.peak),
            frameCount: stats.frameCount
        )
    }

    func cancel() -> URL? {
        let url = outputURL
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        outputFile = nil
        outputURL = nil
        engine.reset()
        onLevel?(0)
        return url
    }

    // This gate exists only to reject a genuinely empty microphone stream. A
    // normal speaking-volume threshold is brittle across built-in microphones,
    // AirPods, input-gain settings, and distance from the Mac. Quiet but real
    // audio should always be handed to Whisper.
    static func containsMeaningfulAudio(rms: Float, peak: Float) -> Bool {
        peak >= 0.003_16 || rms >= 0.000_8
    }

    private static func decibels(_ amplitude: Float) -> Float {
        20 * log10(max(amplitude, 0.000_01))
    }
}
