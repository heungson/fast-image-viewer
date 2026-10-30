import AppKit
import Carbon

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                  green: CGFloat((hex >> 8) & 255) / 255,
                  blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

enum Palette {
    static let background = NSColor(hex: 0x1C1D22)
    static let surface = NSColor(hex: 0x26272E)
    static let muted = NSColor(hex: 0x9FA2AF)
    static let text = NSColor(hex: 0xF2F0F8)
    static let accent = NSColor(hex: 0xBCA9FF)
    static let border = NSColor(hex: 0x373941)
}

func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular,
           color: NSColor = Palette.text) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingMiddle
    return field
}

func symbol(_ name: String, size: CGFloat = 16) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
}

final class AddressField: NSTextField {
    var escape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { escape?() }
}

final class ImageDocument: NSView {
    let imageView = NSImageView()
    let markup = MarkupView()
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = true
        addSubview(imageView)
        addSubview(markup)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: 0x15161B).setFill()
        dirtyRect.fill()
        let spacing: CGFloat = 24
        NSColor.white.withAlphaComponent(0.035).setFill()
        for row in Int(floor(dirtyRect.minY / spacing))...Int(ceil(dirtyRect.maxY / spacing)) {
            for col in Int(floor(dirtyRect.minX / spacing))...Int(ceil(dirtyRect.maxX / spacing)) {
                NSBezierPath(ovalIn: NSRect(x: CGFloat(col) * spacing, y: CGFloat(row) * spacing, width: 1, height: 1)).fill()
            }
        }
        guard imageView.image != nil else { return }
        let photo = imageView.frame
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowBlurRadius = 20
        shadow.shadowOffset = NSSize(width: 0, height: -4); shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.set(); NSColor(hex: 0x20232B).setFill(); photo.fill()
        NSGraphicsContext.restoreGraphicsState()
        let visible = dirtyRect.intersection(photo)
        guard !visible.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState(); photo.clip()
        let tile: CGFloat = 12
        NSColor(hex: 0x272A32).setFill()
        for row in Int(floor((visible.minY - photo.minY) / tile))...Int(ceil((visible.maxY - photo.minY) / tile)) {
            for col in Int(floor((visible.minX - photo.minX) / tile))...Int(ceil((visible.maxX - photo.minX) / tile)) where (row + col) % 2 == 0 {
                NSRect(x: photo.minX + CGFloat(col) * tile, y: photo.minY + CGFloat(row) * tile, width: tile, height: tile).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class ImageCanvas: NSView {
    let scroll = NSScrollView()
    let document = ImageDocument(frame: .zero)
    let emptyState = NSStackView()
    let emptyTitle = label("Open an image to begin", size: 24, weight: .semibold)
    let emptyDetail = label("Paste a path or URL above, or drop an image here.", size: 13, color: Palette.muted)
    let emptyIcon = NSImageView()
    var onDrop: ((String) -> Void)?
    var onZoomChanged: ((CGFloat) -> Void)?
    var onEdit: (() -> Void)?
    var editor: ImageEditor? { document.markup.editor }
    var pixelSize = NSSize.zero
    var zoom: CGFloat = 1
    var fits = true
    var hasImage: Bool { document.imageView.image != nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderColor = Palette.border.withAlphaComponent(0.7).cgColor
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = document
        addSubview(scroll)

        emptyIcon.image = symbol("photo.on.rectangle.angled", size: 32)
        emptyIcon.contentTintColor = Palette.accent
        emptyIcon.wantsLayer = true
        emptyIcon.layer?.backgroundColor = Palette.accent.withAlphaComponent(0.075).cgColor
        emptyIcon.layer?.cornerRadius = 18
        emptyIcon.setFrameSize(NSSize(width: 64, height: 64))
        emptyState.orientation = .vertical
        emptyState.alignment = .centerX
        emptyState.spacing = 13
        emptyState.addArrangedSubview(emptyIcon)
        emptyState.addArrangedSubview(emptyTitle)
        emptyState.addArrangedSubview(emptyDetail)
        let dropHint = label("⌘O  Browse files     ·     ⇧⌘V  Open clipboard", size: 11, color: Palette.muted.withAlphaComponent(0.7))
        emptyState.addArrangedSubview(dropHint)
        emptyState.setCustomSpacing(24, after: emptyDetail)
        addSubview(emptyState)
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyState.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            emptyIcon.heightAnchor.constraint(equalToConstant: 64),
            emptyIcon.widthAnchor.constraint(equalToConstant: 64),
            emptyDetail.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -80)
        ])
        registerForDraggedTypes([.fileURL, .URL, .string])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        updateImageFrame()
    }

    func show(_ image: NSImage, pixels: NSSize) {
        pixelSize = pixels
        document.imageView.image = image
        document.imageView.image?.size = pixels
        emptyState.isHidden = true
        fits = true
        updateImageFrame()
        centerImage()
    }

    func beginEditing(_ editor: ImageEditor) {
        document.markup.editor = editor
        editor.onChange = { [weak self, weak editor] in
            guard let self = self, let editor = editor, self.editor === editor else { return }
            let size = editor.state.size
            let changedSize = self.pixelSize != size
            self.pixelSize = size
            self.document.imageView.image = NSImage(cgImage: editor.state.base, size: size)
            if changedSize { self.fits = true; self.document.markup.resetInteraction() }
            self.updateImageFrame()
            if changedSize { self.centerImage() }
            self.document.markup.needsDisplay = true
            self.onEdit?()
        }
        onEdit?()
    }

    func placeholder(title: String, detail: String, isError: Bool = false) {
        emptyTitle.stringValue = title
        emptyDetail.stringValue = detail
        emptyDetail.toolTip = detail
        emptyDetail.maximumNumberOfLines = 3
        emptyDetail.preferredMaxLayoutWidth = max(400, bounds.width - 100)
        emptyDetail.lineBreakMode = .byWordWrapping
        emptyIcon.image = symbol(isError ? "exclamationmark.triangle" : "photo.on.rectangle.angled", size: 42)
        emptyIcon.contentTintColor = isError ? .systemOrange : Palette.accent
        emptyState.isHidden = false
        document.markup.editor = nil
        document.markup.tool = .select
        document.markup.isHidden = true
        document.imageView.image = nil
        pixelSize = .zero
        document.frame = scroll.contentView.bounds
    }

    func fit() { fits = true; updateImageFrame(); centerImage() }
    func actual() {
        // A source pixel maps to one physical display pixel on Retina screens.
        setZoom(1 / (window?.backingScaleFactor ?? 1))
    }
    func stepZoom(_ factor: CGFloat) { setZoom(zoom * factor) }

    func setZoom(_ value: CGFloat) {
        guard hasImage else { return }
        fits = false
        let oldSize = document.bounds.size
        let visible = scroll.contentView.bounds
        let fraction = NSPoint(x: visible.midX / max(oldSize.width, 1), y: visible.midY / max(oldSize.height, 1))
        zoom = min(max(value, 0.01), 8)
        updateImageFrame()
        let newSize = document.bounds.size
        scroll.contentView.scroll(to: NSPoint(x: max(0, fraction.x * newSize.width - visible.width / 2),
                                               y: max(0, fraction.y * newSize.height - visible.height / 2)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func updateImageFrame() {
        let viewport = scroll.contentSize
        guard hasImage, pixelSize.width > 0, viewport.width > 0, viewport.height > 0 else {
            document.frame = NSRect(origin: .zero, size: viewport)
            return
        }
        if fits {
            zoom = min((viewport.width - 48) / pixelSize.width, (viewport.height - 48) / pixelSize.height,
                       1 / (window?.backingScaleFactor ?? 1))
            zoom = max(0.001, zoom)
        }
        let size = NSSize(width: pixelSize.width * zoom, height: pixelSize.height * zoom)
        let full = NSSize(width: max(viewport.width, size.width + 48), height: max(viewport.height, size.height + 48))
        document.setFrameSize(full)
        document.imageView.frame = NSRect(x: (full.width - size.width) / 2, y: (full.height - size.height) / 2,
                                          width: size.width, height: size.height)
        document.markup.frame = document.imageView.frame
        document.markup.bounds = NSRect(origin: .zero, size: pixelSize)
        document.markup.isHidden = editor == nil
        document.needsDisplay = true
        onZoomChanged?(zoom * (window?.backingScaleFactor ?? 1))
    }

    func centerImage() {
        let size = scroll.contentView.bounds.size
        scroll.contentView.scroll(to: NSPoint(x: max(0, (document.bounds.width - size.width) / 2),
                                               y: max(0, (document.bounds.height - size.height) / 2)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    override func magnify(with event: NSEvent) { setZoom(zoom * (1 + event.magnification)) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let url = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first {
            onDrop?(url.isFileURL ? url.path : url.absoluteString)
            return true
        }
        if let value = sender.draggingPasteboard.string(forType: .string) {
            onDrop?(value)
            return true
        }
        return false
    }
}

enum Shortcut: Int, CaseIterable {
    case controlOptionI, controlOptionSpace, commandShiftI, disabled
    var title: String {
        switch self {
        case .controlOptionI: return "⌃ ⌥ I"
        case .controlOptionSpace: return "⌃ ⌥ Space"
        case .commandShiftI: return "⌘ ⇧ I"
        case .disabled: return "Disabled"
        }
    }
    var key: UInt32 {
        switch self {
        case .controlOptionI, .commandShiftI: return UInt32(kVK_ANSI_I)
        case .controlOptionSpace, .disabled: return UInt32(kVK_Space)
        }
    }
    var modifiers: UInt32 {
        self == .commandShiftI ? UInt32(cmdKey | shiftKey) : UInt32(controlKey | optionKey)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextFieldDelegate, NSMenuItemValidation {
    var window: NSWindow!
    let address = AddressField()
    let canvas = ImageCanvas(frame: .zero)
    let stateLabel = label("Fast Image Viewer", size: 11, color: Palette.muted)
    let metadata = label("View, mark, and share an image", size: 10, weight: .medium, color: Palette.muted)
    let zoomLabel = label("100%", size: 11, weight: .medium, color: Palette.muted)
    let shortcutLabel = label("", size: 11, weight: .medium, color: Palette.muted)
    let openButton = ChromeButton(title: "Open", target: nil, action: nil)
    let revealButton = ChromeButton(title: "", target: nil, action: nil)
    var addressShell: NSView?
    let spinner = NSProgressIndicator()
    var zoomControls: [NSButton] = []
    let toolPicker = IconToolPicker()
    let colorPicker = MarkColorPicker()
    let activeToolLabel = label("Select", size: 12, weight: .semibold)
    let toolKeyLabel = label("V", size: 10, weight: .medium, color: Palette.muted)
    let toolOptions = NSStackView()
    let toolSummary = label("Move marks · Pan image", size: 11, color: Palette.muted)
    let colorWell = NSColorWell()
    let strokePicker = NSPopUpButton()
    let textSizePicker = NSPopUpButton()
    let editHint = label("Open an image to use the editing tools.", size: 11, color: Palette.muted)
    let exportButton = ChromeButton(title: "Export…", target: nil, action: nil)
    let applyCropButton = ChromeButton(title: "Apply Crop", target: nil, action: nil)
    let cancelCropButton = ChromeButton(title: "Cancel", target: nil, action: nil)
    var undoButton: NSButton!
    var redoButton: NSButton!
    var editControls: [NSControl] = []
    var isExporting = false
    var originalMetadata = ""
    var source: ImageSource?
    var loader: ImageLoader?
    var loadID = UUID()
    var statusItem: NSStatusItem!
    var statusMenu: NSMenu!
    var hotKey: EventHotKeyRef?
    var hotKeyHandler: EventHandlerRef?
    var keyMonitor: Any?
    var shortcutItems: [NSMenuItem] = []
    var shortcut: Shortcut = Shortcut(rawValue: UserDefaults.standard.integer(forKey: "shortcut")) ?? .controlOptionI
    var shortcutAvailable = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        makeMenus()
        if window == nil { makeWindow() }
        makeStatusItem()
        installHotKeyHandler()
        // Also handle app-targeted keyboard events (including accessibility tools).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, NSApp.keyWindow === self.window else { return event }
            let modifiers = event.modifierFlags.intersection([.control, .option, .command, .shift])
            let expected: NSEvent.ModifierFlags = self.shortcut == .commandShiftI ? [.command, .shift] : [.control, .option]
            if self.shortcut != .disabled, UInt32(event.keyCode) == self.shortcut.key, modifiers == expected {
                self.openClipboard(nil)
                return nil
            }
            if event.keyCode == UInt16(kVK_Escape) {
                if !self.canvas.document.markup.cancelInteraction() { self.cancelOrHide() }
                return nil
            }
            return event
        }
        registerShortcut()
        showWindow(nil)
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
        if let first = args.first, first != "--smoke-test" { openAddress(first) }
    }

    func configure(_ button: NSButton, action: Selector, prominent: Bool = false) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.font = .systemFont(ofSize: 12, weight: prominent ? .semibold : .medium)
        button.contentTintColor = prominent ? NSColor(hex: 0x201A3A) : Palette.muted
        (button as? ChromeButton)?.style = prominent ? .primary : .quiet
    }

    func iconButton(_ name: String, action: Selector, tooltip: String) -> NSButton {
        let button = ChromeButton(image: symbol(name)!, target: self, action: action)
        configure(button, action: action)
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    @objc func showWindow(_ sender: Any?) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        focusAddress(nil)
    }

    @objc func focusAddress(_ sender: Any?) {
        window.makeFirstResponder(address)
        address.selectText(nil)
    }

    @objc func openClipboard(_ sender: Any?) {
        showWindow(nil)
        if let url = (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first,
           url.isFileURL {
            openAddress(url.path)
        } else if let value = NSPasteboard.general.string(forType: .string), (try? ImageSource.parse(value)) != nil {
            openAddress(value)
        } else {
            stateLabel.stringValue = "Copy an image path or URL, then paste it above."
            stateLabel.textColor = Palette.muted
        }
    }

    @objc func openFromField(_ sender: Any?) { openAddress(address.stringValue) }

    func openAddress(_ value: String, discardConfirmed: Bool = false) {
        guard window.attachedSheet == nil else { return }
        if let editor = canvas.editor, editor.isDirty, !discardConfirmed {
            guard (try? ImageSource.parse(value)) != nil else {
                stateLabel.stringValue = "Enter a valid image path or URL. Your edits are still here."
                return
            }
            confirmDiscard { [weak self] proceed in
                if proceed { self?.openAddress(value, discardConfirmed: true) }
                else { self?.address.stringValue = self?.source?.address ?? value }
            }
            return
        }
        loader?.cancel()
        canvas.document.markup.editor = nil
        window.isDocumentEdited = false
        updateEditorUI()
        let id = UUID()
        loadID = id
        address.stringValue = value
        source = nil
        revealButton.isHidden = true
        zoomControls.forEach { $0.isEnabled = false }
        metadata.stringValue = ""
        zoomLabel.stringValue = "—"
        do {
            let parsed = try ImageSource.parse(value)
            address.stringValue = parsed.address
            source = parsed
            stateLabel.stringValue = parsed.isLocal ? "Opening image…" : "Downloading image…"
            stateLabel.textColor = Palette.muted
            spinner.startAnimation(nil)
            canvas.placeholder(title: "Opening your image…", detail: parsed.name)
            let newLoader = ImageLoader()
            loader = newLoader
            newLoader.load(parsed) { [weak self] result in
                guard let self = self, self.loadID == id else { return }
                self.spinner.stopAnimation(nil)
                self.loader = nil
                switch result {
                case .success(let loaded):
                    guard let image = NSImage(data: loaded.data) else { self.showError(SourceError.notImage); return }
                    self.canvas.show(image, pixels: NSSize(width: loaded.width, height: loaded.height))
                    self.zoomControls.forEach { $0.isEnabled = true }
                    self.stateLabel.stringValue = parsed.name
                    self.stateLabel.toolTip = parsed.address
                    self.stateLabel.textColor = Palette.text
                    let bytes = ByteCountFormatter.string(fromByteCount: Int64(loaded.data.count), countStyle: .file)
                    self.originalMetadata = "\(loaded.width) × \(loaded.height)  ·  \(loaded.format)  ·  \(bytes)"
                    self.metadata.stringValue = self.originalMetadata
                    self.revealButton.isHidden = !parsed.isLocal
                    self.window.title = "\(parsed.name) — Fast Image Viewer"
                    self.window.representedURL = parsed.isLocal ? parsed.url : nil
                    do {
                        let editor = try ImageEditor(data: loaded.data, maxDimension: max(loaded.width, loaded.height))
                        self.canvas.beginEditing(editor)
                        self.canvas.updateImageFrame()
                    } catch {
                        self.editHint.stringValue = "Viewing only: this image couldn’t be prepared for editing."
                    }
                case .failure(let error): self.showError(error)
                }
            }
        } catch { showError(error) }
    }

    func showError(_ error: Error) {
        spinner.stopAnimation(nil)
        stateLabel.stringValue = "Couldn’t open image"
        stateLabel.textColor = .systemOrange
        stateLabel.toolTip = error.localizedDescription
        canvas.placeholder(title: "Let’s try another address.", detail: error.localizedDescription, isError: true)
        updateEditorUI()
        window.title = "Fast Image Viewer"
        window.representedURL = nil
    }

    @objc func browseFiles(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Open an image"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url {
                DispatchQueue.main.async { self?.openAddress(url.path) }
            }
        }
    }

    @objc func revealFile(_ sender: Any?) {
        if let source = source, source.isLocal { NSWorkspace.shared.activateFileViewerSelecting([source.url]) }
    }
    @objc func fitImage(_ sender: Any?) { canvas.fit() }
    @objc func actualSize(_ sender: Any?) { canvas.actual() }
    @objc func zoomIn(_ sender: Any?) { canvas.stepZoom(1.25) }
    @objc func zoomOut(_ sender: Any?) { canvas.stepZoom(0.8) }

    func cancelOrHide() {
        if loader != nil {
            loader?.cancel()
            loader = nil
            loadID = UUID()
            spinner.stopAnimation(nil)
            canvas.placeholder(title: "Open an image to begin", detail: "Paste a path or URL above, or drop an image here.")
            stateLabel.stringValue = "Cancelled"
        } else { window.orderOut(nil) }
    }

    func makeMenus() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Fast Image Viewer", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        let shortcutMenu = NSMenu(title: "Global Shortcut")
        for shortcut in Shortcut.allCases {
            let item = shortcutMenu.addItem(withTitle: shortcut.title, action: #selector(changeShortcut), keyEquivalent: "")
            item.target = self
            item.tag = shortcut.rawValue
            shortcutItems.append(item)
        }
        let shortcutParent = appMenu.addItem(withTitle: "Global Shortcut", action: nil, keyEquivalent: "")
        shortcutParent.submenu = shortcutMenu
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Fast Image Viewer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Fast Image Viewer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)

        let fileMenu = NSMenu(title: "File")
        menuItem(fileMenu, "Open Image…", #selector(browseFiles), "o")
        let clip = menuItem(fileMenu, "Open from Clipboard", #selector(openClipboard), "v")
        clip.keyEquivalentModifierMask = [.command, .shift]
        menuItem(fileMenu, "Focus Address", #selector(focusAddress), "l")
        fileMenu.addItem(.separator())
        menuItem(fileMenu, "Export Edited Copy…", #selector(exportEditedImage), "s")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(); fileItem.submenu = fileMenu; main.addItem(fileItem)

        let edit = NSMenu(title: "Edit")
        menuItem(edit, "Undo", #selector(undoEdit), "z")
        let redo = menuItem(edit, "Redo", #selector(redoEdit), "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let copyImage = menuItem(edit, "Copy Image with Marks", #selector(copyEditedImage), "c")
        copyImage.keyEquivalentModifierMask = [.command, .shift]
        menuItem(edit, "Rotate Clockwise", #selector(rotateImage), "")
        let editItem = NSMenuItem(); editItem.submenu = edit; main.addItem(editItem)

        let view = NSMenu(title: "View")
        menuItem(view, "Fit Image", #selector(fitImage), "0")
        menuItem(view, "Actual Pixels", #selector(actualSize), "1")
        menuItem(view, "Zoom In", #selector(zoomIn), "+")
        menuItem(view, "Zoom Out", #selector(zoomOut), "-")
        menuItem(view, "Show Viewer", #selector(showWindow), "n")
        let viewItem = NSMenuItem(); viewItem.submenu = view; main.addItem(viewItem)
        NSApp.mainMenu = main
    }

    @discardableResult
    func menuItem(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = symbol("photo", size: 15)
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "Fast Image Viewer — click to open; right-click for menu"
        statusItem.button?.setAccessibilityLabel("Fast Image Viewer")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let menu = NSMenu()
        menuItem(menu, "Open from Clipboard", #selector(openClipboard), "")
        menuItem(menu, "Show Viewer", #selector(showWindow), "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Fast Image Viewer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusMenu = menu
    }

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            // Anchor to the actual click, including when a menu-bar manager moves the icon.
            // A synthetic performClick can use the status item's original screen position.
            let click = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(click) } ?? sender.window?.screen
            let barHeight = sender.window?.frame.height ?? NSStatusBar.system.thickness
            let top = screen.map { $0.frame.maxY - barHeight } ?? click.y
            sender.highlight(true)
            defer { sender.highlight(false) }
            statusMenu.popUp(positioning: nil,
                             at: NSPoint(x: click.x - sender.bounds.width / 2, y: top - 4), in: nil)
        } else {
            showWindow(nil)
        }
    }

    func installHotKeyHandler() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context = context, let event = event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x46495652, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            app.openClipboard(nil)
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
    }

    func registerShortcut() {
        if let key = hotKey { UnregisterEventHotKey(key); hotKey = nil }
        shortcutAvailable = true
        if shortcut != .disabled {
            let id = EventHotKeyID(signature: 0x46495652, id: 1)
            shortcutAvailable = RegisterEventHotKey(shortcut.key, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr
        }
        shortcutLabel.stringValue = shortcut == .disabled ? "⌘ L  to focus address" :
            (shortcutAvailable ? "\(shortcut.title)   Open clipboard" : "Shortcut unavailable")
        shortcutLabel.toolTip = "Open an image address from your clipboard, from any app. Change the shortcut in Fast Image Viewer → Global Shortcut."
        shortcutItems.forEach { $0.state = $0.tag == shortcut.rawValue ? .on : .off }
    }

    @objc func changeShortcut(_ sender: NSMenuItem) {
        shortcut = Shortcut(rawValue: sender.tag) ?? .controlOptionI
        UserDefaults.standard.set(shortcut.rawValue, forKey: "shortcut")
        registerShortcut()
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Fast Image Viewer",
            .applicationVersion: "1.2",
            .credits: NSAttributedString(string: "Paste a path. See the image.\n\nThe global shortcut opens an image address from your clipboard.\nClosing the window keeps the shortcut active. Use ⌘Q to quit.")
        ])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard canvas.editor?.isDirty == true else { return .terminateNow }
        showWindow(nil)
        confirmDiscard { sender.reply(toApplicationShouldTerminate: $0) }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(nil); return true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if window == nil { makeWindow() }
        showWindow(nil)
        if let first = filenames.first { openAddress(first) }
        sender.reply(toOpenOrPrint: .success)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if window == nil { makeWindow() }
        showWindow(nil)
        if let first = urls.first { openAddress(first.isFileURL ? first.path : first.absoluteString) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        loader?.cancel()
        if let keyMonitor = keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let hotKey = hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler = hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
