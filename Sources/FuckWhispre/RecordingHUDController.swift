import AppKit

@MainActor
final class RecordingHUDController {
    enum Mode: Equatable {
        case listening
        case handsFree
        case transcribing
        case typing
    }

    private let panel: NSWindow
    private let waveform = WaveformView()
    private let progress = IndeterminateProgressView()
    private let listeningLabel = NSTextField(labelWithString: "Listening")
    private let processingLabel = NSTextField(labelWithString: "Transcribing")
    private let recordingGroup = NSView()
    private let processingGroup = NSView()
    private var currentMode: Mode?
    private var transitionGeneration = 0

    init() {
        panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 210, height: 48),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = makeContentView()
    }

    func show(mode: Mode) {
        positionOnActiveScreen()
        if !panel.isVisible {
            currentMode = mode
            configure(mode)
            showOnly(group(for: mode))
            waveform.reset()
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            transition(to: mode)
        }
    }

    func hide() {
        transitionGeneration += 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel.orderOut(nil)
                self?.panel.alphaValue = 1
                self?.currentMode = nil
            }
        }
    }

    func setLevel(_ level: Float) {
        waveform.targetLevel = CGFloat(level)
    }

    private func transition(to mode: Mode) {
        guard mode != currentMode else { configure(mode); return }
        let old = currentMode.map(group(for:))
        let new = group(for: mode)
        currentMode = mode
        configure(mode)
        transitionGeneration += 1
        let generation = transitionGeneration

        // Listening -> hands-free and transcribing -> typing reuse the same
        // container. Animate the content update without hiding that container.
        if old === new {
            animateInPlaceUpdate(new)
            return
        }

        new.isHidden = false
        new.wantsLayer = true
        old?.wantsLayer = true
        new.layer?.opacity = 1

        if let oldLayer = old?.layer {
            let fadeOut = CAKeyframeAnimation(keyPath: "opacity")
            fadeOut.values = [1, 0.55, 0]
            fadeOut.keyTimes = [0, 0.45, 1]
            fadeOut.duration = 0.14
            fadeOut.timingFunctions = [
                CAMediaTimingFunction(name: .easeIn),
                CAMediaTimingFunction(name: .easeIn)
            ]
            oldLayer.opacity = 0
            oldLayer.add(fadeOut, forKey: "contentFadeOut")
        }

        if let newLayer = new.layer {
            let fadeIn = CAKeyframeAnimation(keyPath: "opacity")
            fadeIn.values = [0, 0, 0.72, 1]
            fadeIn.keyTimes = [0, 0.28, 0.72, 1]
            fadeIn.duration = 0.30
            fadeIn.timingFunctions = [
                CAMediaTimingFunction(name: .linear),
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeOut)
            ]
            newLayer.add(fadeIn, forKey: "contentFadeIn")

            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.94, 0.94, 1.025, 1]
            scale.keyTimes = [0, 0.28, 0.72, 1]
            scale.duration = 0.30
            scale.timingFunctions = fadeIn.timingFunctions
            newLayer.add(scale, forKey: "contentScale")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.31) { [weak self, weak old] in
            guard let self, generation == self.transitionGeneration else { return }
            old?.isHidden = true
            old?.layer?.opacity = 1
        }
    }

    private func animateInPlaceUpdate(_ group: NSView) {
        guard let layer = group.layer else { return }
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1, 0.42, 1]
        opacity.keyTimes = [0, 0.42, 1]
        opacity.duration = 0.22
        opacity.timingFunctions = [
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut)
        ]
        layer.add(opacity, forKey: "contentUpdateOpacity")

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1, 0.975, 1]
        scale.keyTimes = opacity.keyTimes
        scale.duration = opacity.duration
        scale.timingFunctions = opacity.timingFunctions
        layer.add(scale, forKey: "contentUpdateScale")
    }

    private func configure(_ mode: Mode) {
        switch mode {
        case .listening:
            listeningLabel.stringValue = "Listening"
            progress.isCompleted = false
        case .handsFree:
            listeningLabel.stringValue = "Space to finish"
            progress.isCompleted = false
        case .transcribing:
            processingLabel.stringValue = "Transcribing"
            progress.isCompleted = false
        case .typing:
            processingLabel.stringValue = "Typing"
            progress.isCompleted = true
        }
    }

    private func group(for mode: Mode) -> NSView {
        switch mode {
        case .listening, .handsFree: recordingGroup
        case .transcribing, .typing: processingGroup
        }
    }

    private func showOnly(_ visible: NSView) {
        for group in [recordingGroup, processingGroup] {
            group.isHidden = group !== visible
            group.layer?.opacity = 1
        }
    }

    private func makeContentView() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 210, height: 48))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.055, alpha: 0.94).cgColor
        root.layer?.cornerRadius = 20
        root.layer?.cornerCurve = .continuous
        root.layer?.borderWidth = 0.7
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.13).cgColor
        root.layer?.masksToBounds = true

        configureLabel(listeningLabel)
        configureLabel(processingLabel)
        configureGroup(recordingGroup, in: root)
        configureGroup(processingGroup, in: root)
        waveform.translatesAutoresizingMaskIntoConstraints = false
        progress.translatesAutoresizingMaskIntoConstraints = false
        recordingGroup.addSubview(waveform)
        recordingGroup.addSubview(listeningLabel)
        processingGroup.addSubview(progress)
        processingGroup.addSubview(processingLabel)

        NSLayoutConstraint.activate([
            waveform.leadingAnchor.constraint(equalTo: recordingGroup.leadingAnchor, constant: 14),
            waveform.centerYAnchor.constraint(equalTo: recordingGroup.centerYAnchor),
            waveform.widthAnchor.constraint(equalToConstant: 76),
            waveform.heightAnchor.constraint(equalToConstant: 30),
            listeningLabel.leadingAnchor.constraint(equalTo: waveform.trailingAnchor, constant: 10),
            listeningLabel.trailingAnchor.constraint(equalTo: recordingGroup.trailingAnchor, constant: -12),
            listeningLabel.centerYAnchor.constraint(equalTo: recordingGroup.centerYAnchor),

            progress.leadingAnchor.constraint(equalTo: processingGroup.leadingAnchor, constant: 18),
            progress.centerYAnchor.constraint(equalTo: processingGroup.centerYAnchor),
            progress.widthAnchor.constraint(equalToConstant: 64),
            progress.heightAnchor.constraint(equalToConstant: 8),
            processingLabel.leadingAnchor.constraint(equalTo: progress.trailingAnchor, constant: 12),
            processingLabel.trailingAnchor.constraint(equalTo: processingGroup.trailingAnchor, constant: -12),
            processingLabel.centerYAnchor.constraint(equalTo: processingGroup.centerYAnchor)
        ])
        return root
    }

    private func configureLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.84)
        label.lineBreakMode = .byClipping
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureGroup(_ group: NSView, in root: NSView) {
        group.wantsLayer = true
        group.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(group)
        NSLayoutConstraint.activate([
            group.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            group.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            group.topAnchor.constraint(equalTo: root.topAnchor),
            group.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    private func positionOnActiveScreen() {
        let mousePoint = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mousePoint) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY + max(78, visible.height * 0.105)
        ))
    }
}

