import AppKit

/// Three sections, no scrolling, no tabs. The moment it needs either, something has been
/// added that shouldn't have been.
final class SettingsView: NSView, Themed {
    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Settings")
    private let closeButton: IconButton
    private let hairline = NSView()
    private let stack = NSStackView()

    private var recorders: [LappAction: HotkeyRecorderView] = [:]
    private var resetButtons: [NSButton] = []
    private var sectionLabels: [NSTextField] = []
    private var bodyLabels: [NSTextField] = []
    private let globalStatus = NSTextField(labelWithString: "")
    private let appearanceControl = NSSegmentedControl()
    private let fontSlider = NSSlider()
    private let fontValue = NSTextField(labelWithString: "")
    private let opacitySlider = NSSlider()
    private let opacityValue = NSTextField(labelWithString: "")
    private let widthSlider = NSSlider()
    private let widthValue = NSTextField(labelWithString: "")
    private let heightSlider = NSSlider()
    private let heightValue = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let vaultPopup = NSPopUpButton()
    private let folderPopup = NSPopUpButton()
    private var vaults: [ObsidianVault] = []
    private var folders: [String] = []
    private var theme: Theme = .current

    override init(frame frameRect: NSRect) {
        closeButton = IconButton(symbol: "chevron.right", tooltip: "Close", action: #selector(close), target: nil)
        super.init(frame: frameRect)
        closeButton.target = self
        wantsLayer = true
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(globalStatusChanged),
                                               name: .lappGlobalHotkeyStatus, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Build

    private func build() {
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        hairline.wantsLayer = true
        hairline.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scrollView.documentView = document
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(closeButton)
        addSubview(hairline)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: hairline.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16)
        ])

