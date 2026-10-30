import AppKit
import ImageIO

enum MarkupTool: Int, CaseIterable {
    case select, pen, arrow, rectangle, ellipse, text, crop
    var title: String { ["Select", "Pen", "Arrow", "Box", "Oval", "Text", "Crop"][rawValue] }
    var symbolName: String { ["cursorarrow", "pencil.tip", "arrow.up.right", "rectangle", "oval", "textformat", "crop"][rawValue] }
    var key: String { ["v", "p", "a", "r", "o", "t", "c"][rawValue] }
    var hint: String {
        switch self {
        case .select: return "Click a mark to select it. Drag to move it; Delete removes it. Drag empty space to pan."
        case .pen: return "Drag on the image to draw a freehand mark."
        case .arrow: return "Drag from the tail to the tip of an arrow."
        case .rectangle: return "Drag on the image to outline a rectangle."
        case .ellipse: return "Drag on the image to outline an oval."
        case .text: return "Click on the image to add a text label."
        case .crop: return "Drag to select an area, then choose Apply Crop or press Return."
        }
    }
}

struct ImageMark {
    let tool: MarkupTool
    var points: [CGPoint]
    let color: NSColor
    let width: CGFloat
    var text = ""
    var fontSize: CGFloat = 22

    var rect: CGRect {
        guard let start = points.first else { return .zero }
        if tool == .text {
            let size = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)])
            return CGRect(origin: start, size: size)
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min() ?? start.x, y: ys.min() ?? start.y,
                      width: (xs.max() ?? start.x) - (xs.min() ?? start.x),
                      height: (ys.max() ?? start.y) - (ys.min() ?? start.y))
    }

    func moved(by delta: CGPoint) -> ImageMark {
        var copy = self
        copy.points = points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        return copy
    }

    func draw(in context: CGContext) {
        guard let start = points.first else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch tool {
        case .pen:
            if points.count == 1 {
                context.fillEllipse(in: CGRect(x: start.x - width / 2, y: start.y - width / 2, width: width, height: width))
            } else {
                context.addLines(between: points)
                context.strokePath()
            }
        case .rectangle: context.stroke(rect)
        case .ellipse: context.strokeEllipse(in: rect)
        case .arrow:
            guard let end = points.last else { return }
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = min(hypot(end.x - start.x, end.y - start.y) * 0.6, width * 4.5)
            context.move(to: start); context.addLine(to: end); context.strokePath()
            context.move(to: CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)))
            context.addLine(to: end)
            context.addLine(to: CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6)))
            context.strokePath()
        case .text:
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            (text as NSString).draw(at: start, withAttributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: color
            ])
            NSGraphicsContext.restoreGraphicsState()
        default: break
        }
    }
}

struct EditorState {
    let base: CGImage
    var marks: [ImageMark] = []
    var id = UUID()
    var size: CGSize { CGSize(width: base.width, height: base.height) }
}

enum EditError: LocalizedError {
    case render, crop, original
    var errorDescription: String? {
        switch self {
        case .render: return "The image couldn’t be rendered. Try a smaller image or free some memory."
        case .crop: return "Select an area at least 2 × 2 pixels inside the image."
        case .original: return "Choose a different filename to keep your original image."
        }
    }
}

