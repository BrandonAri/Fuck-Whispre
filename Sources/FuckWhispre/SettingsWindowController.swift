import AppKit
import AVFoundation
import ApplicationServices

@MainActor
final class SettingsWindowController: NSWindowController {
    private let controller: DictationController
    private let modelPopup = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
    private let modelStatus = NSTextField(labelWithString: "")
    private let modelAction = NSButton()
    private let downloadProgress = NSProgressIndicator()
    private let microphoneStatus = NSTextField(labelWithString: "")
    private let accessibilityStatus = NSTextField(labelWithString: "")
    private var refreshTimer: Timer?
    private var activeDownload: ModelDownloadOperation?
    private var downloadTask: Task<Void, Never>?

    init(controller: DictationController) {
        self.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Fuck Whispre Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = makeContentView()
        loadPreferences()
        refreshTimer = Timer.scheduledTimer(timeInterval: 0.8, target: self, selector: #selector(refreshPermissions), userInfo: nil, repeats: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeContentView() -> NSView {
        let root = NSView()
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "Settings")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Tune local transcription without changing the Fn workflow.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        let headerText = NSStackView(views: [title, subtitle])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 3
        let header = NSStackView(views: [icon, headerText])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14

        modelPopup.addItems(withTitles: WhisperModelSize.allCases.map { "\($0.title) · \($0.diskSize)" })
        languagePopup.addItems(withTitles: TranscriptionLanguage.allCases.map(\.title))
        modelPopup.target = self
        modelPopup.action = #selector(modelChoiceChanged)
        languagePopup.target = self
        languagePopup.action = #selector(modelChoiceChanged)

        modelAction.bezelStyle = .rounded
        modelAction.target = self
        modelAction.action = #selector(modelActionClicked)
        downloadProgress.style = .bar
        downloadProgress.controlSize = .small
        downloadProgress.minValue = 0
        downloadProgress.maxValue = 1
        downloadProgress.isIndeterminate = false
        downloadProgress.isDisplayedWhenStopped = false
        downloadProgress.isHidden = true
        downloadProgress.widthAnchor.constraint(equalToConstant: 110).isActive = true
        modelStatus.font = .systemFont(ofSize: 11.5)
        modelStatus.textColor = .secondaryLabelColor

        let modelActions = NSStackView(views: [modelAction, downloadProgress, modelStatus])
        modelActions.orientation = .horizontal
        modelActions.alignment = .centerY
        modelActions.spacing = 10
        let modelGrid = settingsGrid(rows: [
            ("Model", modelPopup),
            ("Language", languagePopup),
            ("Status", modelActions)
        ])
        let modelSection = section(title: "Transcription model", views: [modelGrid])

        let hotkeyValue = NSTextField(labelWithString: "Hold Fn · Fn + Space latches · Space finishes · Esc cancels")
        hotkeyValue.textColor = .secondaryLabelColor
        let minimumValue = NSTextField(labelWithString: "Every recording at least 0.5 seconds is sent to Whisper")
        minimumValue.textColor = .secondaryLabelColor
        let behaviorGrid = settingsGrid(rows: [
            ("Hotkey", hotkeyValue),
            ("Minimum", minimumValue)
        ])
        let behaviorSection = section(title: "Behavior", views: [behaviorGrid])

        let microphoneButton = NSButton(title: "Open Microphone Settings", target: self, action: #selector(openMicrophoneSettings))
        let accessibilityButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccessibilitySettings))
        let permissionsGrid = settingsGrid(rows: [
            ("Microphone", permissionControl(status: microphoneStatus, button: microphoneButton)),
            ("Accessibility", permissionControl(status: accessibilityStatus, button: accessibilityButton))
        ])
        let permissionsSection = section(title: "Permissions", views: [permissionsGrid])