        buildHotkeys()
        buildAppearance()
        buildVault()
        refresh()
    }

    private func sectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        sectionLabels.append(label)
        return label
    }

    private func row(_ left: NSView, _ right: NSView) -> NSStackView {
        let row = NSStackView(views: [left, NSView(), right])
        row.orientation = .horizontal
        row.spacing = 6
        row.distribution = .fill
        row.setHuggingPriority(.defaultLow, for: .horizontal)
        left.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    private func buildHotkeys() {
        stack.addArrangedSubview(sectionHeader("Hotkeys"))

        for action in LappAction.allCases {
            let label = NSTextField(labelWithString: action.title)
            label.font = NSFont.systemFont(ofSize: 11)
            bodyLabels.append(label)

            let recorder = HotkeyRecorderView(action: action)
            recorder.onChange = { [weak self] binding in
                self?.apply(binding, to: action)
            }
            recorders[action] = recorder

            let reset = NSButton()
            reset.isBordered = false
            reset.image = NSImage(systemSymbolName: "arrow.uturn.backward",
                                  accessibilityDescription: "Reset")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9.5, weight: .regular))
            reset.imagePosition = .imageOnly
            reset.target = self
            reset.action = #selector(resetBinding(_:))
            reset.tag = LappAction.allCases.firstIndex(of: action) ?? 0
            reset.toolTip = "Reset to default"
            reset.translatesAutoresizingMaskIntoConstraints = false
            reset.widthAnchor.constraint(equalToConstant: 18).isActive = true
            resetButtons.append(reset)

            let controls = NSStackView(views: [recorder, reset])
            controls.orientation = .horizontal
            controls.spacing = 2
            let line = row(label, controls)
            stack.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

            if action.isGlobal {
                globalStatus.font = NSFont.systemFont(ofSize: 10)
                globalStatus.lineBreakMode = .byWordWrapping
                globalStatus.maximumNumberOfLines = 2
                stack.addArrangedSubview(globalStatus)
                globalStatus.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }

        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)
    }

    private func buildAppearance() {
        stack.addArrangedSubview(sectionHeader("Appearance"))

        appearanceControl.segmentCount = AppearanceMode.allCases.count
        for (index, mode) in AppearanceMode.allCases.enumerated() {
            appearanceControl.setLabel(mode.title, forSegment: index)
            appearanceControl.setWidth(0, forSegment: index)
        }
        appearanceControl.segmentDistribution = .fillEqually
        appearanceControl.trackingMode = .selectOne
        appearanceControl.target = self
        appearanceControl.action = #selector(appearanceChanged)
        appearanceControl.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(appearanceControl)
        appearanceControl.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        fontSlider.minValue = 11
        fontSlider.maxValue = 20
        fontSlider.isContinuous = false      // save on mouse-up, not 60 times a second
        fontSlider.target = self
        fontSlider.action = #selector(fontSizeChanged)
        fontValue.font = NSFont.systemFont(ofSize: 11)
        fontValue.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: "Text size")
        label.font = NSFont.systemFont(ofSize: 11)
        bodyLabels.append(label)
        bodyLabels.append(fontValue)

        let controls = NSStackView(views: [fontSlider, fontValue])
        controls.orientation = .horizontal
        controls.spacing = 8
        fontSlider.widthAnchor.constraint(equalToConstant: 108).isActive = true

        let line = row(label, controls)
        stack.addArrangedSubview(line)
        line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        addSlider(opacitySlider, value: opacityValue, title: "Opacity",
                  min: 40, max: 100, action: #selector(opacityChanged))
        addSlider(widthSlider, value: widthValue, title: "Width",
                  min: 220, max: 700, action: #selector(widthChanged))
        let heightLine = addSlider(heightSlider, value: heightValue, title: "Height",
                                   min: 25, max: 100, action: #selector(heightChanged))
        stack.setCustomSpacing(16, after: heightLine)
    }

    @discardableResult
    private func addSlider(_ slider: NSSlider, value: NSTextField, title: String,
                           min: Double, max: Double, action: Selector) -> NSView {
        slider.minValue = min
        slider.maxValue = max
        slider.isContinuous = false      // save on mouse-up, not 60 times a second
        slider.target = self
        slider.action = action
        slider.widthAnchor.constraint(equalToConstant: 108).isActive = true
        value.font = NSFont.systemFont(ofSize: 11)
        value.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11)
        bodyLabels.append(label)
        bodyLabels.append(value)

        let controls = NSStackView(views: [slider, value])
        controls.orientation = .horizontal
        controls.spacing = 8

        let line = row(label, controls)
        stack.addArrangedSubview(line)
        line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return line
    }

    private func buildVault() {
        stack.addArrangedSubview(sectionHeader("Vault"))

        let hint = NSTextField(labelWithString: "Where “Send to Obsidian” writes.")
        hint.font = NSFont.systemFont(ofSize: 10)
        sectionLabels.append(hint)
        stack.addArrangedSubview(hint)

        vaultPopup.target = self
        vaultPopup.action = #selector(vaultChanged)
        folderPopup.target = self
        folderPopup.action = #selector(folderChanged)

        for popup in [vaultPopup, folderPopup] {
            popup.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(popup)
            popup.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    // MARK: Refresh

    func refresh() {
        recorders.values.forEach { $0.refresh() }
        updateResetButtons()
        globalStatusChanged()

        let data = Settings.shared.data
        appearanceControl.selectedSegment = AppearanceMode.allCases.firstIndex(of: data.appearance) ?? 2
        fontSlider.doubleValue = Double(data.fontSize)
        fontValue.stringValue = "\(Int(data.fontSize))"
        opacitySlider.doubleValue = Double(data.opacity * 100)
        opacityValue.stringValue = "\(Int(data.opacity * 100))%"
        widthSlider.doubleValue = Double(data.width)
        widthValue.stringValue = "\(Int(data.width))"
        heightSlider.doubleValue = Double(data.heightFraction * 100)
        heightValue.stringValue = "\(Int(data.heightFraction * 100))%"

        vaults = ObsidianVaults.all()
        vaultPopup.removeAllItems()
        if vaults.isEmpty {
            vaultPopup.addItem(withTitle: "No Obsidian vaults found")
            vaultPopup.isEnabled = false
            folderPopup.isEnabled = false
            folderPopup.removeAllItems()
            return
        }
        vaultPopup.isEnabled = true
        folderPopup.isEnabled = true
        vaults.forEach { vaultPopup.addItem(withTitle: $0.name) }
        let selected = vaults.firstIndex { $0.path == data.vaultPath } ?? 0
        vaultPopup.selectItem(at: selected)
        reloadFolders(vaultIndex: selected, select: data.vaultFolder)
    }

    private func reloadFolders(vaultIndex: Int, select folder: String) {
        folders = ObsidianVaults.folders(in: vaults[vaultIndex].path)
        folderPopup.removeAllItems()
        for path in folders {
            folderPopup.addItem(withTitle: path.isEmpty ? "Vault root" : path)
        }
        folderPopup.selectItem(at: folders.firstIndex(of: folder) ?? 0)
    }

    private func updateResetButtons() {
        for (index, action) in LappAction.allCases.enumerated() {
            let isDefault = Settings.shared.data.bindings[action.rawValue] == nil
            resetButtons[index].isHidden = isDefault
        }
    }

    @objc private func globalStatusChanged() {
        if let error = Hotkeys.shared.globalError {
            globalStatus.stringValue = "Focus pad is \(error). Pick another combination."
            globalStatus.textColor = theme.accent
            globalStatus.isHidden = false
        } else if let claimant = Hotkeys.shared.systemClaimant {
            globalStatus.stringValue = "macOS uses this for \(claimant), so it won't reach Lapp."
            globalStatus.textColor = theme.accent
            globalStatus.isHidden = false
        } else if Settings.shared.binding(for: .focusPad) == nil {
            globalStatus.stringValue = "No global hotkey — the pad can only be focused by clicking it."
            globalStatus.textColor = theme.muted
            globalStatus.isHidden = false
        } else {
            globalStatus.isHidden = true
        }
    }

    // MARK: Changes

    private func apply(_ binding: KeyBinding?, to action: LappAction) {
        if let binding, let clash = Settings.shared.conflict(for: binding, excluding: action) {
            NSSound.beep()
            globalStatus.stringValue = "\(binding.display) is already \(clash.title)."
            globalStatus.textColor = theme.accent
            globalStatus.isHidden = false
            return
        }
        Settings.shared.setBinding(binding, for: action)
        recorders[action]?.refresh()
        updateResetButtons()
    }

    @objc private func resetBinding(_ sender: NSButton) {
        let action = LappAction.allCases[sender.tag]
        Settings.shared.resetBinding(for: action)
        recorders[action]?.refresh()
        updateResetButtons()
    }

    @objc private func appearanceChanged() {
        let mode = AppearanceMode.allCases[appearanceControl.selectedSegment]
        Settings.shared.update { $0.appearance = mode }
    }

    @objc private func fontSizeChanged() {
        let size = CGFloat(fontSlider.doubleValue.rounded())
        fontValue.stringValue = "\(Int(size))"
        Settings.shared.update { $0.fontSize = size }
    }

    @objc private func opacityChanged() {
        let percent = opacitySlider.doubleValue.rounded()
        opacityValue.stringValue = "\(Int(percent))%"
        Settings.shared.update { $0.opacity = CGFloat(percent / 100) }
    }

    @objc private func widthChanged() {
        let width = CGFloat(widthSlider.doubleValue.rounded())
        widthValue.stringValue = "\(Int(width))"
        Settings.shared.update { $0.width = width }
    }

    @objc private func heightChanged() {
        let percent = heightSlider.doubleValue.rounded()
        heightValue.stringValue = "\(Int(percent))%"
        Settings.shared.update { $0.heightFraction = CGFloat(percent / 100) }
    }

    @objc private func vaultChanged() {
        let index = vaultPopup.indexOfSelectedItem
        guard vaults.indices.contains(index) else { return }
        Settings.shared.update {
            $0.vaultPath = self.vaults[index].path
            $0.vaultFolder = ""
        }
        reloadFolders(vaultIndex: index, select: "")
    }

    @objc private func folderChanged() {
        let index = folderPopup.indexOfSelectedItem
        guard folders.indices.contains(index) else { return }
        Settings.shared.update { $0.vaultFolder = self.folders[index] }
    }

    @objc private func close() { onClose?() }

    // MARK: Theme

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        layer?.backgroundColor = theme.surface.cgColor
        hairline.layer?.backgroundColor = theme.hairline.cgColor
        titleLabel.textColor = theme.text
        closeButton.applyTheme(theme)
        sectionLabels.forEach { $0.textColor = theme.muted }
        bodyLabels.forEach { $0.textColor = theme.text }
        resetButtons.forEach { $0.contentTintColor = theme.muted }
        recorders.values.forEach { $0.applyTheme(theme) }
        globalStatusChanged()
    }
}
