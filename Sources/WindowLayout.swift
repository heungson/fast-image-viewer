import AppKit

extension AppDelegate {
    func makeWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Fast Image Viewer"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Palette.background
        window.minSize = NSSize(width: 880, height: 640)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("ViewerWindow")
        window.center()
        let root = NSView(); root.wantsLayer = true
        root.layer?.backgroundColor = Palette.background.cgColor
        window.contentView = root

        let badge = BrandBadge()
        stateLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        metadata.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        configure(revealButton, action: #selector(revealFile))
        revealButton.title = ""; revealButton.image = symbol("arrow.up.forward.square", size: 12)
        revealButton.toolTip = "Reveal original in Finder"; revealButton.setAccessibilityLabel("Reveal in Finder"); revealButton.isHidden = true
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        configure(exportButton, action: #selector(exportEditedImage), prominent: true)
        exportButton.image = symbol("square.and.arrow.up", size: 14); exportButton.imagePosition = .imageLeading
        exportButton.setAccessibilityLabel("Export edited copy")
        let copy = ChromeButton(title: "Copy", target: self, action: #selector(copyEditedImage))
        configure(copy, action: #selector(copyEditedImage)); copy.style = .subtle
        copy.image = symbol("doc.on.doc", size: 14); copy.imagePosition = .imageLeading
        copy.toolTip = "Copy image with marks (⇧⌘C)"; copy.setAccessibilityLabel("Copy image with marks")

        let inputShell = surfaceView(radius: 9, color: Palette.background)
        addressShell = inputShell
        address.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        address.textColor = Palette.text; address.backgroundColor = Palette.background
        address.isBezeled = false; address.focusRingType = .none
        address.placeholderAttributedString = NSAttributedString(string: "Paste an image path or URL…", attributes: [.foregroundColor: Palette.muted])
        address.cell?.usesSingleLineMode = true; address.cell?.isScrollable = true
        address.target = self; address.action = #selector(openFromField); address.delegate = self
        address.escape = { [weak self] in self?.cancelOrHide() }
        address.setAccessibilityLabel("Image file path or URL")
        let linkIcon = NSImageView(); linkIcon.image = symbol("link", size: 14); linkIcon.contentTintColor = Palette.muted
        configure(openButton, action: #selector(openFromField))
        openButton.title = "Open"; openButton.image = symbol("return", size: 12); openButton.imagePosition = .imageTrailing
        openButton.toolTip = "Open address (Return)"
        let addressKey = label("⌘L", size: 10, weight: .medium, color: Palette.muted)
        let browse = ChromeButton(image: symbol("folder")!, target: self, action: #selector(browseFiles))
        configure(browse, action: #selector(browseFiles)); browse.style = .subtle
        browse.toolTip = "Browse files (⌘O)"; browse.setAccessibilityLabel("Browse files")
        [linkIcon, address, addressKey, openButton].forEach { inputShell.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }

        let rail = makeEditingToolbar()
        editControls.append(copy)
        let options = makeToolOptions()
        let minus = iconButton("minus", action: #selector(zoomOut), tooltip: "Zoom out (⌘−)")
        let plus = iconButton("plus", action: #selector(zoomIn), tooltip: "Zoom in (⌘+)")
        let fit = ChromeButton(title: "Fit", target: self, action: #selector(fitImage))
        configure(fit, action: #selector(fitImage)); fit.toolTip = "Fit image (⌘0)"; fit.style = .tool
        let actual = ChromeButton(title: "1:1", target: self, action: #selector(actualSize))
        configure(actual, action: #selector(actualSize)); actual.toolTip = "Actual pixels (⌘1)"; actual.style = .tool
        zoomControls = [minus, plus, fit, actual]; zoomControls.forEach { $0.isEnabled = false }
        zoomLabel.alignment = .center; zoomLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        let zoomTools = NSStackView(views: [minus, zoomLabel, plus, fit, actual])
        zoomTools.orientation = .horizontal; zoomTools.alignment = .centerY; zoomTools.spacing = 3
        editHint.font = .systemFont(ofSize: 10)
        editHint.lineBreakMode = .byTruncatingTail
        shortcutLabel.font = .systemFont(ofSize: 10, weight: .medium)
        let views: [NSView] = [badge, stateLabel, metadata, revealButton, spinner, copy, exportButton, inputShell, browse,
                               rail, options, canvas, zoomTools, editHint, shortcutLabel]
        views.forEach { root.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), badge.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            badge.widthAnchor.constraint(equalToConstant: 34), badge.heightAnchor.constraint(equalToConstant: 34),
            stateLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12), stateLabel.topAnchor.constraint(equalTo: badge.topAnchor),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: copy.leadingAnchor, constant: -56),
            metadata.leadingAnchor.constraint(equalTo: stateLabel.leadingAnchor), metadata.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 4),
            metadata.trailingAnchor.constraint(lessThanOrEqualTo: copy.leadingAnchor, constant: -24),
            revealButton.leadingAnchor.constraint(equalTo: stateLabel.trailingAnchor, constant: 6), revealButton.centerYAnchor.constraint(equalTo: stateLabel.centerYAnchor),
            revealButton.widthAnchor.constraint(equalToConstant: 22), revealButton.heightAnchor.constraint(equalToConstant: 22),
            spinner.leadingAnchor.constraint(equalTo: revealButton.trailingAnchor, constant: 4), spinner.centerYAnchor.constraint(equalTo: stateLabel.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 12), spinner.heightAnchor.constraint(equalToConstant: 12),
            exportButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20), exportButton.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            exportButton.widthAnchor.constraint(equalToConstant: 104), exportButton.heightAnchor.constraint(equalToConstant: 34),
            copy.trailingAnchor.constraint(equalTo: exportButton.leadingAnchor, constant: -8), copy.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            copy.widthAnchor.constraint(equalToConstant: 84), copy.heightAnchor.constraint(equalToConstant: 34),
            inputShell.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), inputShell.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 16),
            inputShell.trailingAnchor.constraint(equalTo: browse.leadingAnchor, constant: -8), inputShell.heightAnchor.constraint(equalToConstant: 38),
            browse.trailingAnchor.constraint(equalTo: exportButton.trailingAnchor), browse.centerYAnchor.constraint(equalTo: inputShell.centerYAnchor),
            browse.widthAnchor.constraint(equalToConstant: 38), browse.heightAnchor.constraint(equalToConstant: 38),
            linkIcon.leadingAnchor.constraint(equalTo: inputShell.leadingAnchor, constant: 12), linkIcon.centerYAnchor.constraint(equalTo: inputShell.centerYAnchor),
            linkIcon.widthAnchor.constraint(equalToConstant: 17),
            address.leadingAnchor.constraint(equalTo: linkIcon.trailingAnchor, constant: 8), address.centerYAnchor.constraint(equalTo: inputShell.centerYAnchor),
            address.heightAnchor.constraint(equalToConstant: 20), address.trailingAnchor.constraint(equalTo: addressKey.leadingAnchor, constant: -8),
            addressKey.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -10), addressKey.centerYAnchor.constraint(equalTo: inputShell.centerYAnchor),
            addressKey.widthAnchor.constraint(equalToConstant: 22),
            openButton.trailingAnchor.constraint(equalTo: inputShell.trailingAnchor, constant: -4), openButton.centerYAnchor.constraint(equalTo: inputShell.centerYAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 72), openButton.heightAnchor.constraint(equalToConstant: 30),
            rail.leadingAnchor.constraint(equalTo: inputShell.leadingAnchor), rail.topAnchor.constraint(equalTo: inputShell.bottomAnchor, constant: 16),
            rail.widthAnchor.constraint(equalToConstant: 56), rail.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            options.leadingAnchor.constraint(equalTo: canvas.leadingAnchor), options.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            options.topAnchor.constraint(equalTo: rail.topAnchor), options.heightAnchor.constraint(equalToConstant: 30),
            canvas.leadingAnchor.constraint(equalTo: rail.trailingAnchor, constant: 14), canvas.trailingAnchor.constraint(equalTo: browse.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: options.bottomAnchor, constant: 10), canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -64),
            zoomTools.trailingAnchor.constraint(equalTo: canvas.trailingAnchor), zoomTools.topAnchor.constraint(equalTo: canvas.bottomAnchor, constant: 10),
            zoomLabel.widthAnchor.constraint(equalToConstant: 40), fit.widthAnchor.constraint(equalToConstant: 38), actual.widthAnchor.constraint(equalToConstant: 38),
            fit.heightAnchor.constraint(equalToConstant: 28), actual.heightAnchor.constraint(equalToConstant: 28),
            editHint.leadingAnchor.constraint(equalTo: canvas.leadingAnchor), editHint.centerYAnchor.constraint(equalTo: zoomTools.centerYAnchor),
            editHint.trailingAnchor.constraint(lessThanOrEqualTo: zoomTools.leadingAnchor, constant: -20),
            shortcutLabel.leadingAnchor.constraint(equalTo: canvas.leadingAnchor), shortcutLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8)
        ])
        let emptyBrowse = ChromeButton(title: "Browse files…", target: self, action: #selector(browseFiles))
        configure(emptyBrowse, action: #selector(browseFiles), prominent: true)
        let emptyClipboard = ChromeButton(title: "Open clipboard", target: self, action: #selector(openClipboard))
        configure(emptyClipboard, action: #selector(openClipboard)); emptyClipboard.style = .subtle
        let emptyActions = NSStackView(views: [emptyBrowse, emptyClipboard]); emptyActions.spacing = 10
        [emptyBrowse, emptyClipboard].forEach {
            $0.widthAnchor.constraint(equalToConstant: 132).isActive = true
            $0.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }
        canvas.emptyState.addArrangedSubview(emptyActions)
        canvas.onDrop = { [weak self] in self?.openAddress($0) }
        canvas.onZoomChanged = { [weak self] scale in
            guard let self = self else { return }
            self.zoomLabel.stringValue = "\(Int((scale * 100).rounded()))%"
            fit.state = self.canvas.fits ? .on : .off
            actual.state = !self.canvas.fits && abs(scale - 1) < 0.001 ? .on : .off
        }
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
