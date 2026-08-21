import AppKit

/// A borderless, non-activating panel: it takes keystrokes without making Lapp the
/// active app, so the thing you were working in stays frontmost.
final class PadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 600),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    /// Keeps the strip pinned to its edge after a screen change, a wake, or a resize.
    func reposition(animated: Bool = false) {
        guard let screen = ScreenAnchor.targetScreen() else { return }
        let target = ScreenAnchor.frame(on: screen)
        guard frame != target else { return }
        if animated {
            Motion.run(Motion.travel) { animator().setFrame(target, display: true) }
        } else {
            setFrame(target, display: true)
        }
        contentView?.needsLayout = true
    }
}
