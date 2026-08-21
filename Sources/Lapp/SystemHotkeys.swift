import AppKit

/// What macOS itself has claimed.
///
/// `RegisterEventHotKey` is not a conflict check: it returns noErr for combinations the
/// system already owns (⌘Space registers "successfully" and then simply never fires).
/// So the check has to come from somewhere else -- the built-in defaults below, corrected
/// by whatever the user has changed in System Settings.
enum SystemHotkeys {
    struct Shortcut {
        var name: String
        var keyCode: UInt16
        var modifiers: NSEvent.ModifierFlags
    }

    private static let shift  = NSEvent.ModifierFlags.shift
    private static let ctrl   = NSEvent.ModifierFlags.control
    private static let option = NSEvent.ModifierFlags.option
    private static let cmd    = NSEvent.ModifierFlags.command

    /// macOS defaults, keyed by the symbolic hotkey id used in com.apple.symbolichotkeys.
    private static let defaults: [Int: Shortcut] = [
        27:  Shortcut(name: "Move focus to next window", keyCode: 50,  modifiers: [cmd]),
        28:  Shortcut(name: "Screenshot to file", keyCode: 20, modifiers: [cmd, shift]),
        29:  Shortcut(name: "Screenshot to clipboard", keyCode: 20, modifiers: [ctrl, cmd, shift]),
        30:  Shortcut(name: "Screenshot selection", keyCode: 21, modifiers: [cmd, shift]),
        31:  Shortcut(name: "Screenshot selection to clipboard", keyCode: 21, modifiers: [ctrl, cmd, shift]),
        32:  Shortcut(name: "Mission Control", keyCode: 126, modifiers: [ctrl]),
        33:  Shortcut(name: "Application windows", keyCode: 125, modifiers: [ctrl]),
        59:  Shortcut(name: "Next input source", keyCode: 49, modifiers: [ctrl, option]),
        60:  Shortcut(name: "Previous input source", keyCode: 49, modifiers: [ctrl]),
        64:  Shortcut(name: "Spotlight", keyCode: 49, modifiers: [cmd]),
        65:  Shortcut(name: "Finder search window", keyCode: 49, modifiers: [cmd, option]),
        79:  Shortcut(name: "Move left a space", keyCode: 123, modifiers: [ctrl]),
        80:  Shortcut(name: "Move right a space", keyCode: 124, modifiers: [ctrl]),
        81:  Shortcut(name: "Move up a space", keyCode: 126, modifiers: [ctrl]),
        82:  Shortcut(name: "Move down a space", keyCode: 125, modifiers: [ctrl]),
        160: Shortcut(name: "Launchpad", keyCode: 65535, modifiers: []),
        175: Shortcut(name: "Notification Centre", keyCode: 65535, modifiers: []),
        184: Shortcut(name: "Screenshot and recording options", keyCode: 23, modifiers: [cmd, shift])
    ]

    /// Not symbolic hotkeys, but every bit as taken.
    private static let fixed: [Shortcut] = [
        Shortcut(name: "the app switcher", keyCode: 48, modifiers: [cmd]),
        Shortcut(name: "the app switcher", keyCode: 48, modifiers: [cmd, shift]),
        Shortcut(name: "Force Quit", keyCode: 53, modifiers: [cmd, option]),
        Shortcut(name: "Lock Screen", keyCode: 12, modifiers: [ctrl, cmd])
    ]

    /// Nil when nothing known claims this combination. A third-party app holding it
    /// silently cannot be detected by any public API, so this is a warning, not a promise.
    static func claimant(of binding: KeyBinding) -> String? {
        let overrides = userOverrides()

        // Sorted so a combination claimed by two ids always reports the same name.
        for (id, fallback) in defaults.sorted(by: { $0.key < $1.key }) {
            if let override = overrides[id] {
                guard override.enabled else { continue }              // user switched it off
                if let shortcut = override.shortcut,
                   shortcut.keyCode == binding.keyCode,
                   shortcut.modifiers == binding.modifiers {
                    return fallback.name
                }
                if override.shortcut == nil,
                   fallback.keyCode == binding.keyCode,
                   fallback.modifiers == binding.modifiers {
                    return fallback.name
                }
            } else if fallback.keyCode == binding.keyCode, fallback.modifiers == binding.modifiers {
                return fallback.name
            }
        }

        for shortcut in fixed where shortcut.keyCode == binding.keyCode && shortcut.modifiers == binding.modifiers {
            return shortcut.name
        }
        return nil
    }

    // MARK: - The user's own changes

    private struct Override {
        var enabled: Bool
        var shortcut: Shortcut?
    }

    /// Only shortcuts the user has actually changed appear in this domain; everything
    /// else is a system default and lives in the table above.
    private static func userOverrides() -> [Int: Override] {
        guard let raw = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys") else { return [:] }

        var result: [Int: Override] = [:]
        for (key, value) in raw {
            guard let id = Int(key), let entry = value as? [String: Any] else { continue }
            let enabled = (entry["enabled"] as? NSNumber)?.boolValue ?? false
            var shortcut: Shortcut?
            if let container = entry["value"] as? [String: Any],
               let parameters = container["parameters"] as? [NSNumber], parameters.count >= 3 {
                let keyCode = parameters[1].intValue
                let modifiers = NSEvent.ModifierFlags(rawValue: parameters[2].uintValue)
                if keyCode != 65535 {
                    shortcut = Shortcut(name: "", keyCode: UInt16(keyCode),
                                        modifiers: modifiers.intersection(.deviceIndependentFlagsMask))
                }
            }
            result[id] = Override(enabled: enabled, shortcut: shortcut)
        }
        return result
    }
}
