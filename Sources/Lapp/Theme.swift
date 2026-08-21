import AppKit

/// Every colour in the app comes from here. Nothing hard-codes white.
struct Theme {
    let surface: NSColor
    let text: NSColor
    let muted: NSColor
    let hairline: NSColor
    let button: NSColor
    let buttonHover: NSColor
    let tab: NSColor
    let accent: NSColor
    let codeBackground: NSColor
    let isDark: Bool

    static let light = Theme(
        surface: NSColor(calibratedWhite: 0.99, alpha: 1.0),
        text: NSColor(calibratedWhite: 0.17, alpha: 1.0),
        muted: NSColor(calibratedWhite: 0.62, alpha: 1.0),
        hairline: NSColor(calibratedWhite: 0.0, alpha: 0.055),
        button: NSColor(calibratedWhite: 0.45, alpha: 1.0),
        buttonHover: NSColor(calibratedWhite: 0.93, alpha: 1.0),
        tab: NSColor(calibratedWhite: 0.96, alpha: 1.0),
        accent: NSColor(calibratedRed: 0.77, green: 0.39, blue: 0.25, alpha: 1.0),
        codeBackground: NSColor(calibratedWhite: 0.94, alpha: 1.0),
        isDark: false
    )

    static let dark = Theme(
        surface: NSColor(calibratedWhite: 0.11, alpha: 1.0),
        text: NSColor(calibratedWhite: 0.88, alpha: 1.0),
        muted: NSColor(calibratedWhite: 0.45, alpha: 1.0),
        hairline: NSColor(calibratedWhite: 1.0, alpha: 0.065),
        button: NSColor(calibratedWhite: 0.62, alpha: 1.0),
        buttonHover: NSColor(calibratedWhite: 0.19, alpha: 1.0),
        tab: NSColor(calibratedWhite: 0.15, alpha: 1.0),
        accent: NSColor(calibratedRed: 0.85, green: 0.51, blue: 0.36, alpha: 1.0),
        codeBackground: NSColor(calibratedWhite: 0.17, alpha: 1.0),
        isDark: true
    )

    /// The configured background opacity, 0 -- 1.
    ///
    /// It is applied to the card's ground and the tab, and to nothing else. Fading the
    /// whole window (`panel.alphaValue`) would take the text with it, which is exactly
    /// what the setting is meant not to do.
    static var backgroundAlpha: CGFloat {
        min(max(Settings.shared.data.opacity, 0), 1)
    }

    /// A ground colour at the configured background opacity.
    static func ground(_ color: NSColor) -> NSColor {
        color.withAlphaComponent(color.alphaComponent * backgroundAlpha)
    }

    var groundSurface: NSColor { Theme.ground(surface) }

    static var current: Theme {
        switch Settings.shared.data.appearance {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let name = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return name == .darkAqua ? .dark : .light
        }
    }

    /// The NSAppearance the panel should adopt, so system controls inside it match.
    static var currentAppearance: NSAppearance? {
        switch Settings.shared.data.appearance {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }
}

/// Anything that repaints when the theme or font size changes.
protocol Themed: AnyObject {
    func applyTheme(_ theme: Theme)
}
