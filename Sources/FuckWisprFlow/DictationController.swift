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
        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                status = .error("Microphone permission is required")
                return
            }
            guard fnIsHeld || latchRequested else { return }
            do {
                try recorder.start()
                recordingStartedAt = .now
                status = latchRequested ? .handsFreeRecording : .recording
            } catch {
                status = .error("Could not start recording: \(error.localizedDescription)")
            }
        }
    }

    private func fnReleased() {
        fnIsHeld = false
        if status == .recording { finishRecording() }
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
            if duration < .milliseconds(300) {
                try? FileManager.default.removeItem(at: recording.file)
                status = .ready
                return
            }
            let defaults = UserDefaults.standard
            let ignoreSilence = defaults.object(forKey: "ignoreSilentRecordings") == nil
                ? true
                : defaults.bool(forKey: "ignoreSilentRecordings")
            if ignoreSilence && !recording.hasSpeech {
                try? FileManager.default.removeItem(at: recording.file)
                status = .ready
                return
            }
            status = .transcribing
            transcriptionTask = Task { [weak self] in await self?.transcribeAndType(recording.file) }
        } catch {
            status = .error("Could not finish recording: \(error.localizedDescription)")
        }
    }

    private func cancelCurrentDictation() {
        latchRequested = false
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
            status = .ready
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                if status != .ready { status = .ready }
                return
            }
            status = .error(error.localizedDescription)
        }
    }

    nonisolated func shutdownImmediately() { transcriber.shutdownImmediately() }
}
