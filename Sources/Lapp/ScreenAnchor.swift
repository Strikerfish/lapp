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
        let x = data.edge == .right ? area.maxX - width : area.minX
        let y = (area.midY - height / 2).rounded()
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Where the strip would land if dropped at this point -- used while dragging the tab.
    static func drop(at point: NSPoint) -> (screen: NSScreen, edge: ScreenEdge)? {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.screens.min { abs($0.frame.midX - point.x) < abs($1.frame.midX - point.x) }
        guard let screen else { return nil }
        return (screen, point.x < screen.frame.midX ? .left : .right)
    }
}
