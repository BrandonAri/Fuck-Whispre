import AppKit
import CoreGraphics
import Foundation

@MainActor
struct TextTyper {
    enum TypingError: LocalizedError {
        case eventCreationFailed

        var errorDescription: String? { "Could not paste the transcription into the focused app." }
    }

    /// Paste as one atomic edit. Posting many Unicode keyboard events can be
    /// reordered or dropped by busy apps, leaving characters missing or the
    /// insertion point between chunks.
    func type(_ text: String) async throws {
        let pasteboard = NSPasteboard.general
        let previous = ClipboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let transcriptionChangeCount = pasteboard.changeCount

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            previous.restore(to: pasteboard)
            throw TypingError.eventCreationFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        // Give the target app time to consume the paste before restoring the
        // clipboard. Never overwrite a clipboard change the user made meanwhile.
        try await Task.sleep(for: .milliseconds(450))
        if pasteboard.changeCount == transcriptionChangeCount {
            previous.restore(to: pasteboard)
        }
    }
}

@MainActor
private struct ClipboardSnapshot {
    struct Item {
        let values: [(NSPasteboard.PasteboardType, Data)]
    }

    let items: [Item]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Item(values: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored: [NSPasteboardItem] = items.map { snapshot in
            let item = NSPasteboardItem()
            for (type, data) in snapshot.values { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
