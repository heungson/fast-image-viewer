import AppKit

/// Native buttons retain AppKit keyboard tracking and accessibility, with a shared visual treatment.
final class ChromeButton: NSButton {
    enum Style { case quiet, subtle, primary, tool }
    var style: Style = .quiet { didSet { needsDisplay = true } }
    private var hovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let selected = style == .tool && state == .on && isEnabled
        let pressed = cell?.isHighlighted == true
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        var foreground = isEnabled ? Palette.text : Palette.muted.withAlphaComponent(0.32)
        if style == .primary && isEnabled {
            let top = NSColor(hex: hovered ? 0xC1B2FF : 0xB5A2FF)
            let bottom = NSColor(hex: pressed ? 0x8A73D8 : 0x9F88EB)
            NSGradient(starting: bottom, ending: top)?.draw(in: shape, angle: 90)
            NSColor.white.withAlphaComponent(0.16).setStroke(); shape.lineWidth = 1; shape.stroke()
            foreground = NSColor(hex: 0x211933)
        } else {
            let fill: NSColor
            if selected { fill = Palette.accent.withAlphaComponent(0.17); foreground = Palette.accent }
            else if (hovered || pressed) && isEnabled { fill = NSColor.white.withAlphaComponent(pressed ? 0.11 : 0.065) }
            else if style == .subtle || style == .primary { fill = Palette.surface }
            else { fill = .clear }
            fill.setFill(); shape.fill()
            if selected || style == .subtle {
                (selected ? Palette.accent.withAlphaComponent(0.28) : Palette.border).setStroke()
                shape.lineWidth = 1; shape.stroke()
            }
        }

        let displayTitle = imagePosition == .imageOnly ? "" : title
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: foreground]
        let textSize = (displayTitle as NSString).size(withAttributes: attributes)
        let iconSide: CGFloat = image == nil ? 0 : 16
        let gap: CGFloat = image == nil || displayTitle.isEmpty ? 0 : 7
        let total = (displayTitle.isEmpty ? 0 : textSize.width) + iconSide + gap
        let leading = (bounds.width - total) / 2
        let trailingImage = imagePosition == .imageTrailing
        if let image = image {
            let natural = image.size
            let ratio = min(iconSide / max(natural.width, 1), iconSide / max(natural.height, 1))
            let size = NSSize(width: natural.width * ratio, height: natural.height * ratio)
            let iconX = trailingImage ? leading + textSize.width + gap : leading
            let rect = NSRect(x: iconX + (iconSide - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
            let tinted = NSImage(size: natural, flipped: false) { target in
                image.draw(in: target)
                foreground.setFill(); target.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        if !displayTitle.isEmpty {
            let x = leading + (trailingImage ? 0 : iconSide + gap)
            (displayTitle as NSString).draw(at: NSPoint(x: x, y: (bounds.height - textSize.height) / 2), withAttributes: attributes)
        }
        if window?.firstResponder === self {
            Palette.accent.withAlphaComponent(0.7).setStroke(); shape.lineWidth = 2; shape.stroke()
        }
    }
}

final class IconToolPicker: NSControl {
    private var buttons: [ChromeButton] = []
    var selectedSegment = 0 { didSet { refresh() } }
    override var isEnabled: Bool { didSet { buttons.forEach { $0.isEnabled = isEnabled }; refresh() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: 0x17191F).cgColor
        layer?.cornerRadius = 10
        layer?.borderColor = Palette.border.withAlphaComponent(0.65).cgColor
        layer?.borderWidth = 1
        setAccessibilityRole(.group)
        setAccessibilityLabel("Markup tools")
        setAccessibilityElement(true)
        for tool in MarkupTool.allCases {
            let button = ChromeButton(image: NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title)!, target: self, action: #selector(choose))
            button.tag = tool.rawValue; button.style = .tool
            button.setButtonType(.pushOnPushOff); button.isBordered = false
            button.setAccessibilityLabel(tool.title)
            button.setAccessibilityParent(self)
            button.toolTip = "\(tool.title) (\(tool.key.uppercased())) — \(tool.hint)"
            buttons.append(button)
        }
        setAccessibilityChildren(buttons)
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 2
        addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
        buttons.forEach {
            $0.widthAnchor.constraint(equalToConstant: 32).isActive = true
            $0.heightAnchor.constraint(equalToConstant: 32).isActive = true
        }
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 244, height: 40) }
    private func refresh() {
        for button in buttons { button.state = button.tag == selectedSegment ? .on : .off; button.needsDisplay = true }
    }
    @objc private func choose(_ sender: NSButton) {
        selectedSegment = sender.tag
        sendAction(action, to: target)
    }
}

func surfaceView(radius: CGFloat = 12, color: NSColor = Palette.surface, border: Bool = true) -> NSView {
    let view = NSView(); view.wantsLayer = true
    view.layer?.backgroundColor = color.cgColor; view.layer?.cornerRadius = radius
    if border { view.layer?.borderWidth = 1; view.layer?.borderColor = Palette.border.cgColor }
    return view
}

final class BrandBadge: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSGradient(starting: NSColor(hex: 0xB7A6FF), ending: NSColor(hex: 0x7962C8))?.draw(in: shape, angle: -55)
        NSColor.white.withAlphaComponent(0.16).setStroke(); shape.lineWidth = 1; shape.stroke()
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        let image = NSImageView()
        image.image = symbol("photo.stack", size: 18)
        image.contentTintColor = .white
        addSubview(image); image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: centerXAnchor), image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 21), image.heightAnchor.constraint(equalToConstant: 21)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}
