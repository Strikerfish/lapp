import AppKit

// MARK: - Actions

/// The order here is the order Settings lists them in, and the order the local key
/// monitor tests them in -- so a more specific combination must come before a looser one.
enum LappAction: String, CaseIterable, Codable {
    case focusPad
    case fileNote
    case discardNote
    case newTab
    case closeTab
    case nextTab
    case previousTab
    case history
    case settings
    case sendToObsidian

    var title: String {
        switch self {
        case .focusPad: return "Focus pad"
        case .fileNote: return "File"
        case .discardNote: return "Discard"
        case .newTab: return "New tab"
        case .closeTab: return "Close tab"
        case .nextTab: return "Next tab"
        case .previousTab: return "Previous tab"
        case .history: return "History"
        case .settings: return "Settings"
        case .sendToObsidian: return "Send to Obsidian"
        }
    }

    /// Only `focusPad` is registered system-wide; the rest fire while the pad has focus.
    var isGlobal: Bool { self == .focusPad }

    var defaultBinding: KeyBinding {
        switch self {
        case .focusPad:        return KeyBinding(keyCode: 49, modifiers: [.option])            // ⌥Space
        case .fileNote:        return KeyBinding(keyCode: 36, modifiers: [.command])           // ⌘↩
        case .discardNote:     return KeyBinding(keyCode: 51, modifiers: [.command])           // ⌘⌫
        case .newTab:          return KeyBinding(keyCode: 17, modifiers: [.command])           // ⌘T
        case .closeTab:        return KeyBinding(keyCode: 13, modifiers: [.command])           // ⌘W
        case .nextTab:         return KeyBinding(keyCode: 48, modifiers: [.control])           // ⌃⇥
        case .previousTab:     return KeyBinding(keyCode: 48, modifiers: [.control, .shift])   // ⌃⇧⇥
        case .history:         return KeyBinding(keyCode: 37, modifiers: [.command])           // ⌘L
        case .settings:        return KeyBinding(keyCode: 43, modifiers: [.command])           // ⌘,
        case .sendToObsidian:  return KeyBinding(keyCode: 31, modifiers: [.command, .shift])   // ⌘⇧O
        }
    }
}

// MARK: - Key bindings

struct KeyBinding: Codable, Equatable {
    var keyCode: UInt16
    var modifierRawValue: UInt

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierRawValue = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue).intersection(.deviceIndependentFlagsMask)
    }

    /// Human-readable, e.g. "⌥Space" or "⌘⇧O".
    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + KeyCodes.name(for: keyCode)
    }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers
    }
}

enum KeyCodes {
    private static let named: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        43: ",", 47: ".", 44: "/", 39: "'", 41: ";", 27: "-", 24: "=",
        33: "[", 30: "]", 42: "\\", 50: "`"
    ]

    private static let letters: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
        15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
        28: "8", 25: "9"
    ]

    static func name(for code: UInt16) -> String {
        named[code] ?? letters[code] ?? "Key \(code)"
    }
}

// MARK: - Settings

enum AppearanceMode: String, Codable, CaseIterable {
    case light, dark, system
    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }
}

enum ScreenEdge: String, Codable {
    case left, right
}

struct SettingsData: Codable {
    var displayID: String?          // CGDisplay UUID string, nil = auto
    var edge: ScreenEdge = .right
    var width: CGFloat = 300
    var heightFraction: CGFloat = 0.48
    var minimized: Bool = false
    var appearance: AppearanceMode = .system
    var opacity: CGFloat = 0.90
    var fontSize: CGFloat = 13
    var bindings: [String: KeyBinding] = [:]
    var vaultPath: String?          // absolute path to the vault root
    var vaultFolder: String = ""    // path relative to the vault root, "" = root

    static let `default` = SettingsData()

    init() {}

    /// Decoded key by key. Swift's synthesised `init(from:)` throws on a missing key even
    /// when the property has a default, which would mean that adding any field silently
    /// resets every setting the user has. Each key falls back to its default instead.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SettingsData()
        displayID      = try c.decodeIfPresent(String.self, forKey: .displayID)
        edge           = try c.decodeIfPresent(ScreenEdge.self, forKey: .edge) ?? fallback.edge
        width          = try c.decodeIfPresent(CGFloat.self, forKey: .width) ?? fallback.width
        heightFraction = try c.decodeIfPresent(CGFloat.self, forKey: .heightFraction) ?? fallback.heightFraction
        minimized      = try c.decodeIfPresent(Bool.self, forKey: .minimized) ?? fallback.minimized
        appearance     = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? fallback.appearance
        opacity        = try c.decodeIfPresent(CGFloat.self, forKey: .opacity) ?? fallback.opacity
        fontSize       = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? fallback.fontSize
        bindings       = try c.decodeIfPresent([String: KeyBinding].self, forKey: .bindings) ?? fallback.bindings
        vaultPath      = try c.decodeIfPresent(String.self, forKey: .vaultPath)
        vaultFolder    = try c.decodeIfPresent(String.self, forKey: .vaultFolder) ?? fallback.vaultFolder
    }
}

extension Notification.Name {
    static let lappSettingsChanged = Notification.Name("no.hoen.lapp.settingsChanged")
}

final class Settings {
    static let shared = Settings()

    private(set) var data: SettingsData
    private let url = Paths.root.appendingPathComponent("settings.json")

    private init() {
        if let bytes = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(SettingsData.self, from: bytes) {
            data = decoded
        } else {
            data = .default
        }
    }

    func binding(for action: LappAction) -> KeyBinding? {
        // A stored binding wins; absence of the key means "never customised" -> default.
        // An explicitly cleared binding is stored as a sentinel with keyCode == .max.
        guard let stored = data.bindings[action.rawValue] else { return action.defaultBinding }
        return stored.keyCode == UInt16.max ? nil : stored
    }

    func setBinding(_ binding: KeyBinding?, for action: LappAction) {
        if let binding {
            data.bindings[action.rawValue] = binding
        } else {
            data.bindings[action.rawValue] = KeyBinding(keyCode: UInt16.max, modifiers: [])
        }
        save()
    }

    func resetBinding(for action: LappAction) {
        data.bindings.removeValue(forKey: action.rawValue)
        save()
    }

    /// The action already using this combination, if any.
    func conflict(for binding: KeyBinding, excluding action: LappAction) -> LappAction? {
        LappAction.allCases.first { $0 != action && self.binding(for: $0) == binding }
    }

    func update(_ mutate: (inout SettingsData) -> Void) {
        mutate(&data)
        save()
    }

    private func save() {
        Paths.ensureRoot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let bytes = try? encoder.encode(data) {
            try? bytes.write(to: url, options: .atomic)
        }
        NotificationCenter.default.post(name: .lappSettingsChanged, object: nil)
    }
}

// MARK: - Paths

enum Paths {
    /// Deliberately outside the iCloud-synced Documents tree.
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Lapp")
    static var notes: URL { root.appendingPathComponent("notes") }
    static var trash: URL { root.appendingPathComponent("trash") }
    static var drafts: URL { root.appendingPathComponent("drafts") }
    /// Where the one draft lived before tabs. Read once, by the migration in `Store`.
    static var draft: URL { root.appendingPathComponent("current.md") }

    static func ensureRoot() {
        for dir in [root, notes, trash, drafts] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
