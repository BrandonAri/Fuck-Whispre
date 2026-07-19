import AppKit
import AVFoundation
import ApplicationServices
import Foundation

@MainActor
final class DictationController {
    enum Status: Equatable {
        case ready
        case recording
        case handsFreeRecording
        case transcribing
        case typing
        case error(String)

        var message: String {
            switch self {
            case .ready: "Ready — hold Fn to talk"
            case .recording: "Listening… release Fn when finished"
            case .handsFreeRecording: "Hands-free listening… press Space to finish · Esc to cancel"
            case .transcribing: "Transcribing with Whisper…"
            case .typing: "Typing…"
            case .error(let message): message
            }
        }

        var menuBarSymbol: String {
            switch self {
            case .ready: "waveform"
            case .recording, .handsFreeRecording: "waveform.circle.fill"
            case .transcribing: "ellipsis.circle"
            case .typing: "keyboard.fill"
            case .error: "exclamationmark.triangle.fill"
            }
        }
    }

    var onStatusChange: ((Status) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    private(set) var status: Status = .ready {
        didSet {
            fnMonitor?.updateInteractionState(
                handsFree: status == .handsFreeRecording,
                cancellable: status == .recording || status == .handsFreeRecording || status == .transcribing || status == .typing
            )
            onStatusChange?(status)
        }
    }

    private let recorder = AudioRecorder()
    private let transcriber = LocalWhisperTranscriber()
    private let typer = TextTyper()
    private var fnMonitor: FnKeyMonitor?
    private var started = false
    private var fnIsHeld = false
    private var latchRequested = false
    private var recordingStartedAt: ContinuousClock.Instant?
    private var transcriptionTask: Task<Void, Never>?
    private var pendingRecordingStartID: UUID?

    func start() {
        guard !started else { return }
        started = true
        onStatusChange?(status)
        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.onAudioLevel?(level)
            }
        }
        fnMonitor = FnKeyMonitor(
            onPress: { [weak self] in Task { @MainActor in self?.fnPressed() } },
            onRelease: { [weak self] in Task { @MainActor in self?.fnReleased() } },
            onLatch: { [weak self] in Task { @MainActor in self?.latchHandsFree() } },
            onFinish: { [weak self] in Task { @MainActor in self?.handsFreeStopPressed() } },
            onCancel: { [weak self] in Task { @MainActor in self?.cancelCurrentDictation() } }
        )
        fnMonitor?.start()
        fnMonitor?.updateInteractionState(handsFree: false, cancellable: false)
        AppLog.dictation.info("Dictation controller started")
        Task { await transcriber.warmUp() }
    }

    func requestMicrophoneAccess() {
        Task { _ = await AVCaptureDevice.requestAccess(for: .audio) }
    }

    func requestAccessibilityAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func warmSelectedModel() {
        Task { await transcriber.reloadSelectedModel() }
    }

    private func fnPressed() {
        guard status != .recording, status != .handsFreeRecording, status != .transcribing, status != .typing else { return }
        fnIsHeld = true
        latchRequested = false
        let startID = UUID()
        pendingRecordingStartID = startID
        AppLog.dictation.info("Fn pressed; microphone authorization=\(String(describing: AVCaptureDevice.authorizationStatus(for: .audio)), privacy: .public)")

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecording(startID: startID)
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                guard pendingRecordingStartID == startID else { return }
                guard granted else {
                    pendingRecordingStartID = nil
                    AppLog.dictation.error("Microphone permission was denied")
                    status = .error("Microphone permission is required")
                    return
                }
                beginRecording(startID: startID)
            }
        default:
            pendingRecordingStartID = nil
            AppLog.dictation.error("Microphone permission is unavailable")
            status = .error("Microphone permission is required")
        }
    }

    private func beginRecording(startID: UUID) {
        guard pendingRecordingStartID == startID else { return }
        guard fnIsHeld || latchRequested else {
            pendingRecordingStartID = nil
            AppLog.dictation.info("Recording start cancelled because Fn was released")
            return
        }
        do {
            try recorder.start()
            pendingRecordingStartID = nil
            recordingStartedAt = .now
            status = latchRequested ? .handsFreeRecording : .recording
            AppLog.audio.info("Recording started")
        } catch {
            pendingRecordingStartID = nil
            AppLog.audio.error("Could not start recording: \(error.localizedDescription, privacy: .public)")
            status = .error("Could not start recording: \(error.localizedDescription)")
        }
    }

    private func fnReleased() {
        fnIsHeld = false
        AppLog.dictation.info("Fn released; state=\(String(describing: self.status), privacy: .public)")
        if status == .recording {
            finishRecording()
        } else if status != .handsFreeRecording {
            pendingRecordingStartID = nil
        }
    }

    private func latchHandsFree() {
        guard fnIsHeld else { return }
        latchRequested = true
        if status == .recording { status = .handsFreeRecording }
    }

    private func handsFreeStopPressed() {
        guard status == .handsFreeRecording else { return }
        finishRecording()
    }

    private func finishRecording() {
        guard status == .recording || status == .handsFreeRecording else { return }
        latchRequested = false
        let duration = recordingStartedAt.map { $0.duration(to: .now) } ?? .zero
        recordingStartedAt = nil

        do {
            let recording = try recorder.stop()
            let measuredDuration = recording.duration
            let fileSize = (try? recording.file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            AppLog.audio.info(
                "Recording stopped: wallSeconds=\(Self.seconds(duration), privacy: .public), audioSeconds=\(measuredDuration, privacy: .public), frames=\(recording.frameCount), bytes=\(fileSize), rmsDB=\(recording.rmsDecibels, privacy: .public), peakDB=\(recording.peakDecibels, privacy: .public), meaningful=\(recording.hasSpeech)"
            )
            if duration < .milliseconds(300) || measuredDuration < 0.25 {
                AppLog.audio.info("Discarding recording shorter than 250 ms")
                try? FileManager.default.removeItem(at: recording.file)
                status = .ready
                return
            }
            let defaults = UserDefaults.standard
            let ignoreSilence = defaults.object(forKey: "ignoreSilentRecordings") == nil
                ? true
                : defaults.bool(forKey: "ignoreSilentRecordings")
            if ignoreSilence && !recording.hasSpeech {
                AppLog.audio.info("Discarding near-silent microphone stream")
                try? FileManager.default.removeItem(at: recording.file)
                status = .ready
                return
            }
            status = .transcribing
            AppLog.whisper.info("Sending recording to local Whisper")
            transcriptionTask = Task { [weak self] in await self?.transcribeAndType(recording.file) }
        } catch {
            AppLog.audio.error("Could not finish recording: \(error.localizedDescription, privacy: .public)")
            status = .error("Could not finish recording: \(error.localizedDescription)")
        }
    }

    private func cancelCurrentDictation() {
        latchRequested = false
        pendingRecordingStartID = nil
        recordingStartedAt = nil
        if status == .recording || status == .handsFreeRecording {
            if let file = recorder.cancel() { try? FileManager.default.removeItem(at: file) }
            status = .ready
            return
        }
        if status == .transcribing || status == .typing {
            transcriptionTask?.cancel()
            transcriptionTask = nil
            status = .ready
        }
    }

    private func transcribeAndType(_ file: URL) async {
        defer {
            try? FileManager.default.removeItem(at: file)
            transcriptionTask = nil
        }
        do {
            try Task.checkCancellation()
            let text = try await transcriber.transcribe(file: file)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()
            guard !text.isEmpty else {
                AppLog.whisper.error("Whisper returned an empty transcription")
                status = .error("Whisper returned no text")
                return
            }
            guard AXIsProcessTrusted() else {
                requestAccessibilityAccess()
                status = .error("Enable Accessibility, then try again")
                return
            }
            status = .typing
            try await typer.type(text)
            try Task.checkCancellation()
            AppLog.dictation.info("Transcription inserted successfully; characters=\(text.count)")
            status = .ready
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                if status != .ready { status = .ready }
                return
            }
            AppLog.whisper.error("Dictation failed: \(error.localizedDescription, privacy: .public)")
            status = .error(error.localizedDescription)
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    nonisolated func shutdownImmediately() { transcriber.shutdownImmediately() }
}
