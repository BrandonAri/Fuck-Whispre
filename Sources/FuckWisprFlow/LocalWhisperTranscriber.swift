import Foundation

private final class WhisperServerProcessHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func replace(with process: Process?) {
        let previous = lock.withLock { () -> Process? in
            let previous = self.process
            self.process = process
            return previous
        }
        if let previous, previous.isRunning { previous.terminate() }
    }

    func stop() { replace(with: nil) }
}

actor LocalWhisperTranscriber {
    enum LocalWhisperError: LocalizedError {
        case runtimeMissing
        case modelMissing
        case launchFailed(String)
        case serverUnavailable
        case transcriptionFailed(String)
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .runtimeMissing:
                "The bundled local Whisper runtime is missing. Rebuild the app."
            case .modelMissing:
                "The selected Whisper model is missing. Download it again."
            case .launchFailed(let detail):
                "Could not launch local Whisper: \(detail)"
            case .serverUnavailable:
                "Local Whisper did not finish loading. Please try again."
            case .transcriptionFailed(let detail):
                "Local Whisper failed: \(detail)"
            case .emptyResult:
                "Local Whisper returned no text."
            }
        }
    }

    private let processHolder = WhisperServerProcessHolder()
    private var serverProcess: Process?
    private var serverSelection: ModelSelection?
    private var serverPort: Int?

    func warmUp() async {
        let selection = ModelManager.shared.activeSelection()
        _ = try? await ensureServer(for: selection)
    }

    func transcribe(file: URL) async throws -> String {
        let selection = ModelManager.shared.activeSelection()
        let port = try await ensureServer(for: selection)
        try Task.checkCancellation()

        let boundary = "FuckWhispre-\(UUID().uuidString)"
        let body = try multipartBody(
            boundary: boundary,
            fields: [
                "language": selection.language.whisperArgument,
                "response_format": "text",
                "temperature": "0.0",
                "temperature_inc": "0.2",
                "best_of": "1",
                "beam_size": "1",
                "no_timestamps": "true"
            ],
            file: file
        )
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/inference")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let detail = String(data: data, encoding: .utf8) ?? "invalid server response"
            throw LocalWhisperError.transcriptionFailed(detail)
        }
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw LocalWhisperError.emptyResult }
        return text
    }

    func reloadSelectedModel() async {
        processHolder.stop()
        serverProcess = nil
        serverSelection = nil
        serverPort = nil
        await warmUp()
    }

    nonisolated func shutdownImmediately() { processHolder.stop() }

    private func ensureServer(for selection: ModelSelection) async throws -> Int {
        if serverSelection == selection,
           let process = serverProcess,
           process.isRunning,
           let port = serverPort {
            try await waitUntilReady(process: process, port: port)
            return port
        }

        guard let executable = Bundle.main.resourceURL?.appendingPathComponent("whisper-server"),
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw LocalWhisperError.runtimeMissing
        }
        guard let model = ModelManager.shared.modelURL(for: selection) else {
            throw LocalWhisperError.modelMissing
        }

        processHolder.stop()
        let process = Process()
        let port = Int.random(in: 49_152...62_000)
        let threads = min(8, max(4, ProcessInfo.processInfo.activeProcessorCount - 2))
        let serverArguments = [
            "--model", model.path,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--threads", "\(threads)",
            "--flash-attn",
            "--best-of", "1",
            "--beam-size", "1"
        ]
        // A tiny watchdog prevents the memory-heavy model worker from becoming
        // orphaned if the menu-bar app is force-quit or crashes. The shell is
        // replaced by whisper-server, so Process continues to track the server.
        let parentPID = ProcessInfo.processInfo.processIdentifier
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "parent_pid=\"$1\"; shift; (while kill -0 \"$parent_pid\" 2>/dev/null; do sleep 1; done; kill -TERM \"$$\" 2>/dev/null) & exec \"$@\"",
            "fuck-whispre-server",
            "\(parentPID)",
            executable.path
        ] + serverArguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw LocalWhisperError.launchFailed(error.localizedDescription)
        }
        processHolder.replace(with: process)
        serverProcess = process
        serverSelection = selection
        serverPort = port
        try await waitUntilReady(process: process, port: port)
        return port
    }

    private func waitUntilReady(process: Process, port: Int) async throws {
        let url = URL(string: "http://127.0.0.1:\(port)/")!
        for _ in 0..<400 {
            try Task.checkCancellation()
            guard process.isRunning else { throw LocalWhisperError.serverUnavailable }
            var request = URLRequest(url: url)
            request.timeoutInterval = 0.2
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               200..<500 ~= http.statusCode {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw LocalWhisperError.serverUnavailable
    }

    private func multipartBody(
        boundary: String,
        fields: [String: String],
        file: URL
    ) throws -> Data {
        var data = Data()
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            data.appendUTF8("--\(boundary)\r\n")
            data.appendUTF8("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            data.appendUTF8("\(value)\r\n")
        }
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n")
        data.appendUTF8("Content-Type: audio/wav\r\n\r\n")
        data.append(try Data(contentsOf: file))
        data.appendUTF8("\r\n--\(boundary)--\r\n")
        return data
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(string.data(using: .utf8)!)
    }
}
