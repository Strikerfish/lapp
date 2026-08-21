import AppKit
import ServiceManagement

final class AppController: NSObject, NSApplicationDelegate, PadRootDelegate {
    private let panel = PadPanel()
    private let container = PadContainerView()
    private var root: PadRootView { container.card }
    private var saveWork: DispatchWorkItem?
    private var previousApp: NSRunningApplication?
    private var lastFocusBinding: KeyBinding?
    private var lastGeometry = ""
    private var dragAnchor: (origin: NSPoint, mouse: NSPoint)?
    /// Set while the controller is driving the panel frame itself.
    private var suppressReposition = false

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensureRoot()
        Store.shared.purgeTrash()
        buildMenu()

        container.delegate = self
        panel.contentView = container
        root.text = Store.shared.loadDraft()
        applyAppearance()

        lastGeometry = geometryKey()
        panel.reposition()
        panel.orderFrontRegardless()

        lastFocusBinding = Settings.shared.binding(for: .focusPad)
        Hotkeys.shared.handler = { [weak self] action in self?.padPerform(action) }
        Hotkeys.shared.start()

        LoginItem.enableIfNeeded()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(settingsChanged),
                           name: .lappSettingsChanged, object: nil)
        center.addObserver(self, selector: #selector(screensChanged),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screensChanged),
            name: NSWorkspace.didWakeNotification, object: nil)

        DistributedNotificationCenter.default.addObserver(
            self, selector: #selector(systemAppearanceChanged),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        flushDraft()
        return .terminateNow
    }

    // MARK: - Menu

    /// LSUIElement apps have no visible menu bar, but the main menu is still what routes
    /// ⌘C / ⌘V / ⌘Z to the text view.
    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit Lapp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        let entries: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Undo", Selector(("undo:")), "z", [.command]),
            ("Redo", Selector(("redo:")), "z", [.command, .shift]),
            ("Cut", #selector(NSText.cut(_:)), "x", [.command]),
            ("Copy", #selector(NSText.copy(_:)), "c", [.command]),
            ("Paste", #selector(NSText.paste(_:)), "v", [.command]),
            ("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]),
            ("Select All", #selector(NSText.selectAll(_:)), "a", [.command])
        ]
        for (title, action, key, modifiers) in entries {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            edit.addItem(item)
        }
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    // MARK: - Appearance

    private func applyAppearance() {
        panel.appearance = Theme.currentAppearance
        panel.alphaValue = min(max(Settings.shared.data.opacity, 0.35), 1.0)
        container.applyTheme(Theme.current)
    }

    /// Changes that move or resize the strip are worth animating; a font-size nudge isn't.
    private func geometryKey() -> String {
        let data = Settings.shared.data
        return "\(data.edge.rawValue)|\(data.minimized)|\(data.displayID ?? "auto")"
    }

    @objc private func systemAppearanceChanged() {
        guard Settings.shared.data.appearance == .system else { return }
        DispatchQueue.main.async { self.applyAppearance() }
    }

    @objc private func settingsChanged() {
        applyAppearance()
        container.needsLayout = true
        let key = geometryKey()
        let moved = key != lastGeometry
        lastGeometry = key
        if !suppressReposition { panel.reposition(animated: moved) }
        let binding = Settings.shared.binding(for: .focusPad)
        if binding != lastFocusBinding {
            lastFocusBinding = binding
            Hotkeys.shared.reload()
        }
    }

    @objc private func screensChanged() {
        // Screens can still be settling right after a wake or a replug.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            self.panel.reposition()
            self.panel.orderFrontRegardless()
        }
    }

    // MARK: - PadRootDelegate

    func padTextDidChange(_ text: String) {
        saveWork?.cancel()
        let work = DispatchWorkItem { Store.shared.saveDraft(text) }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func flushDraft() {
        saveWork?.cancel()
        saveWork = nil
        Store.shared.saveDraft(root.text)
    }

    func padPerform(_ action: LappAction) {
        switch action {
        case .focusPad:      focusPad()
        case .fileNote:      fileNote()
        case .discardNote:   discardNote()
        case .history:       toggleHistory()
        case .settings:      toggleSettings()
        case .sendToObsidian: sendCurrentToObsidian()
        }
    }

    func padToggleMinimized() {
        setMinimized(!Settings.shared.data.minimized)
    }

    /// The card slides out through the screen edge and is clipped by it, rather than
    /// blinking away. The window's outer edge stays pinned while its width animates, and
    /// `swipingCardWidth` holds the card at full size so it travels instead of squashing.
    ///
    /// Only the width is animated. The height change is invisible: once the card has gone,
    /// the only thing drawn is the tab, and the window is transparent everywhere else.
    private func setMinimized(_ minimize: Bool) {
        guard let screen = ScreenAnchor.targetScreen() else { return }
        let onRight = Settings.shared.data.edge == .right
        let cardWidth = ScreenAnchor.cardWidth(on: screen)

        // Held across the animation, not just the synchronous set-up: the minimise branch
        // writes the setting from its completion handler, and `Settings.update` posts
        // `settingsChanged` synchronously. Without the flag still up, that observer would
        // start its own animated reposition on top of the one finishing here.
        suppressReposition = true

        if minimize {
            flushDraft()
            root.dismissOverlay(animated: false)
            container.swipingCardWidth = cardWidth

            var collapsed = panel.frame
            collapsed.size.width -= cardWidth
            if onRight { collapsed.origin.x += cardWidth }

            Motion.run(Motion.swipe, {
                panel.animator().setFrame(collapsed, display: true)
            }, then: { [weak self] in
                guard let self else { return }
                self.container.swipingCardWidth = nil
                Settings.shared.update { $0.minimized = true }
                self.lastGeometry = self.geometryKey()
                self.panel.setFrame(ScreenAnchor.frame(on: screen), display: true)
                self.suppressReposition = false
            })
        } else {
            Settings.shared.update { $0.minimized = false }
            lastGeometry = geometryKey()

            let target = ScreenAnchor.frame(on: screen)
            var collapsed = target
            collapsed.size.width -= cardWidth
            if onRight { collapsed.origin.x += cardWidth }

            container.swipingCardWidth = cardWidth
            panel.setFrame(collapsed, display: true)
            panel.orderFrontRegardless()

            Motion.run(Motion.swipe, {
                panel.animator().setFrame(target, display: true)
            }, then: { [weak self] in
                guard let self else { return }
                self.container.swipingCardWidth = nil
                self.panel.makeKey()
                self.root.focusText(moveCaretToEnd: true)
                self.suppressReposition = false
            })
        }
    }

    func padTabDragged(to screenPoint: NSPoint) {
        if dragAnchor == nil { dragAnchor = (panel.frame.origin, screenPoint) }
        guard let anchor = dragAnchor else { return }
        // Horizontal only -- the strip is always vertically centred on its screen.
        var frame = panel.frame
        frame.origin.x = anchor.origin.x + (screenPoint.x - anchor.mouse.x)
        panel.setFrame(frame, display: true)
    }

    func padTabDropped(at screenPoint: NSPoint) {
        dragAnchor = nil
        guard let drop = ScreenAnchor.drop(at: screenPoint) else {
            panel.reposition(animated: true)
            return
        }
        let id = ScreenAnchor.displayID(of: drop.screen)
        Settings.shared.update {
            $0.displayID = id
            $0.edge = drop.edge
        }
        panel.reposition(animated: true)
    }

    func padEscape() {
        if root.hasOverlay {
            root.dismissOverlay()
            root.focusText(moveCaretToEnd: false)
            return
        }
        returnFocus()
    }

    // MARK: - Actions

    private func focusPad() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
        if Settings.shared.data.minimized {
            setMinimized(false)
            return
        }
        root.dismissOverlay()
        panel.orderFrontRegardless()
        panel.makeKey()
        root.focusText(moveCaretToEnd: true)
    }

    private func returnFocus() {
        panel.resignKey()
        if let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        self.previousApp = nil
    }

    private func fileNote() {
        flushDraft()
        let text = root.text
        if Store.shared.file(text) != nil {
            root.flash("Filed")
        }
        root.text = ""
        Store.shared.saveDraft("")
    }

    private func discardNote() {
        flushDraft()
        Store.shared.discard(root.text)
        root.text = ""
        Store.shared.saveDraft("")
        root.flash("Discarded")
    }

    private func toggleHistory() {
        if root.hasOverlay {
            root.dismissOverlay()
            root.focusText(moveCaretToEnd: false)
            return
        }
        let view = HistoryView()
        view.onClose = { [weak self] in
            self?.root.dismissOverlay()
            self?.root.focusText(moveCaretToEnd: false)
        }
        view.onOpen = { [weak self] note in
            guard let self else { return }
            self.flushDraft()
            // Anything already on the pad is filed first, so nothing is lost by swapping.
            if !self.root.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Store.shared.file(self.root.text)
            }
            self.root.text = Store.shared.take(note)
            self.root.dismissOverlay()
            self.root.focusText(moveCaretToEnd: true)
        }
        view.onDelete = { note in Store.shared.delete(note) }
        view.onSend = { [weak self] note in
            let raw = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
            let body = Store.stripFrontMatter(raw)
            let result = ObsidianExport.send(body: body, created: note.filed)
            self?.report(result)
            if case .sent = result { Store.shared.delete(note) }
        }
        root.present(view)
    }

    private func toggleSettings() {
        if root.hasOverlay {
            root.dismissOverlay()
            root.focusText(moveCaretToEnd: false)
            return
        }
        let view = SettingsView()
        view.onClose = { [weak self] in
            self?.root.dismissOverlay()
            self?.root.focusText(moveCaretToEnd: false)
        }
        root.present(view)
    }

    private func sendCurrentToObsidian() {
        flushDraft()
        let result = ObsidianExport.send(body: root.text, created: Store.shared.draftCreated)
        report(result)
        if case .sent = result {
            Store.shared.discard("")   // resets the draft's created stamp
            root.text = ""
            Store.shared.saveDraft("")
        }
    }

    private func report(_ result: ObsidianExport.Result) {
        switch result {
        case .sent(let path):  root.flash("→ \(path)")
        case .noVault:         root.flash("No Obsidian vault configured")
        case .empty:           root.flash("Nothing to send")
        case .failed(let why): root.flash("Failed: \(why)")
        }
    }
}

// MARK: - Login item

enum LoginItem {
    private static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isBundled else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func enableIfNeeded() {
        guard isBundled, SMAppService.mainApp.status != .enabled else { return }
        try? SMAppService.mainApp.register()
    }

    static func toggle() {
        guard isBundled else { return }
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }
}

// MARK: - Bootstrap

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = AppController()
app.delegate = controller
app.run()
