import OSLog

enum AppLog {
    private static let subsystem = "com.brandon.FuckWisprFlow"

    static let dictation = Logger(subsystem: subsystem, category: "Dictation")
    static let audio = Logger(subsystem: subsystem, category: "Audio")
    static let whisper = Logger(subsystem: subsystem, category: "Whisper")
}
