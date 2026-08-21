import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let lappGlobalHotkeyStatus = Notification.Name("no.hoen.lapp.globalHotkeyStatus")
}

/// One binding per action. `focusPad` is registered system-wide through Carbon --
/// chosen over an NSEvent global monitor because it needs no Accessibility permission,
/// and because it reports failure, which is what lets Settings say a combination is taken.
final class Hotkeys {
    static let shared = Hotkeys()

    var handler: ((LappAction) -> Void)?
    /// ⌘1 … ⌘9 jump straight to a tab. Fixed rather than rebindable: nine more rows would
    /// bury the ten bindings in Settings that are worth changing.
    var tabHandler: ((Int) -> Void)?
    /// Set while a hotkey is being recorded, so recording doesn't trigger the action.
    var isSuspended = false
    private(set) var globalError: String?
    /// Set when a known macOS shortcut already owns the combination.
    private(set) var systemClaimant: String?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var localMonitor: Any?

    private init() {}

    func start() {
        installCarbonHandler()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleLocal(event) == true ? nil : event
        }
        reload()
    }

    // MARK: - Global

    func reload() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        globalError = nil
        systemClaimant = nil

        guard let binding = Settings.shared.binding(for: .focusPad) else {
            NotificationCenter.default.post(name: .lappGlobalHotkeyStatus, object: nil)
            return
        }

        systemClaimant = SystemHotkeys.claimant(of: binding)

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4C415050), id: 1) // 'LAPP'
        let status = RegisterEventHotKey(UInt32(binding.keyCode),
                                         Self.carbonModifiers(binding.modifiers),
                                         id,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            globalError = status == OSStatus(eventHotKeyExistsErr)
                ? "already used by another app"
                : "unavailable (error \(status))"
        }
        NotificationCenter.default.post(name: .lappGlobalHotkeyStatus, object: nil)
    }

    private func installCarbonHandler() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                guard !Hotkeys.shared.isSuspended else { return }
                Hotkeys.shared.handler?(.focusPad)
            }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.shift)   { value |= UInt32(shiftKey) }
        if flags.contains(.option)  { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        return value
    }

    // MARK: - Local

    /// Returns true when the event was consumed.
    private func handleLocal(_ event: NSEvent) -> Bool {
        guard !isSuspended else { return false }
        for action in LappAction.allCases where !action.isGlobal {
            if let binding = Settings.shared.binding(for: action), binding.matches(event) {
                handler?(action)
                return true
            }
        }
        // Tested after the bindings, so rebinding something to ⌘1 still wins.
        if let digit = Self.digitKeys[event.keyCode],
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let tabHandler {
            tabHandler(digit)
            return true
        }
        return false
    }

    private static let digitKeys: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
    ]
}