        let stack = NSStackView(views: [header, modelSection, behaviorSection, permissionsSection])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -26),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            icon.widthAnchor.constraint(equalToConstant: 50),
            icon.heightAnchor.constraint(equalToConstant: 50),
            modelSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            behaviorSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            permissionsSection.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return root
    }

    private func section(title: String, views: [NSView]) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        let content = NSStackView(views: views)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.62).cgColor
        content.layer?.cornerRadius = 13
        content.layer?.cornerCurve = .continuous
        let group = NSStackView(views: [heading, content])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 6
        content.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        return group
    }

    private func settingsGrid(rows: [(String, NSView)]) -> NSGridView {
        let gridRows: [[NSView]] = rows.map { label, control in
            let heading = NSTextField(labelWithString: label)
            heading.font = .systemFont(ofSize: 12, weight: .medium)
            heading.alignment = .right
            return [heading, control]
        }
        let grid = NSGridView(views: gridRows)
        grid.rowSpacing = 9
        grid.columnSpacing = 14
        grid.column(at: 0).width = 86
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        return grid
    }

    private func permissionControl(status: NSTextField, button: NSButton) -> NSView {
        status.font = .systemFont(ofSize: 11.5, weight: .medium)
        button.bezelStyle = .rounded
        button.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let row = NSStackView(views: [status, NSView(), button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.widthAnchor.constraint(equalToConstant: 420).isActive = true
        return row
    }

    private func loadPreferences() {
        let active = ModelManager.shared.activeSelection()
        modelPopup.selectItem(at: WhisperModelSize.allCases.firstIndex(of: active.size) ?? 1)
        languagePopup.selectItem(at: TranscriptionLanguage.allCases.firstIndex(of: active.language) ?? 0)
        refreshModelState()
        refreshPermissions()
    }

    private var chosenSelection: ModelSelection {
        ModelSelection(
            size: WhisperModelSize.allCases[max(0, modelPopup.indexOfSelectedItem)],
            language: TranscriptionLanguage.allCases[max(0, languagePopup.indexOfSelectedItem)]
        )
    }

    @objc private func modelChoiceChanged() { refreshModelState() }

    private func refreshModelState() {
        let choice = chosenSelection
        let active = ModelManager.shared.activeSelection()
        let installed = ModelManager.shared.modelURL(for: choice) != nil
        if choice == active {
            modelAction.title = "Active"
            modelAction.isEnabled = false
            modelStatus.stringValue = "Currently used for dictation"
            modelStatus.textColor = .secondaryLabelColor
        } else if installed {
            modelAction.title = "Use Model"
            modelAction.isEnabled = true
            modelStatus.stringValue = "Downloaded and ready"
            modelStatus.textColor = .systemGreen
        } else {
            modelAction.title = "Download \(choice.size.diskSize)"
            modelAction.isEnabled = true
            modelStatus.stringValue = "Downloads once; transcription remains local"
            modelStatus.textColor = .secondaryLabelColor
        }
    }

    @objc private func modelActionClicked() {
        if activeDownload != nil {
            activeDownload?.cancel()
            downloadTask?.cancel()
            return
        }
        let choice = chosenSelection
        if ModelManager.shared.modelURL(for: choice) != nil {
            ModelManager.shared.activate(choice)
            controller.warmSelectedModel()
            refreshModelState()
            return
        }
        modelAction.isEnabled = false
        modelPopup.isEnabled = false
        languagePopup.isEnabled = false
        downloadProgress.doubleValue = 0
        downloadProgress.isHidden = false
        modelAction.title = "Cancel"
        modelAction.isEnabled = true
        modelStatus.stringValue = "Starting download…"
        let operation = ModelManager.shared.makeDownload(choice) { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress.doubleValue = progress
                self?.modelStatus.stringValue = "Downloading… \(Int(progress * 100))%"
            }
        }
        activeDownload = operation
        downloadTask = Task { [weak self] in
            do {
                try await operation.start()
                self?.controller.warmSelectedModel()
                self?.modelStatus.stringValue = "Downloaded and active"
                self?.modelStatus.textColor = .systemGreen
            } catch {
                if (error as? URLError)?.code == .cancelled || Task.isCancelled {
                    self?.modelStatus.stringValue = "Download cancelled"
                    self?.modelStatus.textColor = .secondaryLabelColor
                } else {
                    self?.modelStatus.stringValue = error.localizedDescription
                    self?.modelStatus.textColor = .systemRed
                }
            }
            self?.activeDownload = nil
            self?.downloadTask = nil
            self?.downloadProgress.isHidden = true
            self?.modelPopup.isEnabled = true
            self?.languagePopup.isEnabled = true
            self?.refreshModelState()
        }
    }

    @objc private func refreshPermissions() {
        updatePermissionLabel(microphoneStatus, granted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        updatePermissionLabel(accessibilityStatus, granted: AXIsProcessTrusted())
    }

    private func updatePermissionLabel(_ label: NSTextField, granted: Bool) {
        label.stringValue = granted ? "✓ Enabled" : "Action required"
        label.textColor = granted ? .systemGreen : .systemOrange
    }

    @objc private func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(url) }
    }

    @objc private func openAccessibilitySettings() { controller.requestAccessibilityAccess() }
}
