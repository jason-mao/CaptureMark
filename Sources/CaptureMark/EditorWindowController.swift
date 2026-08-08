import AppKit
import UniformTypeIdentifiers

final class EditorWindowController: NSWindowController, NSToolbarDelegate, AnnotationCanvasViewDelegate {
    private enum ToolbarID {
        static let capture = NSToolbarItem.Identifier("Capture")
        static let tools = NSToolbarItem.Identifier("Tools")
        static let color = NSToolbarItem.Identifier("Color")
        static let fontSize = NSToolbarItem.Identifier("FontSize")
        static let textOutline = NSToolbarItem.Identifier("TextOutline")
        static let undo = NSToolbarItem.Identifier("Undo")
        static let copy = NSToolbarItem.Identifier("Copy")
        static let export = NSToolbarItem.Identifier("Export")
    }

    let canvas = AnnotationCanvasView(frame: .zero)
    var onCaptureRequested: (() -> Void)?

    private weak var toolControl: NSSegmentedControl?
    private weak var colorWell: NSColorWell?
    private weak var fontSlider: NSSlider?
    private weak var fontSizeLabel: NSTextField?
    private weak var textOutlineToggle: NSButton?
    private weak var textOutlineColorWell: NSColorWell?

    init() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CaptureMark"
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.backgroundColor = .windowBackgroundColor
        window.minSize = CGSize(width: 720, height: 480)
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = canvas

        super.init(window: window)

        canvas.delegate = self
        let toolbar = NSToolbar(identifier: "CaptureMarkToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setScreenshot(_ screenshot: CapturedScreenshot) {
        canvas.setScreenshot(screenshot)
        showEditor()
    }

