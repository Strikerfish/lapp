import AppKit

/// The list of filed notes. Reads the directory once when opened, not continuously.
final class HistoryView: NSView, Themed {
    var onOpen: ((NoteSummary) -> Void)?
    var onDelete: ((NoteSummary) -> Void)?
    var onSend: ((NoteSummary) -> Void)?
    var onClose: (() -> Void)?

    private let search = NSSearchField()
    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private let empty = NSTextField(labelWithString: "No notes filed yet.")
    private let closeButton: IconButton
    private let hairline = NSView()

    private var notes: [NoteSummary] = []
    private var theme: Theme = .current

    override init(frame frameRect: NSRect) {
        closeButton = IconButton(symbol: "chevron.right", tooltip: "Close", action: #selector(close), target: nil)
        super.init(frame: frameRect)
        closeButton.target = self
        wantsLayer = true
        build()
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        search.placeholderString = "Filter"
        search.focusRingType = .none
        search.target = self
        search.action = #selector(filterChanged)
        search.sendsWholeSearchString = false
        search.sendsSearchStringImmediately = true
        search.translatesAutoresizingMaskIntoConstraints = false

        hairline.wantsLayer = true
        hairline.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 8, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let clip = FlippedView()
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            stack.topAnchor.constraint(equalTo: clip.topAnchor),
            stack.bottomAnchor.constraint(equalTo: clip.bottomAnchor)
        ])

        scrollView.documentView = clip
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        empty.font = NSFont.systemFont(ofSize: 11.5)
        empty.translatesAutoresizingMaskIntoConstraints = false

        addSubview(search)
        addSubview(closeButton)
        addSubview(hairline)
        addSubview(scrollView)
        addSubview(empty)

        NSLayoutConstraint.activate([
            search.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            search.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            search.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: search.centerYAnchor),

            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: hairline.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            empty.centerXAnchor.constraint(equalTo: centerXAnchor),
            empty.topAnchor.constraint(equalTo: hairline.bottomAnchor, constant: 24)
        ])
    }

    func reload() {
        notes = Store.shared.notes()
        rebuild()
    }

    @objc private func filterChanged() { rebuild() }
    @objc private func close() { onClose?() }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let query = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = query.isEmpty ? notes : notes.filter {
            $0.title.lowercased().contains(query) || $0.preview.lowercased().contains(query)
        }
        empty.isHidden = !visible.isEmpty
        empty.stringValue = notes.isEmpty ? "No notes filed yet." : "Nothing matches."

        for note in visible {
            let row = NoteRow(note: note)
            row.onOpen = { [weak self] in self?.onOpen?(note) }
            row.onDelete = { [weak self] in
                self?.onDelete?(note)
                self?.reload()
            }
            row.onSend = { [weak self] in
                self?.onSend?(note)
                self?.reload()
            }
            row.applyTheme(theme)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        layer?.backgroundColor = theme.surface.cgColor
        hairline.layer?.backgroundColor = theme.hairline.cgColor
        empty.textColor = theme.muted
        closeButton.applyTheme(theme)
        stack.arrangedSubviews.compactMap { $0 as? NoteRow }.forEach { $0.applyTheme(theme) }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Row

private final class NoteRow: NSView, Themed {
    var onOpen: (() -> Void)?
    var onDelete: (() -> Void)?
    var onSend: (() -> Void)?

    private let note: NoteSummary
    private let title = NSTextField(labelWithString: "")
    private let date = NSTextField(labelWithString: "")
    private let preview = NSTextField(labelWithString: "")
    private let sendButton: IconButton
    private let deleteButton: IconButton
    private var hovering = false
    private var theme: Theme = .current

    init(note: NoteSummary) {
        self.note = note
        sendButton = IconButton(symbol: "arrow.up.forward.square", tooltip: "Send to Obsidian",
                                action: #selector(send), target: nil)
        deleteButton = IconButton(symbol: "trash", tooltip: "Delete", action: #selector(remove), target: nil)
        super.init(frame: .zero)
        sendButton.target = self
        deleteButton.target = self
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        title.stringValue = note.title.isEmpty ? "Untitled" : note.title
        title.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        date.stringValue = Self.format(note.filed)
        date.font = NSFont.systemFont(ofSize: 10)
        date.translatesAutoresizingMaskIntoConstraints = false
        date.setContentCompressionResistancePriority(.required, for: .horizontal)

        preview.stringValue = note.preview
        preview.font = NSFont.systemFont(ofSize: 10.5)
        preview.lineBreakMode = .byTruncatingTail
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.isHidden = note.preview.isEmpty

        sendButton.isHidden = true
        deleteButton.isHidden = true

        addSubview(title)
        addSubview(date)
        addSubview(preview)
        addSubview(sendButton)
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            title.trailingAnchor.constraint(lessThanOrEqualTo: date.leadingAnchor, constant: -6),

            date.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            date.centerYAnchor.constraint(equalTo: title.centerYAnchor),

            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            preview.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),

            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -1),
            sendButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            bottomAnchor.constraint(equalTo: preview.isHidden ? title.bottomAnchor : preview.bottomAnchor,
                                    constant: 7)
        ])
    }

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        title.textColor = theme.text
        date.textColor = theme.muted
        preview.textColor = theme.muted
        sendButton.applyTheme(theme)
        deleteButton.applyTheme(theme)
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
        sendButton.isHidden = false
        deleteButton.isHidden = false
        date.isHidden = true
        applyTheme(theme)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        sendButton.isHidden = true
        deleteButton.isHidden = true
        date.isHidden = false
        applyTheme(theme)
    }

    override func mouseDown(with event: NSEvent) { onOpen?() }

    @objc private func send() { onSend?() }
    @objc private func remove() { onDelete?() }

    private static func format(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "d MMM"
        } else {
            formatter.dateFormat = "d MMM yy"
        }
        return formatter.string(from: date)
    }
}
