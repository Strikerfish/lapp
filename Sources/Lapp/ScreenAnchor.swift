import AppKit

/// Works out which display the strip lives on and what rectangle it occupies.
///
/// The strip sits flush against the screen edge -- no outer inset -- so it reads as
/// something extending out of the side of the screen rather than a window parked near it.
/// The tab is a nub protruding from the inner side; when minimised it is all that's left.
enum ScreenAnchor {
    enum Metrics {
        static let tabWidth: CGFloat = 13
        static let tabHeight: CGFloat = 50
        static let minCardWidth: CGFloat = 200
        static let cornerRadius: CGFloat = 10
    }

    /// Stable across replugs, unlike the index in `NSScreen.screens`.
    static func displayID(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String? else { return nil }
        return string
    }

    static func screen(withID id: String) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    /// The configured display, or -- when nothing is configured or it has been unplugged --
    /// the side screen: the one that isn't carrying the menu bar.
    static func targetScreen() -> NSScreen? {
        if let id = Settings.shared.data.displayID, let screen = screen(withID: id) { return screen }
        let screens = NSScreen.screens
        guard let main = NSScreen.main ?? screens.first else { return nil }
        return screens.first { $0 != main } ?? main
    }

    static func cardWidth(on screen: NSScreen) -> CGFloat {
        min(max(Settings.shared.data.width, Metrics.minCardWidth), screen.visibleFrame.width * 0.6)
    }

    static func frame(on screen: NSScreen) -> NSRect {
        let data = Settings.shared.data
        let area = screen.visibleFrame
        let width = data.minimized ? Metrics.tabWidth : cardWidth(on: screen) + Metrics.tabWidth
        let height = data.minimized
            ? Metrics.tabHeight
            : (area.height * min(max(data.heightFraction, 0.2), 1.0)).rounded()

        // Pinned, x comes from the edge and only y is the user's; free, both are.
        let expandedWidth = cardWidth(on: screen) + Metrics.tabWidth
        let expandedX = area.minX + area.width * data.horizontalFraction - expandedWidth / 2
        let x: CGFloat
        if data.free {
            // Minimised, the window is only the tab. It stays where the card's outer edge
            // was -- the same edge the minimise swipe pins while it animates -- so the
            // strip doesn't hop sideways as it closes.
            x = data.minimized && data.edge == .right
                ? expandedX + expandedWidth - Metrics.tabWidth
                : expandedX
        } else {
            x = data.edge == .right ? area.maxX - width : area.minX
        }
        let y = area.maxY - area.height * data.verticalFraction - height / 2

        // Clamped rather than trusted: a fraction that was fine on one display can put
        // the strip off the edge of a smaller one.
        return NSRect(x: min(max(x, area.minX), area.maxX - width).rounded(),
                      y: min(max(y, area.minY), area.maxY - height).rounded(),
                      width: width, height: height)
    }

    /// A minimised window is only the tab, but the stored fractions describe the whole
    /// strip. This is the rectangle the card would occupy if it were expanded where the
    /// tab now is, so dragging the nub about leaves the card where you would expect it.
    static func expandedEquivalent(of frame: NSRect, on screen: NSScreen) -> NSRect {
        let data = Settings.shared.data
        guard data.minimized else { return frame }
        var result = frame
        result.size.width = cardWidth(on: screen) + Metrics.tabWidth
        result.origin.x = data.edge == .right ? frame.maxX - result.width : frame.minX
        return result
    }

    /// The inverse of `frame(on:)` -- where a window that has just been dragged sits, as
    /// the fractions that will put it back there.
    static func fractions(of frame: NSRect, on screen: NSScreen) -> (horizontal: CGFloat, vertical: CGFloat) {
        let area = screen.visibleFrame
        guard area.width > 0, area.height > 0 else { return (0.5, 0.5) }
        let horizontal = (frame.midX - area.minX) / area.width
        let vertical = (area.maxY - frame.midY) / area.height
        return (min(max(horizontal, 0), 1), min(max(vertical, 0), 1))
    }

    /// Where the strip would land if dropped at this point -- used while dragging the tab.
    static func drop(at point: NSPoint) -> (screen: NSScreen, edge: ScreenEdge)? {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.screens.min { abs($0.frame.midX - point.x) < abs($1.frame.midX - point.x) }
        guard let screen else { return nil }
        return (screen, point.x < screen.frame.midX ? .left : .right)
    }
}