    func showEditor() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
    }

    func undo() {
        canvas.performUndo()
    }

    func redo() {
        canvas.performRedo()
    }

    func copyResult() {
        canvas.commitPendingTextEntry()
        guard let image = canvas.renderedImage(), let pngData = canvas.renderedPNGData() else {
            NSSound.beep()
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        pasteboard.setData(pngData, forType: .png)
        showTransientTitle("已复制到剪贴板")
    }

    func exportPNG() {
        canvas.commitPendingTextEntry()
        guard let pngData = canvas.renderedPNGData() else {
            NSSound.beep()
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename()
        panel.title = "导出标注截图"
        panel.prompt = "导出"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try pngData.write(to: url, options: .atomic)
            showTransientTitle("已导出 \(url.lastPathComponent)")
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "PNG 导出失败"
            alert.runModal()
        }
    }

    func deleteSelection() {
        canvas.deleteSelection()
    }

    func canvasSelectionDidChange(_ annotation: Annotation?) {
        guard let annotation else {
            updateTextOutlineControls(
                enabled: canvas.currentTextOutlineEnabled,
                color: canvas.currentTextOutlineColor
            )
            return
        }
        switch annotation {
        case .text(let text):
            colorWell?.color = text.color
            fontSlider?.doubleValue = text.fontSize
            updateFontSizeLabel(text.fontSize)
            canvas.currentTextOutlineEnabled = text.outlineColor != nil
            if let outlineColor = text.outlineColor {
                canvas.currentTextOutlineColor = outlineColor
            }
            updateTextOutlineControls(
                enabled: canvas.currentTextOutlineEnabled,
                color: canvas.currentTextOutlineColor
            )
        case .arrow(let arrow):
            colorWell?.color = arrow.color
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarID.capture, ToolbarID.tools, ToolbarID.color, ToolbarID.fontSize,
            ToolbarID.textOutline,
            .flexibleSpace, ToolbarID.undo, ToolbarID.copy, ToolbarID.export,
            .space
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarID.capture, .space, ToolbarID.tools, ToolbarID.color,
            ToolbarID.fontSize, ToolbarID.textOutline, .flexibleSpace, ToolbarID.undo,
            ToolbarID.copy, ToolbarID.export
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case ToolbarID.capture:
            return buttonItem(
                identifier: identifier,
                label: "框选截图",
                symbol: "camera.viewfinder",
                action: #selector(requestCapture)
            )
        case ToolbarID.tools:
            let control = NSSegmentedControl(
                labels: ["选择", "文字", "箭头"],
                trackingMode: .selectOne,
                target: self,
                action: #selector(toolChanged(_:))
            )
            control.selectedSegment = 0
            control.setWidth(54, forSegment: 0)
            control.setWidth(54, forSegment: 1)
            control.setWidth(54, forSegment: 2)
            toolControl = control
            return customItem(identifier: identifier, label: "工具", view: control)
        case ToolbarID.color:
            let well = NSColorWell(frame: CGRect(x: 0, y: 0, width: 44, height: 30))
            well.color = canvas.currentColor
            well.target = self
            well.action = #selector(colorChanged(_:))
            colorWell = well
            return customItem(identifier: identifier, label: "颜色", view: well)
        case ToolbarID.fontSize:
            let slider = NSSlider(value: 28, minValue: 12, maxValue: 96, target: self, action: #selector(fontSizeChanged(_:)))
            slider.isContinuous = true
            slider.widthAnchor.constraint(equalToConstant: 94).isActive = true
            let label = NSTextField(labelWithString: "28 pt")
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: 38).isActive = true
            let stack = NSStackView(views: [slider, label])
            stack.orientation = .horizontal
            stack.spacing = 5
            fontSlider = slider
            fontSizeLabel = label
            return customItem(identifier: identifier, label: "字号", view: stack)
        case ToolbarID.textOutline:
            let toggle = NSButton(
                checkboxWithTitle: "描边",
                target: self,
                action: #selector(textOutlineToggled(_:))
            )
            toggle.state = canvas.currentTextOutlineEnabled ? .on : .off
            toggle.toolTip = "开启或关闭文字描边"

            let well = NSColorWell(frame: CGRect(x: 0, y: 0, width: 38, height: 28))
            well.color = canvas.currentTextOutlineColor
            well.isEnabled = canvas.currentTextOutlineEnabled
            well.target = self
            well.action = #selector(textOutlineColorChanged(_:))
            well.toolTip = "文字描边颜色"

            let stack = NSStackView(views: [toggle, well])
            stack.orientation = .horizontal
            stack.spacing = 6
            textOutlineToggle = toggle
            textOutlineColorWell = well
            return customItem(identifier: identifier, label: "文字描边", view: stack)
        case ToolbarID.undo:
            return buttonItem(
                identifier: identifier,
                label: "撤销",
                symbol: "arrow.uturn.backward",
                action: #selector(undoClicked)
            )
        case ToolbarID.copy:
            return buttonItem(
                identifier: identifier,
                label: "复制",
                symbol: "doc.on.doc",
                action: #selector(copyClicked)
            )
        case ToolbarID.export:
            return buttonItem(
                identifier: identifier,
                label: "导出 PNG",
                symbol: "square.and.arrow.down",
                action: #selector(exportClicked)
            )
        default:
            return nil
        }
    }

    @objc private func requestCapture() {
        canvas.commitPendingTextEntry()
        onCaptureRequested?()
    }

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        canvas.tool = EditorTool(rawValue: sender.selectedSegment) ?? .select
        window?.makeFirstResponder(canvas)
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        canvas.setColor(sender.color)
    }

    @objc private func fontSizeChanged(_ sender: NSSlider) {
        let value = CGFloat(sender.doubleValue.rounded())
        updateFontSizeLabel(value)
        canvas.setFontSize(value)
    }

    @objc private func textOutlineToggled(_ sender: NSButton) {
        let enabled = sender.state == .on
        textOutlineColorWell?.isEnabled = enabled
        canvas.setTextOutlineEnabled(enabled)
        window?.makeFirstResponder(canvas)
    }

    @objc private func textOutlineColorChanged(_ sender: NSColorWell) {
        canvas.setTextOutlineColor(sender.color)
    }

    @objc private func undoClicked() {
        undo()
    }

    @objc private func copyClicked() {
        copyResult()
    }

    @objc private func exportClicked() {
        exportPNG()
    }

    private func buttonItem(identifier: NSToolbarItem.Identifier, label: String, symbol: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }

    private func customItem(identifier: NSToolbarItem.Identifier, label: String, view: NSView) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.view = view
        return item
    }

    private func updateFontSizeLabel(_ value: CGFloat) {
        fontSizeLabel?.stringValue = "\(Int(value)) pt"
    }

    private func updateTextOutlineControls(enabled: Bool, color: NSColor) {
        textOutlineToggle?.state = enabled ? .on : .off
        textOutlineColorWell?.color = color
        textOutlineColorWell?.isEnabled = enabled
    }

    private func suggestedFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "CaptureMark-\(formatter.string(from: Date())).png"
    }

    private func showTransientTitle(_ message: String) {
        guard let window else { return }
        let originalTitle = "CaptureMark"
        window.title = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak window] in
            window?.title = originalTitle
        }
    }
}
