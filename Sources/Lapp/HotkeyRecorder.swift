import AppKit

/// Click it, press the combination you want. Escape cancels, Delete clears.
final class HotkeyRecorderView: NSView, Themed {
    var onChange: ((KeyBinding?) -> Void)?

    private let action: LappAction
    private let label = NSTextField(labelWithString: "")
    private var recording = false
    private var monitor: Any?
    private var theme: Theme = .current

    init(action: LappAction) {
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 6),
            heightAnchor.constraint(equalToConstant: 22),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 62)
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { stop() }

    func refresh() {
        if recording {
            label.stringValue = "Press keys"
        } else if let binding = Settings.shared.binding(for: action) {
            label.stringValue = binding.display
        } else {
            label.stringValue = "None"
        }
        applyTheme(theme)
    }

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        layer?.borderColor = (recording ? theme.accent : theme.hairline).cgColor
        layer?.backgroundColor = (recording ? theme.accent.withAlphaComponent(0.10) : theme.buttonHover).cgColor
        label.textColor = recording ? theme.accent : theme.text
    }

    override func mouseDown(with event: NSEvent) {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        Hotkeys.shared.isSuspended = true
        refresh()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.capture(event)
            return nil
        }
    }

    private func stop() {
        recording = false
        Hotkeys.shared.isSuspended = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        refresh()
    }

    private func capture(_ event: NSEvent) {
        switch event.keyCode {
        case 53:            // Escape cancels
            stop()
            return
        case 51, 117:       // Delete clears
            stop()
            onChange?(nil)
            return
        default:
            break
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // A bare letter would swallow typing; require at least one modifier unless it's a function key.
        let isFunctionKey = modifiers.contains(.function) || (event.keyCode >= 96 && event.keyCode <= 122)
        guard !modifiers.subtracting([.function, .capsLock]).isEmpty || isFunctionKey else {
            NSSound.beep()
            return
        }

        stop()
        onChange?(KeyBinding(keyCode: event.keyCode, modifiers: modifiers))
    }
}
