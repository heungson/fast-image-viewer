import AppKit

extension AppDelegate {
    func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Fast Image Viewer"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Palette.background
        window.minSize = NSSize(width: 880, height: 620)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("ViewerWindow")
        window.center()
        let root = NSView(); root.wantsLayer = true
        root.layer?.backgroundColor = Palette.background.cgColor
        window.contentView = root

        let badge = BrandBadge()
        let title = label("Fast Image Viewer", size: 15, weight: .semibold)
        let subtitle = label("View. Mark. Share.", size: 10, color: Palette.muted)
        let shortcutBadge = surfaceView(radius: 8, color: Palette.background)
        shortcutBadge.addSubview(shortcutLabel); shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        configure(exportButton, action: #selector(exportEditedImage), prominent: true)
        exportButton.image = symbol("square.and.arrow.up", size: 14)
        exportButton.imagePosition = .imageTrailing
        exportButton.setAccessibilityLabel("Export edited copy")

        let inputShell = surfaceView(radius: 10)
        addressShell = inputShell
        address.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        address.textColor = Palette.text; address.backgroundColor = Palette.surface
        address.isBezeled = false; address.focusRingType = .none
        address.placeholderAttributedString = NSAttributedString(string: "Paste an image path or URL…", attributes: [.foregroundColor: Palette.muted])
        address.cell?.usesSingleLineMode = true; address.cell?.isScrollable = true
        address.target = self; address.action = #selector(openFromField); address.delegate = self
        address.escape = { [weak self] in self?.cancelOrHide() }
        address.setAccessibilityLabel("Image file path or URL")
        let linkIcon = NSImageView(); linkIcon.image = symbol("link", size: 15); linkIcon.contentTintColor = Palette.muted
        configure(openButton, action: #selector(openFromField))
        openButton.style = .subtle
        openButton.title = "Open"; openButton.image = symbol("return", size: 12); openButton.imagePosition = .imageTrailing
        openButton.toolTip = "Open address (Return)"
        let addressKey = label("⌘L", size: 10, weight: .medium, color: Palette.muted)
        [linkIcon, address, addressKey, openButton].forEach { inputShell.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        let browse = ChromeButton(image: symbol("folder")!, target: self, action: #selector(browseFiles))
        configure(browse, action: #selector(browseFiles)); browse.style = .subtle
        browse.toolTip = "Browse files (⌘O)"; browse.setAccessibilityLabel("Browse files")

        let editingTools = makeEditingToolbar()
        let minus = iconButton("minus", action: #selector(zoomOut), tooltip: "Zoom out (⌘−)")
        let plus = iconButton("plus", action: #selector(zoomIn), tooltip: "Zoom in (⌘+)")
        let fit = ChromeButton(title: "Fit", target: self, action: #selector(fitImage))
        configure(fit, action: #selector(fitImage)); fit.toolTip = "Fit image (⌘0)"
        let actual = ChromeButton(title: "1:1", target: self, action: #selector(actualSize))
        configure(actual, action: #selector(actualSize)); actual.toolTip = "Actual pixels (⌘1)"
        zoomControls = [minus, plus, fit, actual]; zoomControls.forEach { $0.isEnabled = false }
        zoomLabel.alignment = .center
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let zoomTools = NSStackView(views: [minus, zoomLabel, plus, fit, actual])
        zoomTools.orientation = .horizontal; zoomTools.alignment = .centerY; zoomTools.spacing = 4
        let contextActions = NSStackView(views: [textSizePicker, applyCropButton, cancelCropButton])
        contextActions.orientation = .horizontal; contextActions.alignment = .centerY; contextActions.spacing = 8
        configure(revealButton, action: #selector(revealFile))
        revealButton.title = ""; revealButton.image = symbol("arrow.up.forward.square", size: 12)
        revealButton.toolTip = "Reveal original in Finder"; revealButton.setAccessibilityLabel("Reveal in Finder"); revealButton.isHidden = true
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        stateLabel.font = .systemFont(ofSize: 11, weight: .medium)
        metadata.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        metadata.alignment = .center

        let views: [NSView] = [badge, title, subtitle, shortcutBadge, exportButton, inputShell, browse, editingTools,
                               canvas, spinner, stateLabel, metadata, revealButton, zoomTools, editHint, contextActions]
        views.forEach { root.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22), badge.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            badge.widthAnchor.constraint(equalToConstant: 36), badge.heightAnchor.constraint(equalToConstant: 36),
            title.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10), title.topAnchor.constraint(equalTo: badge.topAnchor, constant: 2),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor), subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            exportButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22), exportButton.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            exportButton.widthAnchor.constraint(equalToConstant: 96), exportButton.heightAnchor.constraint(equalToConstant: 32),
            shortcutBadge.trailingAnchor.constraint(equalTo: exportButton.leadingAnchor, constant: -12), shortcutBadge.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            shortcutBadge.heightAnchor.constraint(equalToConstant: 28),
            shortcutLabel.leadingAnchor.constraint(equalTo: shortcutBadge.leadingAnchor, constant: 10), shortcutLabel.trailingAnchor.constraint(equalTo: shortcutBadge.trailingAnchor, constant: -10),
            shortcutLabel.centerYAnchor.constraint(equalTo: shortcutBadge.centerYAnchor),
            inputShell.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22), inputShell.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 16),
            inputShell.trailingAnchor.constraint(equalTo: browse.leadingAnchor, constant: -8), inputShell.heightAnchor.constraint(equalToConstant: 44),
            browse.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22), browse.centerYAnchor.constraint(equalTo: inputShell.centerYAnchor),
            browse.widthAnchor.constraint(equalToConstant: 44), browse.heightAnchor.constraint(equalToConstant: 44),
            linkIcon.leadingAnchor.constraint(equalTo: inputShell.leadingAnchor, constant: 14), linkIcon.centerYAnchor.constraint(equalTo: inputShell.centerYAnchor),
            linkIcon.widthAnchor.constraint(equalToConstant: 17),
            address.leadingAnchor.constraint(equalTo: linkIcon.trailingAnchor, constant: 10), address.centerYAnchor.constraint(equalTo: inputShell.centerYAnchor),
            address.heightAnchor.constraint(equalToConstant: 22), address.trailingAnchor.constraint(equalTo: addressKey.leadingAnchor, constant: -10),
            addressKey.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -12), addressKey.centerYAnchor.constraint(equalTo: inputShell.centerYAnchor),
            addressKey.widthAnchor.constraint(equalToConstant: 22),
            openButton.trailingAnchor.constraint(equalTo: inputShell.trailingAnchor, constant: -6), openButton.centerYAnchor.constraint(equalTo: inputShell.centerYAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 76), openButton.heightAnchor.constraint(equalToConstant: 32),
            editingTools.leadingAnchor.constraint(equalTo: inputShell.leadingAnchor), editingTools.trailingAnchor.constraint(equalTo: browse.trailingAnchor),
            editingTools.topAnchor.constraint(equalTo: inputShell.bottomAnchor, constant: 12), editingTools.heightAnchor.constraint(equalToConstant: 56),
            canvas.leadingAnchor.constraint(equalTo: inputShell.leadingAnchor), canvas.trailingAnchor.constraint(equalTo: browse.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: editingTools.bottomAnchor, constant: 14), canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -70),
            spinner.leadingAnchor.constraint(equalTo: inputShell.leadingAnchor), spinner.centerYAnchor.constraint(equalTo: stateLabel.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 12), spinner.heightAnchor.constraint(equalToConstant: 12),
            stateLabel.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 6), stateLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -42),
            stateLabel.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, multiplier: 0.29),
            revealButton.leadingAnchor.constraint(equalTo: stateLabel.trailingAnchor, constant: 6), revealButton.centerYAnchor.constraint(equalTo: stateLabel.centerYAnchor),
            revealButton.widthAnchor.constraint(equalToConstant: 24), revealButton.heightAnchor.constraint(equalToConstant: 24),
            metadata.centerXAnchor.constraint(equalTo: root.centerXAnchor), metadata.centerYAnchor.constraint(equalTo: stateLabel.centerYAnchor),
            metadata.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, multiplier: 0.26),
            zoomTools.trailingAnchor.constraint(equalTo: browse.trailingAnchor), zoomTools.centerYAnchor.constraint(equalTo: stateLabel.centerYAnchor),
            zoomLabel.widthAnchor.constraint(equalToConstant: 40), fit.widthAnchor.constraint(equalToConstant: 36), actual.widthAnchor.constraint(equalToConstant: 46),
            editHint.leadingAnchor.constraint(equalTo: inputShell.leadingAnchor), editHint.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            editHint.heightAnchor.constraint(equalToConstant: 20), editHint.trailingAnchor.constraint(lessThanOrEqualTo: contextActions.leadingAnchor, constant: -10),
            contextActions.trailingAnchor.constraint(equalTo: browse.trailingAnchor), contextActions.centerYAnchor.constraint(equalTo: editHint.centerYAnchor),
            applyCropButton.widthAnchor.constraint(equalToConstant: 94), applyCropButton.heightAnchor.constraint(equalToConstant: 24),
            cancelCropButton.widthAnchor.constraint(equalToConstant: 52), cancelCropButton.heightAnchor.constraint(equalToConstant: 24),
            textSizePicker.widthAnchor.constraint(equalToConstant: 115)
        ])
        canvas.onDrop = { [weak self] in self?.openAddress($0) }
        canvas.onZoomChanged = { [weak self] in self?.zoomLabel.stringValue = "\(Int(($0 * 100).rounded()))%" }
        canvas.onEdit = { [weak self] in self?.updateEditorUI() }
        canvas.document.markup.onInteractionChanged = { [weak self] in self?.updateEditorUI() }
        canvas.document.markup.onTextRequested = { [weak self] point, color, size in self?.addText(at: point, color: color, size: size) }
        canvas.document.markup.onCropRequested = { [weak self] in self?.applyCrop(nil) }
        updateEditorUI(); window.initialFirstResponder = address
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === address else { return }
        addressShell?.layer?.borderColor = Palette.accent.withAlphaComponent(0.65).cgColor
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === address else { return }
        addressShell?.layer?.borderColor = Palette.border.cgColor
    }
}
