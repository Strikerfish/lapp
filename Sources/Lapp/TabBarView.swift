import AppKit

/// The row of open notes across the top of the card, plus the + that opens another.
///
/// Widths are computed in `layout()` rather than left to a stack view: the strip is narrow
/// enough that chips have to share whatever is there, shrinking to `Metrics.minChip` and
/// then scrolling once even that doesn't fit.
final class TabBarView: NSView, Themed {
    enum Metrics {
        static let height: CGFloat = 26
        static let minChip: CGFloat = 70
        static let maxChip: CGFloat = 150
        static let spacing: CGFloat = 3
        static let inset: CGFloat = 5
    }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNew: (() -> Void)?

    private let scrollView = NSScrollView()
    private let row = NSView()
    private let plus: IconButton
    private var chips: [TabChip] = []
    private var theme: Theme = .current
    private var laidOutWidth: CGFloat = -1
    private var revealPending = false

    override init(frame frameRect: NSRect) {
        plus = IconButton(symbol: "plus", tooltip: "New tab", action: #selector(newTab), target: nil)
        super.init(frame: frameRect)
        wantsLayer = true
        plus.target = self

        scrollView.documentView = row
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        addSubview(plus)

        NSLayoutConstraint.activate([
            plus.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.inset),
            plus.centerYAnchor.constraint(equalTo: centerYAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.inset),
            scrollView.trailingAnchor.constraint(equalTo: plus.leadingAnchor, constant: -2),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Contents

    /// Rebuilds only when the number of tabs changed; otherwise the labels are updated in
    /// place, so typing the first line of a note doesn't rebuild the bar on every keystroke.
    func setTabs(_ titles: [String], active: Int) {
        var rebuilt = false
        if chips.count != titles.count {
            chips.forEach { $0.removeFromSuperview() }
            chips = titles.indices.map { index in
                let chip = TabChip()
                chip.onSelect = { [weak self] in self?.onSelect?(index) }
                chip.onClose = { [weak self] in self?.onClose?(index) }
                row.addSubview(chip)
                return chip
            }
            rebuilt = true
            laidOutWidth = -1
        }
        for (index, chip) in chips.enumerated() {
            let isActive = index == active
            if chip.title != titles[index] { chip.title = titles[index] }
            // Repainted only when the selection actually moved: this runs on every
            // keystroke, to follow the first line of the note being typed.
            if rebuilt || chip.isActive != isActive {
                chip.isActive = isActive
                chip.applyTheme(theme)
                if isActive { revealPending = true }
            }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard !chips.isEmpty else { return }
        let available = scrollView.contentSize.width
        let spacing = Metrics.spacing
        let ideal = (available - spacing * CGFloat(chips.count - 1)) / CGFloat(chips.count)
        let width = min(max(ideal, Metrics.minChip), Metrics.maxChip).rounded()
        let total = width * CGFloat(chips.count) + spacing * CGFloat(chips.count - 1)

        row.frame = NSRect(x: 0, y: 0, width: max(total, available), height: bounds.height)
        for (index, chip) in chips.enumerated() {
            chip.frame = NSRect(x: (width + spacing) * CGFloat(index),
                                y: (bounds.height - 20) / 2, width: width, height: 20)
        }
        // Scrolled here rather than when the selection changes: the chip has no frame
        // worth scrolling to until this has run.
        if revealPending || bounds.width != laidOutWidth {
            revealPending = false
            laidOutWidth = bounds.width
            if let active = chips.first(where: { $0.isActive }) {
                active.scrollToVisible(active.bounds)
            }
        }
    }

    /// Called when the selection moves, so a tab picked by keyboard scrolls into view.
    func revealActive() {
        revealPending = true
        needsLayout = true
    }

    @objc private func newTab() { onNew?() }

    // MARK: Theme

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        layer?.backgroundColor = NSColor.clear.cgColor
        plus.setSymbol("plus", tooltip: "New tab" + LappAction.newTab.shortcutSuffix)
        plus.applyTheme(theme)
        chips.forEach { $0.applyTheme(theme) }
    }
}

// MARK: - Chip

/// One tab. The ✕ only appears on hover, and the label always reserves its width, so the
/// title never jumps sideways when the pointer arrives.
private final class TabChip: NSView, Themed {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    var title: String = "" {
        didSet {
            label.stringValue = title.isEmpty ? "New note" : title
            toolTip = label.stringValue
        }
    }
    var isActive = false

    private let label = NSTextField(labelWithString: "")
    private let close = NSButton()
    private var hovering = false
    private var theme: Theme = .current

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5

        label.font = NSFont.systemFont(ofSize: 10.5)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        close.isBordered = false
        close.imagePosition = .imageOnly
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold))
        close.target = self
        close.action = #selector(closeTab)
        close.isHidden = true
        close.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(close)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -1),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 14),
            close.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        let background = isActive ? theme.buttonHover : (hovering ? theme.buttonHover : .clear)
        layer?.backgroundColor = background.cgColor
        label.textColor = isActive ? theme.text : theme.muted
        label.font = NSFont.systemFont(ofSize: 10.5, weight: isActive ? .medium : .regular)
        close.contentTintColor = theme.button
        close.toolTip = "Close tab" + LappAction.closeTab.shortcutSuffix
        close.isHidden = !hovering
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

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) { onSelect?() }

    /// Middle-click closes, the way it does everywhere else with tabs.
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() }
    }

    @objc private func closeTab() { onClose?() }
}