final class ImageEditor {
    private(set) var state: EditorState
    private var undoStates: [EditorState] = []
    private var redoStates: [EditorState] = []
    private var savedID: UUID
    var onChange: (() -> Void)?
    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }
    var isDirty: Bool { state.id != savedID }

    init(image: CGImage) {
        state = EditorState(base: image)
        savedID = state.id
    }

    convenience init(data: Data, maxDimension: Int) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension
              ] as CFDictionary) else { throw EditError.render }
        self.init(image: image)
    }

    private func commit(_ next: EditorState) {
        undoStates.append(state)
        redoStates.removeAll()
        state = next
        // Mark operations share their base bitmap; bound retained bitmaps after crops/rotations.
        while undoStates.count > 50 || (undoStates.count > 1 && retainedBytes() > 256 * 1024 * 1024) {
            undoStates.removeFirst()
        }
        onChange?()
    }

    private func retainedBytes() -> Int {
        var seen = Set<ObjectIdentifier>()
        return ([state] + undoStates).reduce(0) { total, item in
            guard seen.insert(ObjectIdentifier(item.base)).inserted else { return total }
            return total + item.base.bytesPerRow * item.base.height
        }
    }

    func add(_ mark: ImageMark) {
        var next = state; next.id = UUID(); next.marks.append(mark); commit(next)
    }
    func replaceMark(at index: Int, with mark: ImageMark) {
        guard state.marks.indices.contains(index) else { return }
        var next = state; next.id = UUID(); next.marks[index] = mark; commit(next)
    }
    func removeMark(at index: Int) {
        guard state.marks.indices.contains(index) else { return }
        var next = state; next.id = UUID(); next.marks.remove(at: index); commit(next)
    }
    func undo() {
        guard let previous = undoStates.popLast() else { return }
        redoStates.append(state); state = previous; onChange?()
    }
    func redo() {
        guard let next = redoStates.popLast() else { return }
        undoStates.append(state); state = next; onChange?()
    }
    func markExported(_ id: UUID) { savedID = id; onChange?() }

    static func context(width: Int, height: Int) throws -> CGContext {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw EditError.render }
        return context
    }

    static func render(_ state: EditorState) throws -> CGImage {
        if state.marks.isEmpty { return state.base }
        let context = try context(width: state.base.width, height: state.base.height)
        context.draw(state.base, in: CGRect(origin: .zero, size: state.size))
        context.translateBy(x: 0, y: state.size.height)
        context.scaleBy(x: 1, y: -1)
        state.marks.forEach { $0.draw(in: context) }
        guard let result = context.makeImage() else { throw EditError.render }
        return result
    }

    func crop(to rect: CGRect) throws {
        let clipped = rect.standardized.intersection(CGRect(origin: .zero, size: state.size))
        guard !clipped.isNull else { throw EditError.crop }
        // Snap inward so every exported pixel belongs to the selected region.
        let pixels = CGRect(x: ceil(clipped.minX), y: ceil(clipped.minY),
                            width: floor(clipped.maxX) - ceil(clipped.minX),
                            height: floor(clipped.maxY) - ceil(clipped.minY))
        guard pixels.width >= 2, pixels.height >= 2,
              let image = try Self.render(state).cropping(to: pixels) else { throw EditError.crop }
        commit(EditorState(base: image))
    }

    func rotateClockwise() throws {
        let image = try Self.render(state)
        let context = try Self.context(width: image.height, height: image.width)
        context.translateBy(x: 0, y: CGFloat(image.width))
        context.rotate(by: -.pi / 2)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let rotated = context.makeImage() else { throw EditError.render }
        commit(EditorState(base: rotated))
    }

    static func export(_ state: EditorState, jpeg: Bool = false) throws -> Data {
        var image = try render(state)
        if jpeg {
            let context = try Self.context(width: image.width, height: image.height)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: state.size))
            context.draw(image, in: CGRect(origin: .zero, size: state.size))
            guard let opaque = context.makeImage() else { throw EditError.render }
            image = opaque
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, (jpeg ? "public.jpeg" : "public.png") as CFString, 1, nil) else {
            throw EditError.render
        }
        CGImageDestinationAddImage(destination, image, jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary : nil)
        guard CGImageDestinationFinalize(destination) else { throw EditError.render }
        return data as Data
    }
}

