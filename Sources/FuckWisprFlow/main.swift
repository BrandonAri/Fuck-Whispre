import AppKit

@main
@MainActor
final class FuckWisprFlowApplication: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: FuckWisprFlowApplication?
    private let controller = DictationController()
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var helpMenuItem: NSMenuItem!
    private let recordingHUD = RecordingHUDController()
    private var recordingHUDVisible = false
    private var onboardingController: PermissionsWindowController?
    private var settingsController: SettingsWindowController?
    private var didStart = false

    static func main() {
        let app = NSApplication.shared
        let delegate = FuckWisprFlowApplication()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        delegate.startApplication()
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        startApplication()
    }

    private func startApplication() {
        guard !didStart else { return }
        didStart = true
        configureMenuBar()
        controller.onStatusChange = { [weak self] status in
            DispatchQueue.main.async { self?.render(status) }
        }
        controller.onAudioLevel = { [weak self] level in
            self?.recordingHUD.setLevel(level)
        }
        controller.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--show-settings") {
                self?.openSettings()
            } else if arguments.contains("--show-hud") {
                self?.recordingHUD.show(mode: .listening)
                self?.recordingHUD.setLevel(0.72)
            } else if arguments.contains("--show-transcribing") {
                self?.recordingHUD.show(mode: .transcribing)
            } else if arguments.contains("--show-hud-transition") {
                self?.recordingHUD.show(mode: .listening)
                self?.recordingHUD.setLevel(0.72)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self?.recordingHUD.show(mode: .transcribing)
                }
            } else if !UserDefaults.standard.bool(forKey: "didCompleteOnboarding") {
                self?.openOnboarding()
            }
        }
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setMenuBarMark(recording: false)

        menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "Ready — hold Fn to talk", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        helpMenuItem = NSMenuItem(title: "Fn + Space: hands-free · Space: finish · Esc: cancel", action: nil, keyEquivalent: "")
        helpMenuItem.isEnabled = false
        menu.addItem(helpMenuItem)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit Fuck Whispre", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func render(_ status: DictationController.Status) {
        statusMenuItem.title = status.message
        let isRecording = status == .recording || status == .handsFreeRecording
        setMenuBarMark(recording: isRecording)
        let mode: RecordingHUDController.Mode? = switch status {
        case .recording: .listening
        case .handsFreeRecording: .handsFree
        case .transcribing: .transcribing
        case .typing: .typing
        case .ready, .error: nil
        }
        if let mode {
            recordingHUDVisible = true
            recordingHUD.show(mode: mode)
        } else if recordingHUDVisible {
            recordingHUDVisible = false
            recordingHUD.hide()
        }
    }

    private func setMenuBarMark(recording: Bool) {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.attributedTitle = NSAttributedString(
            string: "Fuck.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .heavy),
                .foregroundColor: recording ? NSColor.systemRed : NSColor.labelColor
            ]
        )
        button.toolTip = "Fuck Whispre"
    }

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(controller: controller)
        }
        settingsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    private func openOnboarding() {
        if onboardingController == nil {
            onboardingController = PermissionsWindowController(controller: controller)
        }
        onboardingController?.showWindow(nil)
        onboardingController?.refreshPermissionState()
        NSApp.activate(ignoringOtherApps: true)
        onboardingController?.window?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdownImmediately()
    }
}
