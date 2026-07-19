import Foundation

enum WhisperModelSize: String, CaseIterable, Sendable {
    case tiny
    case base
    case small
    case medium

    var title: String {
        switch self {
        case .tiny: "Tiny — fastest"
        case .base: "Base — balanced"
        case .small: "Small — more accurate"
        case .medium: "Medium — best quality"
        }
    }

    var diskSize: String {
        switch self {
        case .tiny: "75 MB"
        case .base: "142 MB"
        case .small: "466 MB"
        case .medium: "1.5 GB"
        }
    }
}

enum TranscriptionLanguage: String, CaseIterable, Sendable {
    case english
    case multilingual

    var title: String {
        switch self {
        case .english: "English"
        case .multilingual: "Auto-detect languages"
        }
    }

    var whisperArgument: String {
        switch self {
        case .english: "en"
        case .multilingual: "auto"
        }
    }
}

struct ModelSelection: Equatable, Sendable {
    var size: WhisperModelSize
    var language: TranscriptionLanguage

    var filename: String {
        let suffix = language == .english ? ".en" : ""
        return "ggml-\(size.rawValue)\(suffix).bin"
    }

    var displayName: String {
        "\(size.title) · \(language.title)"
    }
}

struct ModelManager: Sendable {
    static let shared = ModelManager()
    static let bundledDefault = ModelSelection(size: .base, language: .english)

    private let sizeKey = "activeModelSize"
    private let languageKey = "activeModelLanguage"

    func activeSelection() -> ModelSelection {
        let defaults = UserDefaults.standard
        let size = WhisperModelSize(rawValue: defaults.string(forKey: sizeKey) ?? "") ?? .base
        let language = TranscriptionLanguage(rawValue: defaults.string(forKey: languageKey) ?? "") ?? .english
        let selected = ModelSelection(size: size, language: language)
        return modelURL(for: selected) != nil ? selected : Self.bundledDefault
    }

    func activate(_ selection: ModelSelection) {
        guard modelURL(for: selection) != nil else { return }
        UserDefaults.standard.set(selection.size.rawValue, forKey: sizeKey)
        UserDefaults.standard.set(selection.language.rawValue, forKey: languageKey)
    }

    func modelURL(for selection: ModelSelection) -> URL? {
        if selection == Self.bundledDefault,
           let bundled = Bundle.main.resourceURL?.appendingPathComponent(selection.filename),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        let downloaded = modelsDirectory.appendingPathComponent(selection.filename)
        if FileManager.default.fileExists(atPath: downloaded.path) { return downloaded }
        let legacy = legacyModelsDirectory.appendingPathComponent(selection.filename)
        return FileManager.default.fileExists(atPath: legacy.path) ? legacy : nil
    }

    func makeDownload(
        _ selection: ModelSelection,
        progress: @escaping @Sendable (Double) -> Void
    ) -> ModelDownloadOperation {
        ModelDownloadOperation(selection: selection, destinationDirectory: modelsDirectory, progress: progress)
    }

    var modelsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Fuck Whispre/Models", isDirectory: true)
    }

    private var legacyModelsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Fuck Wispr Flow/Models", isDirectory: true)
    }

    enum DownloadError: LocalizedError {
        case invalidResponse
        var errorDescription: String? { "The model download failed. Please try again." }
    }
}

final class ModelDownloadOperation: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let selection: ModelSelection
    private let destinationDirectory: URL
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var movedFile = false

    init(selection: ModelSelection, destinationDirectory: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.selection = selection
        self.destinationDirectory = destinationDirectory
        self.progress = progress
    }

    func start() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                let configuration = URLSessionConfiguration.default
                configuration.timeoutIntervalForRequest = 60
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let source = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(selection.filename)")!
                let task = session.downloadTask(with: source)
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let http = downloadTask.response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw ModelManager.DownloadError.invalidResponse
            }
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            let destination = destinationDirectory.appendingPathComponent(selection.filename)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            ModelManager.shared.activate(selection)
            movedFile = true
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
        else if movedFile { finish(.success(())) }
        else { finish(.failure(ModelManager.DownloadError.invalidResponse)) }
        session.finishTasksAndInvalidate()
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        self.task = nil
        self.session = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}