final class MarkupView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var editor: ImageEditor? { didSet { resetInteraction() } }
    var tool = MarkupTool.select { didSet { resetInteraction(); window?.invalidateCursorRects(for: self) } }
    var color = NSColor(srgbRed: 1, green: 0.25, blue: 0.3, alpha: 1)
    var strokeSize: CGFloat = 4
    var textSize: CGFloat = 22
    var onInteractionChanged: (() -> Void)?
    var onTextRequested: ((CGPoint, NSColor, CGFloat) -> Void)?
    var onCropRequested: (() -> Void)?
    private(set) var selectedIndex: Int?
    private(set) var cropRect: CGRect?
    private var start: CGPoint?
    private var draft: ImageMark?
    private var originalMark: ImageMark?
    private var panOrigin: CGPoint?
    private var panWindowPoint: CGPoint?
    var scale: CGFloat { max(0.001, frame.width / max(bounds.width, 1)) }

    func resetInteraction() {
        start = nil; draft = nil; originalMark = nil; selectedIndex = nil; cropRect = nil
        panOrigin = nil; panWindowPoint = nil
        needsDisplay = true; onInteractionChanged?()
    }

    @discardableResult func cancelInteraction() -> Bool {
        let active = start != nil || selectedIndex != nil || cropRect != nil || tool != .select
        if active { tool = .select }
        return active
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: tool == .select ? .arrow : .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        guard let editor = editor, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); defer { context.restoreGState() }
        for (index, mark) in editor.state.marks.enumerated() {
            if index == selectedIndex, originalMark != nil, let draft = draft { draft.draw(in: context) }
            else { mark.draw(in: context) }
        }
        if originalMark == nil { draft?.draw(in: context) }
        if let index = selectedIndex, editor.state.marks.indices.contains(index) {
            let rect = (draft ?? editor.state.marks[index]).rect.insetBy(dx: -6 / scale, dy: -6 / scale)
            context.setStrokeColor(NSColor.white.cgColor); context.setLineWidth(1 / scale)
            context.setLineDash(phase: 0, lengths: [5 / scale, 4 / scale]); context.stroke(rect)
        }
        if let crop = cropRect, crop.width > 0, crop.height > 0 {
            context.setLineDash(phase: 0, lengths: [])
            context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            context.addRect(bounds); context.addRect(crop); context.fillPath(using: .evenOdd)
            context.setStrokeColor(NSColor.white.cgColor); context.setLineWidth(1.5 / scale)
            context.stroke(crop)
        }
    }

    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(0, p.x), bounds.width), y: min(max(0, p.y), bounds.height))
    }

    override func mouseDown(with event: NSEvent) {
        guard let editor = editor else { return }
        window?.makeFirstResponder(self)
        let p = point(event)
        start = p; draft = nil; originalMark = nil; selectedIndex = nil; cropRect = nil
        if tool == .select {
            selectedIndex = editor.state.marks.indices.reversed().first {
                let mark = editor.state.marks[$0]
                return mark.rect.insetBy(dx: -max(mark.width, 6 / scale), dy: -max(mark.width, 6 / scale)).contains(p)
            }
            if let index = selectedIndex { originalMark = editor.state.marks[index] }
            else if let clip = enclosingScrollView?.contentView { panOrigin = clip.bounds.origin; panWindowPoint = event.locationInWindow }
        } else if tool != .crop && tool != .text {
            draft = ImageMark(tool: tool, points: [p], color: color, width: strokeSize / scale)
        }
        needsDisplay = true; onInteractionChanged?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = start else { return }
        let p = point(event)
        if tool == .crop {
            cropRect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(start.x - p.x), height: abs(start.y - p.y))
        } else if let mark = originalMark {
            draft = mark.moved(by: CGPoint(x: p.x - start.x, y: p.y - start.y))
        } else if let origin = panOrigin, let anchor = panWindowPoint, let scroll = enclosingScrollView {
            let delta = CGPoint(x: event.locationInWindow.x - anchor.x, y: event.locationInWindow.y - anchor.y)
            scroll.contentView.scroll(to: CGPoint(x: origin.x - delta.x, y: origin.y + delta.y))
            scroll.reflectScrolledClipView(scroll.contentView)
        } else if draft != nil {
            if tool == .pen { draft?.points.append(p) }
            else { draft?.points = [start, p] }
        }
        needsDisplay = true; onInteractionChanged?()
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = start else { return }
        if tool == .text { onTextRequested?(start, color, textSize / scale) }
        else if let draft = draft {
            if let index = selectedIndex, originalMark != nil { editor?.replaceMark(at: index, with: draft) }
            else if tool == .pen || hypot((draft.points.last?.x ?? start.x) - start.x, (draft.points.last?.y ?? start.y) - start.y) * scale >= 3 {
                editor?.add(draft)
            }
        }
        self.start = nil; draft = nil; originalMark = nil; panOrigin = nil; panWindowPoint = nil
        needsDisplay = true; onInteractionChanged?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            if let index = selectedIndex { editor?.removeMark(at: index); selectedIndex = nil; needsDisplay = true }
            return
        }
        if event.keyCode == 36, tool == .crop { onCropRequested?(); return }
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let tool = MarkupTool.allCases.first(where: { $0.key == event.charactersIgnoringModifiers?.lowercased() }) {
            self.tool = tool; return
        }
        super.keyDown(with: event)
    }
}
