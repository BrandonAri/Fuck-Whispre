import AppKit
import CoreGraphics

final class FnKeyMonitor {
    private enum KeyAction {
        case latch
        case finish
        case cancel
        case suppress
    }

    private let onPress: () -> Void
    private let onRelease: () -> Void
    private let onLatch: () -> Void
    private let onFinish: () -> Void
    private let onCancel: () -> Void
    private var globalFnMonitor: Any?
    private var localFnMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private let stateLock = NSLock()
    private var fnIsDown = false
    private var handsFreeActive = false
    private var cancellableActive = false
    private var suppressedKeyCodes: Set<Int64> = []

    init(
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void,
        onLatch: @escaping () -> Void,
        onFinish: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onPress = onPress
        self.onRelease = onRelease
        self.onLatch = onLatch
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    func start() {
        guard globalFnMonitor == nil else { return }
        globalFnMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFn(event)
        }
        localFnMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFn(event)
            return event
        }
        installKeyEventTap()
    }

    func updateInteractionState(handsFree: Bool, cancellable: Bool) {
        stateLock.withLock {
            handsFreeActive = handsFree
            cancellableActive = cancellable
        }
    }

    private func installKeyEventTap() {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handleKeyEvent(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleKeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            let wasSuppressed = stateLock.withLock { suppressedKeyCodes.remove(keyCode) != nil }
            return wasSuppressed ? nil : Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let action: KeyAction? = stateLock.withLock {
            let fnPressed = fnIsDown || event.flags.contains(.maskSecondaryFn)
            if keyCode == 49, fnPressed {
                suppressedKeyCodes.insert(keyCode)
                return .latch
            }
            if keyCode == 49, handsFreeActive {
                suppressedKeyCodes.insert(keyCode)
                return .finish
            }
            if keyCode == 53, cancellableActive {
                suppressedKeyCodes.insert(keyCode)
                return .cancel
            }
            // Return and keypad Enter must not stop hands-free dictation or
            // accidentally submit content in the focused app.
            if (keyCode == 36 || keyCode == 76), handsFreeActive {
                suppressedKeyCodes.insert(keyCode)
                return .suppress
            }
            return nil
        }

        switch action {
        case .latch: onLatch()
        case .finish: onFinish()
        case .cancel: onCancel()
        case .suppress: break
        case nil: return Unmanaged.passUnretained(event)
        }
        return nil
    }

    private func handleFn(_ event: NSEvent) {
        // 63 is the hardware key code emitted by the Fn/Globe key on Apple keyboards.
        guard event.keyCode == 63 else { return }
        let isDown = event.modifierFlags.contains(.function)
        let changed = stateLock.withLock { () -> Bool in
            guard isDown != fnIsDown else { return false }
            fnIsDown = isDown
            return true
        }
        guard changed else { return }
        isDown ? onPress() : onRelease()
    }

    deinit {
        if let globalFnMonitor { NSEvent.removeMonitor(globalFnMonitor) }
        if let localFnMonitor { NSEvent.removeMonitor(localFnMonitor) }
        if let eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
    }
}
