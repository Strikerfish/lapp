import AppKit

protocol PadRootDelegate: AnyObject {
    func padTextDidChange(_ text: String)
    func padPerform(_ action: LappAction)
    func padSelectTab(_ index: Int)
    func padCloseTab(_ index: Int)
    func padEscape()
    func padToggleMinimized()
    func padTabDragged(to screenPoint: NSPoint)
    func padTabDropped(at screenPoint: NSPoint)
}

// MARK: - Icon button

final class IconButton: NSButton {
    private var hovering = false
    private var theme: Theme = .current

    init(symbol: String, tooltip: String, action: Selector, target: AnyObject?) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        toolTip = tooltip
        wantsLayer = true
        layer?.cornerRadius = 5
        let config = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .medium)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 27),
            heightAnchor.constraint(equalToConstant: 23)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        contentTintColor = theme.button
        layer?.backgroundColor = hovering ? theme.buttonHover.cgColor : NSColor.clear.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        applyTheme(theme)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        applyTheme(theme)
    }
}

// MARK: - Text view

final class LappTextView: NSTextView {
    weak var padDelegate: PadRootDelegate?

    override func cancelOperation(_ sender: Any?) {
        padDelegate?.padEscape()
    }

    /// The panel is non-activating, so it never becomes "main"; draw the caret anyway.
    override var shouldDrawInsertionPoint: Bool { isEditable && window?.isKeyWindow == true }

    /// Carries a list on to the next line, and ends it when an item is left empty.
    /// Goes through `insertText` so it lands in the undo stack like ordinary typing.
    override func insertNewline(_ sender: Any?) {
        let selection = selectedRange()
        guard selection.length == 0 else { return super.insertNewline(sender) }

        let text = string as NSString
        let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = text.substring(with: lineRange)
        let caret = selection.location - lineRange.location

        switch ListContinuation.outcome(for: line, caret: caret) {
        case .plain:
            super.insertNewline(sender)
        case .carryOn(let prefix):
            insertText("\n" + prefix, replacementRange: selection)
        case .endList(let prefixLength):
            let markerRange = NSRange(location: lineRange.location, length: prefixLength)
            insertText("", replacementRange: markerRange)
        }
    }
}

// MARK: - Container

/// Lays out the card and the tab by hand. The card is flush against the screen edge and
/// rounded only on the inner side; the tab is a nub protruding further inward, and is the
/// only thing left when the strip is minimised.
final class PadContainerView: NSView {
    let card = PadRootView()
    let tab = EdgeTabView()

    /// Set during the minimise/restore swipe. While it holds a value the card keeps this
    /// exact width and stays laid out as if expanded, so shrinking the window slides the
    /// card out through the screen edge and clips it, rather than squashing it.
    var swipingCardWidth: CGFloat? {
        didSet { needsLayout = true }
    }

    weak var delegate: PadRootDelegate? {
        didSet {
            card.delegate = delegate
            tab.delegate = delegate
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(card)
        addSubview(tab)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let data = Settings.shared.data
        let tabWidth = ScreenAnchor.Metrics.tabWidth
        let tabHeight = min(ScreenAnchor.Metrics.tabHeight, bounds.height)
        let onRight = data.edge == .right
        let tabY = ((bounds.height - tabHeight) / 2).rounded()

        if let cardWidth = swipingCardWidth {
            card.isHidden = false
            card.frame = NSRect(x: onRight ? tabWidth : bounds.width - tabWidth - cardWidth,
                                y: 0, width: cardWidth, height: bounds.height)
            tab.frame = NSRect(x: onRight ? 0 : bounds.width - tabWidth,
                               y: tabY, width: tabWidth, height: tabHeight)
        } else if data.minimized {
            card.isHidden = true
            tab.frame = NSRect(x: onRight ? bounds.width - tabWidth : 0,
                               y: tabY, width: tabWidth, height: tabHeight)
        } else {
            card.isHidden = false
            card.frame = NSRect(x: onRight ? tabWidth : 0, y: 0,
                                width: max(0, bounds.width - tabWidth), height: bounds.height)
            tab.frame = NSRect(x: onRight ? 0 : bounds.width - tabWidth,
                               y: tabY, width: tabWidth, height: tabHeight)
        }

        // Round only the corners that face into the screen; the outer side stays square so
        // the strip reads as continuous with the screen edge.
        let innerCorners: CACornerMask = onRight
            ? [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        card.layer?.maskedCorners = innerCorners
        tab.layer?.maskedCorners = innerCorners
        tab.pointsOutward = onRight
        tab.needsDisplay = true

        window?.invalidateShadow()
    }

    func applyTheme(_ theme: Theme) {
        card.applyTheme(theme)
        tab.applyTheme(theme)
    }
}

// MARK: - The tab

/// Click to minimise or restore. Drag to move the strip to the other side, or to another
/// screen -- it snaps to whichever edge you let go nearest.
final class EdgeTabView: NSView {
    weak var delegate: PadRootDelegate?
    var pointsOutward = true {
        didSet { if pointsOutward != oldValue { needsDisplay = true } }
    }

    private var theme: Theme = .current
    private var hovering = false
    private var dragStart: NSPoint?
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6.5
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        // The tab is part of the strip's surface, so it fades with it. The grip dots are
        // drawn at full strength, which is what keeps the handle findable at 0%.
        layer?.backgroundColor = Theme.ground(hovering ? theme.buttonHover : theme.tab).cgColor
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        applyTheme(theme)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        applyTheme(theme)
    }

    // MARK: Click vs drag

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let now = NSEvent.mouseLocation
        if !isDragging, hypot(now.x - start.x, now.y - start.y) > 4 { isDragging = true }
        if isDragging { delegate?.padTabDragged(to: now) }
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; isDragging = false }
        if isDragging {
            delegate?.padTabDropped(at: NSEvent.mouseLocation)
        } else {
            delegate?.padToggleMinimized()
        }
    }

    /// The card is hidden while minimised, so the tab has to carry the menu.
    override func menu(for event: NSEvent) -> NSMenu? {
        (superview as? PadContainerView)?.card.menu(for: event)
    }

    // MARK: Grip marks

    override func draw(_ dirtyRect: NSRect) {
        // Three faint dots: enough to read as a handle, quiet enough to ignore.
        let dot: CGFloat = 1.8
        let gap: CGFloat = 4.5
        let total = dot * 3 + gap * 2
        var y = bounds.midY + total / 2 - dot
        theme.muted.withAlphaComponent(0.55).setFill()
        for _ in 0..<3 {
            let rect = NSRect(x: bounds.midX - dot / 2, y: y, width: dot, height: dot)
            NSBezierPath(ovalIn: rect).fill()
            y -= dot + gap
        }
    }
}

