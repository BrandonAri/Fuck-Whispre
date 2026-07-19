import AppKit
import AVFoundation
import ApplicationServices

@MainActor
final class PermissionsWindowController: NSWindowController {
    private let controller: DictationController
    private let microphoneStep = PermissionStepView(number: "1", title: "Microphone", detail: "Records only while Fn is held.")
    private let accessibilityStep = PermissionStepView(number: "2", title: "Accessibility", detail: "Watches Fn and types into the focused app.")
    private let finishButton = NSButton()
    private var refreshTimer: Timer?

    init(controller: DictationController) {
        self.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Fuck Whispre"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = makeContentView()
        refreshTimer = Timer.scheduledTimer(
            timeInterval: 0.6,
            target: self,
            selector: #selector(refreshPermissionState),
            userInfo: nil,
            repeats: true
        )
        refreshPermissionState()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeContentView() -> NSView {
        let root = NSView()
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Two permissions. Then you’re done.")
        title.font = .systemFont(ofSize: 25, weight: .bold)
        let privacy = NSTextField(labelWithString: "Speech stays on this Mac.")
        privacy.font = .systemFont(ofSize: 13)
        privacy.textColor = .secondaryLabelColor
        let titleStack = NSStackView(views: [title, privacy])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 4

        let header = NSStackView(views: [icon, titleStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 16

        microphoneStep.button.target = self
        microphoneStep.button.action = #selector(requestMicrophone)
        accessibilityStep.button.target = self
        accessibilityStep.button.action = #selector(requestAccessibility)

        let dragGuide = AccessibilityDragGuideView(appURL: Bundle.main.bundleURL)
        dragGuide.translatesAutoresizingMaskIntoConstraints = false

        finishButton.title = "Finish Setup"
        finishButton.bezelStyle = .rounded
        finishButton.controlSize = .large
        finishButton.keyEquivalent = "\r"
        finishButton.target = self
        finishButton.action = #selector(finishSetup)

        let footerText = NSTextField(labelWithString: "Hold Fn to talk · Release to transcribe")
        footerText.font = .systemFont(ofSize: 12, weight: .medium)
        footerText.textColor = .secondaryLabelColor
        let footer = NSStackView(views: [footerText, NSView(), finishButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let stack = NSStackView(views: [header, microphoneStep, accessibilityStep, dragGuide, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            icon.widthAnchor.constraint(equalToConstant: 62),
            icon.heightAnchor.constraint(equalToConstant: 62),
            microphoneStep.widthAnchor.constraint(equalTo: stack.widthAnchor),
            microphoneStep.heightAnchor.constraint(equalToConstant: 70),
            accessibilityStep.widthAnchor.constraint(equalTo: stack.widthAnchor),
            accessibilityStep.heightAnchor.constraint(equalToConstant: 70),
            dragGuide.widthAnchor.constraint(equalTo: stack.widthAnchor),
            dragGuide.heightAnchor.constraint(equalToConstant: 116),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return root
    }

    @objc func refreshPermissionState() {
        let microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let accessibilityGranted = AXIsProcessTrusted()
        microphoneStep.update(granted: microphoneGranted, actionTitle: microphoneGranted ? "Allowed" : microphoneActionTitle)
        accessibilityStep.update(granted: accessibilityGranted, actionTitle: accessibilityGranted ? "Enabled" : "Open System Settings")
        finishButton.isEnabled = microphoneGranted && accessibilityGranted
    }

    private var microphoneActionTitle: String {
        AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined ? "Allow Microphone" : "Open System Settings"
    }

    @objc private func requestMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                refreshPermissionState()
            }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func requestAccessibility() {
        controller.requestAccessibilityAccess()
    }

    @objc private func finishSetup() {
        UserDefaults.standard.set(true, forKey: "didCompleteOnboarding")
        window?.close()
    }
}

@MainActor
private final class PermissionStepView: NSView {
    let button = NSButton()
    private let status = NSTextField(labelWithString: "Action required")

    init(number: String, title: String, detail: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.65).cgColor
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous

        let badge = NSTextField(labelWithString: number)
        badge.alignment = .center
        badge.font = .systemFont(ofSize: 13, weight: .bold)
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        badge.layer?.cornerRadius = 15

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        let explanation = NSTextField(labelWithString: detail)
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 11, weight: .medium)
        status.textColor = .systemOrange

        for view in [badge, heading, explanation, status, button] { view.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(badge)
        addSubview(heading)
        addSubview(explanation)
        addSubview(status)
        addSubview(button)
        button.bezelStyle = .rounded

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 30),
            badge.heightAnchor.constraint(equalToConstant: 30),
            heading.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 14),
            heading.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            explanation.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            explanation.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 2),
            status.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            status.topAnchor.constraint(equalTo: explanation.bottomAnchor, constant: 2),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 158),
            explanation.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -14)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(granted: Bool, actionTitle: String) {
        status.stringValue = granted ? "✓ Ready" : "Action required"
        status.textColor = granted ? .systemGreen : .systemOrange
        button.title = actionTitle
        button.isEnabled = !granted
    }
}

@MainActor
private final class AccessibilityDragGuideView: NSView, NSDraggingSource {
    private let appURL: URL
    private let icon: NSImage
    private var phase: CGFloat = 0
    private var timer: Timer?

    init(appURL: URL) {
        self.appURL = appURL
        self.icon = NSWorkspace.shared.icon(forFile: appURL.path)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.07).cgColor
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        toolTip = "Drag this into the Accessibility app list"
        timer = Timer.scheduledTimer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tick() {
        phase = (phase + 0.008).truncatingRemainder(dividingBy: 1)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let title = "Drag the app into Accessibility"
        let detail = "Then turn its switch on. You can drag anywhere in this highlighted box."
        title.draw(at: NSPoint(x: 18, y: bounds.height - 31), withAttributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ])
        detail.draw(at: NSPoint(x: 18, y: bounds.height - 52), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: NSColor.secondaryLabelColor
        ])

        let iconRect = NSRect(x: 24, y: 12, width: 42, height: 42)
        icon.draw(in: iconRect)

        let targetRect = NSRect(x: bounds.width - 172, y: 13, width: 148, height: 40)
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: targetRect, xRadius: 10, yRadius: 10).fill()
        "Accessibility list".draw(at: NSPoint(x: targetRect.minX + 25, y: targetRect.minY + 12), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.controlAccentColor
        ])

        let travel = max(20, targetRect.minX - iconRect.maxX - 18)
        let eased = 0.5 - 0.5 * cos(phase * .pi * 2)
        let ghostX = iconRect.maxX + 9 + travel * eased
        icon.draw(in: NSRect(x: ghostX, y: 20, width: 28, height: 28), from: .zero, operation: .sourceOver, fraction: 0.55)
    }

    override func mouseDragged(with event: NSEvent) {
        let item = NSPasteboardItem()
        item.setString(appURL.absoluteString, forType: .fileURL)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(NSRect(x: event.locationInWindow.x, y: event.locationInWindow.y, width: 56, height: 56), contents: icon)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}
