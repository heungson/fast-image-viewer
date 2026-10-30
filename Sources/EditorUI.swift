import AppKit
import UniformTypeIdentifiers

extension AppDelegate {
    func makeEditingToolbar() -> NSView {
        toolPicker.target = self; toolPicker.action = #selector(changeTool)
        toolPicker.selectedSegment = 0
        colorWell.color = canvas.document.markup.color
        colorWell.target = self; colorWell.action = #selector(changeMarkStyle)
        colorWell.setAccessibilityLabel("Mark color")
        colorWell.toolTip = "Color for new marks"
        for width in [2, 4, 8, 12] { strokePicker.addItem(withTitle: "\(width) pt"); strokePicker.lastItem?.tag = width }
        strokePicker.selectItem(withTag: 4)
        strokePicker.target = self; strokePicker.action = #selector(changeMarkStyle)
        strokePicker.font = .systemFont(ofSize: 11)
        strokePicker.setAccessibilityLabel("Mark line width")
        strokePicker.toolTip = "Width for new marks at the current zoom"
        for size in [14, 22, 32, 48, 64] { textSizePicker.addItem(withTitle: "Text: \(size) pt"); textSizePicker.lastItem?.tag = size }
        textSizePicker.selectItem(withTag: 22)
        textSizePicker.target = self; textSizePicker.action = #selector(changeMarkStyle)
        textSizePicker.font = .systemFont(ofSize: 11)
        textSizePicker.setAccessibilityLabel("New text size")
        undoButton = iconButton("arrow.uturn.backward", action: #selector(undoEdit), tooltip: "Undo edit (⌘Z)")
        redoButton = iconButton("arrow.uturn.forward", action: #selector(redoEdit), tooltip: "Redo edit (⇧⌘Z)")
        let rotate = iconButton("rotate.right", action: #selector(rotateImage), tooltip: "Rotate 90° clockwise")
        exportButton.toolTip = "Export an edited copy (⌘S)"
        configure(applyCropButton, action: #selector(applyCrop), prominent: true)
        configure(cancelCropButton, action: #selector(cancelCrop))
        colorPicker.selectedColor = colorWell.color
        colorPicker.target = self; colorPicker.action = #selector(chooseMarkColor)
        let divider = surfaceView(radius: 0, color: Palette.border, border: false)
        let history = NSStackView(views: [undoButton, redoButton, rotate])
        history.orientation = .vertical; history.spacing = 6
        let rail = surfaceView(radius: 14)
        [toolPicker, divider, history].forEach { rail.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            toolPicker.centerXAnchor.constraint(equalTo: rail.centerXAnchor), toolPicker.topAnchor.constraint(equalTo: rail.topAnchor, constant: 6),
            divider.topAnchor.constraint(greaterThanOrEqualTo: toolPicker.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: rail.leadingAnchor, constant: 14), divider.trailingAnchor.constraint(equalTo: rail.trailingAnchor, constant: -14),
            divider.heightAnchor.constraint(equalToConstant: 1), divider.bottomAnchor.constraint(equalTo: history.topAnchor, constant: -12),
            history.centerXAnchor.constraint(equalTo: rail.centerXAnchor), history.bottomAnchor.constraint(equalTo: rail.bottomAnchor, constant: -12)
        ])
        editControls = [toolPicker, colorWell, colorPicker, strokePicker, rotate, exportButton]
        return rail
    }

    func makeToolOptions() -> NSView {
        let card = NSView()
        let title = NSStackView(views: [activeToolLabel, toolKeyLabel])
        title.orientation = .horizontal; title.spacing = 8; title.alignment = .centerY
        toolKeyLabel.alignment = .center
        toolKeyLabel.wantsLayer = true; toolKeyLabel.layer?.cornerRadius = 4
        toolKeyLabel.layer?.borderWidth = 1; toolKeyLabel.layer?.borderColor = Palette.border.cgColor
        toolOptions.orientation = .horizontal; toolOptions.alignment = .centerY; toolOptions.spacing = 10
        [colorPicker, colorWell, strokePicker, textSizePicker].forEach(toolOptions.addArrangedSubview)
        let cropActions = NSStackView(views: [cancelCropButton, applyCropButton])
        cropActions.orientation = .horizontal; cropActions.alignment = .centerY; cropActions.spacing = 8
        [title, toolOptions, toolSummary, cropActions].forEach { card.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 4), title.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            title.widthAnchor.constraint(equalToConstant: 90), toolKeyLabel.widthAnchor.constraint(equalToConstant: 20), toolKeyLabel.heightAnchor.constraint(equalToConstant: 18),
            toolOptions.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 16), toolOptions.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            toolSummary.leadingAnchor.constraint(equalTo: toolOptions.leadingAnchor), toolSummary.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            cropActions.trailingAnchor.constraint(equalTo: card.trailingAnchor), cropActions.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            colorWell.widthAnchor.constraint(equalToConstant: 28), colorWell.heightAnchor.constraint(equalToConstant: 26),
            strokePicker.widthAnchor.constraint(equalToConstant: 68), textSizePicker.widthAnchor.constraint(equalToConstant: 110),
            applyCropButton.widthAnchor.constraint(equalToConstant: 100), applyCropButton.heightAnchor.constraint(equalToConstant: 30),
            cancelCropButton.widthAnchor.constraint(equalToConstant: 58), cancelCropButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        return card
    }

    @objc func chooseMarkColor(_ sender: MarkColorPicker) {
        colorWell.color = sender.selectedColor
        changeMarkStyle(sender)
    }

    func updateEditorUI() {
        let editor = canvas.editor
        editControls.forEach { $0.isEnabled = editor != nil }
        undoButton?.isEnabled = editor?.canUndo == true
        redoButton?.isEnabled = editor?.canRedo == true
        exportButton.isEnabled = editor != nil && !isExporting
        let markup = canvas.document.markup
        toolPicker.selectedSegment = markup.tool.rawValue
        activeToolLabel.stringValue = markup.tool.title
        toolKeyLabel.stringValue = markup.tool.key.uppercased()
        toolOptions.isHidden = editor == nil || markup.tool == .select || markup.tool == .crop
        toolSummary.isHidden = !toolOptions.isHidden
        toolSummary.stringValue = editor == nil ? "Open an image to start" : markup.tool == .crop ? "Drag to frame your crop" : "Move marks · Pan image"
        strokePicker.isHidden = markup.tool == .text
        applyCropButton.isHidden = editor == nil || markup.tool != .crop
        cancelCropButton.isHidden = applyCropButton.isHidden
        applyCropButton.isEnabled = (markup.cropRect?.width ?? 0) >= 2 && (markup.cropRect?.height ?? 0) >= 2
        textSizePicker.isHidden = editor == nil || markup.tool != .text
        editHint.stringValue = editor == nil ? "Open an image to use the editing tools." : markup.tool.hint
        window?.isDocumentEdited = editor?.isDirty == true
        if let editor = editor {
            let size = editor.state.size
            metadata.stringValue = editor.isDirty || editor.canUndo ? "\(Int(size.width)) × \(Int(size.height))  ·  \(editor.isDirty ? "Unsaved edits" : "Exported")" : originalMetadata
            stateLabel.stringValue = source?.name ?? "Image"
            stateLabel.textColor = Palette.text
        }
    }

    @objc func changeTool(_ sender: IconToolPicker) {
        guard canvas.editor != nil, let tool = MarkupTool(rawValue: sender.selectedSegment) else { return }
        canvas.document.markup.tool = tool
        window.makeFirstResponder(canvas.document.markup)
    }

    @objc func changeMarkStyle(_ sender: Any?) {
        canvas.document.markup.color = colorWell.color.usingColorSpace(.sRGB) ?? colorWell.color
        colorPicker.selectedColor = colorWell.color
        canvas.document.markup.strokeSize = CGFloat(strokePicker.selectedItem?.tag ?? 4)
        canvas.document.markup.textSize = CGFloat(textSizePicker.selectedItem?.tag ?? 22)
    }

    @objc func undoEdit(_ sender: Any?) {
        if !(sender is NSButton), let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.undo() }
        else { canvas.document.markup.resetInteraction(); canvas.editor?.undo() }
    }
    @objc func redoEdit(_ sender: Any?) {
        if !(sender is NSButton), let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.redo() }
        else { canvas.document.markup.resetInteraction(); canvas.editor?.redo() }
    }

    @objc func rotateImage(_ sender: Any?) {
        guard let editor = canvas.editor else { return }
        canvas.document.markup.resetInteraction()
        do { try editor.rotateClockwise(); window.makeFirstResponder(canvas.document.markup) }
        catch { presentEditError(error) }
    }
    @objc func applyCrop(_ sender: Any?) {
        guard let editor = canvas.editor, let rect = canvas.document.markup.cropRect else { return }
        do {
            try editor.crop(to: rect)
            canvas.document.markup.tool = .select
            window.makeFirstResponder(canvas.document.markup)
        } catch { presentEditError(error) }
    }
    @objc func cancelCrop(_ sender: Any?) { canvas.document.markup.tool = .select }

    func addText(at point: CGPoint, color: NSColor, size: CGFloat) {
        guard let editor = canvas.editor, window.attachedSheet == nil else { return }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
        field.placeholderString = "Type a label…"
        field.setAccessibilityLabel("Text label")
        let alert = NSAlert()
        alert.messageText = "Add a text label"
        alert.informativeText = "The label will appear at the point you clicked."
        alert.addButton(withTitle: "Add Text"); alert.addButton(withTitle: "Cancel")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] result in
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result == .alertFirstButtonReturn, !text.isEmpty, self?.canvas.editor === editor else { return }
            editor.add(ImageMark(tool: .text, points: [point], color: color, width: 1, text: String(text.prefix(1000)), fontSize: size))
            self?.window.makeFirstResponder(self?.canvas.document.markup)
        }
    }

    func presentEditError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "Couldn’t complete the edit"
        alert.informativeText = error.localizedDescription
        alert.beginSheetModal(for: window)
    }

    @objc func exportEditedImage(_ sender: Any?) { exportImage() }

    func exportImage(completion: ((Bool) -> Void)? = nil) {
        guard let editor = canvas.editor, !isExporting, window.attachedSheet == nil else { completion?(false); return }
        let panel = NSSavePanel()
        panel.title = "Export an edited copy"
        panel.prompt = "Export"
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true
        let stem = ((source?.name ?? "image") as NSString).deletingPathExtension
        panel.nameFieldStringValue = (stem.isEmpty ? "image" : stem) + "-edited.png"
        panel.message = "Use .png to keep transparency, or .jpg for JPEG with a white background. Animated images export as a still frame."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { completion?(false); return }
            let original = self.source?.isLocal == true ? self.source?.url : nil
            if let original = original, original.resolvingSymlinksInPath().path.caseInsensitiveCompare(url.resolvingSymlinksInPath().path) == .orderedSame {
                self.presentEditError(EditError.original); completion?(false); return
            }
            let state = editor.state
            self.isExporting = true; self.spinner.startAnimation(nil); self.updateEditorUI()
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try ImageEditor.export(state, jpeg: ["jpg", "jpeg"].contains(url.pathExtension.lowercased())).write(to: url, options: .atomic) }
                DispatchQueue.main.async {
                    self.isExporting = false; self.spinner.stopAnimation(nil)
                    switch result {
                    case .success:
                        editor.markExported(state.id)
                        self.updateEditorUI()
                        self.stateLabel.stringValue = "Exported \(url.lastPathComponent)"
                        self.stateLabel.toolTip = url.path
                        completion?(self.canvas.editor === editor && editor.state.id == state.id)
                    case .failure(let error): self.updateEditorUI(); self.presentEditError(error); completion?(false)
                    }
                }
            }
        }
    }

    @objc func copyEditedImage(_ sender: Any?) {
        guard let editor = canvas.editor, !isExporting else { return }
        let state = editor.state
        isExporting = true; spinner.startAnimation(nil); updateEditorUI()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let result = Result { try ImageEditor.export(state) }
            DispatchQueue.main.async {
                self.isExporting = false; self.spinner.stopAnimation(nil); self.updateEditorUI()
                switch result {
                case .success(let data):
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setData(data, forType: .png)
                    self.stateLabel.stringValue = "Image copied with marks"
                case .failure(let error): self.presentEditError(error)
                }
            }
        }
    }

    func confirmDiscard(completion: @escaping (Bool) -> Void) {
        guard window.attachedSheet == nil else { completion(false); return }
        let alert = NSAlert()
        alert.messageText = "Keep your image edits?"
        alert.informativeText = "Export a copy to keep your work. Discarding will lose the current edits."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard Edits")
        alert.addButton(withTitle: "Export…")
        alert.beginSheetModal(for: window) { [weak self] response in
            // AppKit invokes the callback before detaching the outgoing sheet.
            DispatchQueue.main.async {
                if response == .alertSecondButtonReturn { completion(true) }
                else if response == .alertThirdButtonReturn { self?.exportImage(completion: completion) }
                else { completion(false) }
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undoEdit):
            return (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.canUndo ?? (canvas.editor?.canUndo == true)
        case #selector(redoEdit):
            return (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.canRedo ?? (canvas.editor?.canRedo == true)
        case #selector(exportEditedImage), #selector(copyEditedImage): return canvas.editor != nil && !isExporting
        case #selector(rotateImage): return canvas.editor != nil
        default: return true
        }
    }
}