// MARK: - Card

final class PadRootView: NSView {
    weak var delegate: PadRootDelegate? {
        didSet { textView.padDelegate = delegate }
    }

    let textView = LappTextView()
    let styler = MarkdownStyler()
    let tabBar = TabBarView()

    private let tabHairline = NSView()
    private let scrollView = NSScrollView()
    private let bar = NSView()
    private let hairline = NSView()
    private let placeholder = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private var buttons: [IconButton] = []
    private var overlay: NSView?
    private var overlayOffset: NSLayoutConstraint?
    private var statusTimer: Timer?

    private var theme: Theme = .current

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = ScreenAnchor.Metrics.cornerRadius
        layer?.masksToBounds = true
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Build

    private func build() {
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 11, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.delegate = styler

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        placeholder.stringValue = "Write something down."
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        bar.wantsLayer = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        hairline.wantsLayer = true
        hairline.translatesAutoresizingMaskIntoConstraints = false

        let file = IconButton(symbol: "checkmark", tooltip: "File", action: #selector(fileNote), target: self)
        let discard = IconButton(symbol: "xmark", tooltip: "Discard", action: #selector(discardNote), target: self)
        let history = IconButton(symbol: "list.bullet", tooltip: "History", action: #selector(showHistory), target: self)
        let settings = IconButton(symbol: "gearshape", tooltip: "Settings", action: #selector(showSettings), target: self)
        buttons = [file, discard, history, settings]

        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        status.font = NSFont.systemFont(ofSize: 10)
        status.alphaValue = 0
        status.lineBreakMode = .byTruncatingMiddle
        status.translatesAutoresizingMaskIntoConstraints = false

        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.onSelect = { [weak self] index in self?.delegate?.padSelectTab(index) }
        tabBar.onClose = { [weak self] index in self?.delegate?.padCloseTab(index) }
        tabBar.onNew = { [weak self] in self?.delegate?.padPerform(.newTab) }
        tabHairline.wantsLayer = true
        tabHairline.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(stack)
        bar.addSubview(status)
        addSubview(tabBar)
        addSubview(tabHairline)
        addSubview(scrollView)
        addSubview(placeholder)
        addSubview(hairline)
        addSubview(bar)

        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBar.topAnchor.constraint(equalTo: topAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: TabBarView.Metrics.height),

            tabHairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabHairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabHairline.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            tabHairline.heightAnchor.constraint(equalToConstant: 1),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: tabHairline.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: hairline.topAnchor),

            placeholder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            placeholder.topAnchor.constraint(equalTo: tabHairline.bottomAnchor, constant: 13),

            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bar.topAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 32),

            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 5),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            status.leadingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 6),
            status.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            status.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(textChanged),
                                               name: NSText.didChangeNotification, object: textView)
    }

    // MARK: Theme

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        // The card's ground is the only thing the opacity setting touches. Everything
        // drawn on it -- text, buttons, the overlays -- keeps its own alpha, which is
        // why the overlays are transparent and this layer shows through them.
        layer?.backgroundColor = theme.groundSurface.cgColor
        bar.layer?.backgroundColor = NSColor.clear.cgColor
        hairline.layer?.backgroundColor = theme.hairline.cgColor
        tabHairline.layer?.backgroundColor = theme.hairline.cgColor
        tabBar.applyTheme(theme)
        placeholder.textColor = theme.muted
        status.textColor = theme.muted
        buttons.forEach { $0.applyTheme(theme) }

        styler.theme = theme
        styler.baseSize = Settings.shared.data.fontSize
        placeholder.font = NSFont.systemFont(ofSize: Settings.shared.data.fontSize)
        textView.font = styler.baseFont
        textView.textColor = theme.text
        textView.insertionPointColor = theme.accent
        textView.typingAttributes = styler.baseAttributes
        textView.selectedTextAttributes = [.backgroundColor: theme.accent.withAlphaComponent(0.22)]
        if let storage = textView.textStorage { styler.styleAll(storage) }

        (overlay as? Themed)?.applyTheme(theme)
    }

    // MARK: Text

    var text: String {
        get { textView.string }
        set {
            textView.string = newValue
            if let storage = textView.textStorage { styler.styleAll(storage) }
            textView.typingAttributes = styler.baseAttributes
            updatePlaceholder()
        }
    }

    func focusText(moveCaretToEnd: Bool) {
        window?.makeFirstResponder(textView)
        if moveCaretToEnd {
            let end = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: end, length: 0))
            textView.scrollRangeToVisible(NSRange(location: end, length: 0))
        }
    }

    @objc private func textChanged() {
        updatePlaceholder()
        delegate?.padTextDidChange(textView.string)
    }

    private func updatePlaceholder() {
        placeholder.isHidden = !textView.string.isEmpty || hasOverlay
    }

    // MARK: Actions

    @objc private func fileNote() { delegate?.padPerform(.fileNote) }
    @objc private func discardNote() { delegate?.padPerform(.discardNote) }
    @objc private func showHistory() { delegate?.padPerform(.history) }
    @objc private func showSettings() { delegate?.padPerform(.settings) }

    // MARK: Status flash

    func flash(_ message: String) {
        status.stringValue = message
        statusTimer?.invalidate()
        Motion.run(Motion.fade) { status.animator().alphaValue = 1 }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Motion.run(0.4) { self?.status.animator().alphaValue = 0 }
        }
    }

    // MARK: Overlay

    var hasOverlay: Bool { overlay != nil }

    func present(_ view: NSView) {
        dismissOverlay(animated: false)
        // Hidden immediately, not on completion: the overlays draw no background of their
        // own so the card's ground can carry the opacity, and text left underneath would
        // read straight through them.
        setPadContentHidden(true)
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        let offset = view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: bounds.width)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalTo: widthAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: hairline.topAnchor),
            offset
        ])
        overlay = view
        (view as? Themed)?.applyTheme(theme)
        layoutSubtreeIfNeeded()
        overlayOffset = offset
        Motion.run(Motion.overlay) { offset.animator().constant = 0 }
    }

    func dismissOverlay(animated: Bool = true) {
        guard let view = overlay else { return }
        overlay = nil
        setPadContentHidden(false)
        guard animated, let offset = overlayOffset else {
            overlayOffset = nil
            view.removeFromSuperview()
            return
        }
        overlayOffset = nil
        // Slides back out the way it came in, rather than fading on the spot.
        Motion.run(Motion.overlay, {
            offset.animator().constant = bounds.width
            view.animator().alphaValue = 0
        }, then: { view.removeFromSuperview() })
    }

    /// The pad itself, minus the button bar, which stays visible behind an overlay.
    private func setPadContentHidden(_ hidden: Bool) {
        scrollView.isHidden = hidden
        tabBar.isHidden = hidden
        tabHairline.isHidden = hidden
        // Not via `updatePlaceholder`: this runs before `overlay` is assigned.
        placeholder.isHidden = hidden || !textView.string.isEmpty
    }

    // MARK: Right-click menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        let screens = NSScreen.screens
        if screens.count > 1 {
            let header = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            let current = ScreenAnchor.targetScreen()
            for screen in screens {
                let item = NSMenuItem(title: "  " + screen.localizedName,
                                      action: #selector(chooseScreen(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ScreenAnchor.displayID(of: screen)
                item.state = screen == current ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let flip = NSMenuItem(title: Settings.shared.data.edge == .right ? "Move to Left Edge" : "Move to Right Edge",
                              action: #selector(flipEdge), keyEquivalent: "")
        flip.target = self
        menu.addItem(flip)

        menu.addItem(.separator())
        let obsidian = NSMenuItem(title: "Send to Obsidian", action: #selector(sendToObsidian), keyEquivalent: "")
        obsidian.target = self
        menu.addItem(obsidian)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        let quit = NSMenuItem(title: "Quit Lapp", action: #selector(quit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func chooseScreen(_ sender: NSMenuItem) {
        Settings.shared.update { $0.displayID = sender.representedObject as? String }
    }

    @objc private func flipEdge() {
        Settings.shared.update { $0.edge = $0.edge == .right ? .left : .right }
    }

    @objc private func sendToObsidian() { delegate?.padPerform(.sendToObsidian) }
    @objc private func toggleLoginItem() { LoginItem.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}