@MainActor
private final class WaveformView: NSView {
    var targetLevel: CGFloat = 0.06
    private var displayedLevel: CGFloat = 0.06
    private var phase: CGFloat = 0
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        startAnimating()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        startAnimating()
    }

    func reset() {
        targetLevel = 0.06
        displayedLevel = 0.06
        phase = 0
    }

    private func startAnimating() {
        timer = Timer.scheduledTimer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }

    @objc private func tick() {
        displayedLevel += (targetLevel - displayedLevel) * 0.28
        targetLevel *= 0.92
        phase += 0.24
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let shapes: [CGFloat] = [0.42, 0.72, 0.92, 0.66, 1, 0.76, 0.48, 0.7]
        let barWidth: CGFloat = 4
        let gap: CGFloat = 4
        let totalWidth = CGFloat(shapes.count) * barWidth + CGFloat(shapes.count - 1) * gap
        var x = (bounds.width - totalWidth) / 2

        NSColor.systemRed.setFill()
        for (index, shape) in shapes.enumerated() {
            let motion = 0.72 + 0.28 * sin(phase + CGFloat(index) * 0.82)
            let energy = 0.16 + min(1, displayedLevel) * 0.84
            let height = max(4, bounds.height * shape * energy * motion)
            NSBezierPath(roundedRect: NSRect(x: x, y: bounds.midY - height / 2, width: barWidth, height: height), xRadius: 2, yRadius: 2).fill()
            x += barWidth + gap
        }
    }
}

@MainActor
private final class IndeterminateProgressView: NSView {
    var isCompleted = false { didSet { needsDisplay = true } }
    private var phase: CGFloat = 0
    private var timer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        timer = Timer.scheduledTimer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tick() {
        phase = (phase + 0.025).truncatingRemainder(dividingBy: 1)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).addClip()

        NSColor.white.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()

        NSColor.systemRed.withAlphaComponent(0.92).setFill()
        if isCompleted {
            NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        } else {
            let width = bounds.width * 0.30
            let travel = bounds.width + width
            let x = phase * travel - width
            NSBezierPath(
                roundedRect: NSRect(x: x, y: 0, width: width, height: bounds.height),
                xRadius: bounds.height / 2,
                yRadius: bounds.height / 2
            ).fill()
        }
    }
}
