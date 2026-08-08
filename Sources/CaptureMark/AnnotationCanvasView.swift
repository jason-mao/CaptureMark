import AppKit

protocol AnnotationCanvasViewDelegate: AnyObject {
    func canvasSelectionDidChange(_ annotation: Annotation?)
}

final class AnnotationCanvasView: NSView {
    weak var delegate: AnnotationCanvasViewDelegate?

    private(set) var screenshot: CapturedScreenshot?
    private(set) var annotations: [Annotation] = []
    private(set) var selectedID: UUID?

    var tool: EditorTool = .select {
        didSet {
            cancelTextEntry()
            arrowStart = nil
            arrowCurrent = nil
            needsDisplay = true
        }
    }
    var currentColor: NSColor = .systemRed
    var currentFontSize: CGFloat = 28

    private let actionUndoManager = UndoManager()
    private var arrowStart: CGPoint?
    private var arrowCurrent: CGPoint?
    private weak var activeTextView: InlineTextView?
    private weak var activeTextContainer: NSScrollView?
    private var activeTextPosition: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { actionUndoManager }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.105, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setScreenshot(_ screenshot: CapturedScreenshot) {
        cancelTextEntry()
        self.screenshot = screenshot
        annotations = []
        selectedID = nil
        actionUndoManager.removeAllActions()
        needsDisplay = true
        notifySelectionChanged()
    }

    func setColor(_ color: NSColor) {
        currentColor = color
        activeTextView?.textColor = color
        guard let selectedID, let index = annotations.firstIndex(where: { $0.id == selectedID }) else {
            return
        }

        var updated = annotations
        switch updated[index] {
        case .text(var annotation):
            annotation.color = color
            updated[index] = .text(annotation)
        case .arrow(var annotation):
            annotation.color = color
            updated[index] = .arrow(annotation)
        }
        setAnnotations(updated, actionName: "更改颜色")
    }

    func setFontSize(_ size: CGFloat) {
        currentFontSize = size
        updateActiveTextEditorLayout()
        guard let selectedID, let index = annotations.firstIndex(where: { $0.id == selectedID }),
              case .text(var annotation) = annotations[index] else {
            return
        }

        annotation.fontSize = size
        var updated = annotations
        updated[index] = .text(annotation)
        setAnnotations(updated, actionName: "更改字号")
    }

    func deleteSelection() {
        guard let selectedID else { return }
        let updated = annotations.filter { $0.id != selectedID }
        self.selectedID = nil
        setAnnotations(updated, actionName: "删除标注")
        notifySelectionChanged()
    }

    func performUndo() {
        actionUndoManager.undo()
    }

    func performRedo() {
        actionUndoManager.redo()
    }

    func renderedPNGData() -> Data? {
        guard let screenshot else { return nil }

        let width = max(1, Int(screenshot.pixelSize.width.rounded()))
        let height = max(1, Int(screenshot.pixelSize.height.rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        let pointSize = screenshot.image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.scaleBy(
            x: CGFloat(width) / pointSize.width,
            y: CGFloat(height) / pointSize.height
        )
        screenshot.image.draw(
            in: CGRect(origin: .zero, size: pointSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        drawAnnotations(in: CGRect(origin: .zero, size: pointSize), showSelection: false)
        NSGraphicsContext.restoreGraphicsState()

        bitmap.size = pointSize
        return bitmap.representation(using: .png, properties: [:])
    }

    func renderedImage() -> NSImage? {
        guard let pngData = renderedPNGData() else { return nil }
        return NSImage(data: pngData)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor(calibratedWhite: 0.105, alpha: 1).setFill()
        bounds.fill()

        guard let screenshot else {
            drawEmptyState()
            return
        }

        let imageRect = displayRect(for: screenshot.image.size)
        NSColor.black.withAlphaComponent(0.25).setFill()
        imageRect.insetBy(dx: -1, dy: -1).fill()
        screenshot.image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        drawAnnotations(in: imageRect, showSelection: true)

        if let start = arrowStart, let end = arrowCurrent {
            let preview = ArrowAnnotation(
                id: UUID(),
                start: start,
                end: end,
                color: currentColor,
                lineWidth: 4
            )
            drawArrow(preview, in: imageRect, selected: false)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let imagePoint = imagePoint(fromViewPoint: convert(event.locationInWindow, from: nil)) else {
            return
        }

        switch tool {
        case .select:
            selectedID = hitTestAnnotation(at: imagePoint)?.id
            notifySelectionChanged()
            needsDisplay = true
        case .text:
            beginTextEntry(at: imagePoint)
        case .arrow:
            arrowStart = imagePoint
            arrowCurrent = imagePoint
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard tool == .arrow, arrowStart != nil else { return }
        arrowCurrent = clampedImagePoint(fromViewPoint: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard tool == .arrow, let start = arrowStart else { return }
        let end = clampedImagePoint(fromViewPoint: convert(event.locationInWindow, from: nil)) ?? start
        arrowStart = nil
        arrowCurrent = nil

        guard hypot(end.x - start.x, end.y - start.y) >= 5 else {
            needsDisplay = true
            return
        }

        let annotation = ArrowAnnotation(
            id: UUID(),
            start: start,
            end: end,
            color: currentColor,
            lineWidth: 4
        )
        selectedID = annotation.id
        setAnnotations(annotations + [.arrow(annotation)], actionName: "添加箭头")
        notifySelectionChanged()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            deleteSelection()
        } else {
            super.keyDown(with: event)
        }
    }

    private func beginTextEntry(at position: CGPoint) {
        commitTextEntry()
        guard screenshot != nil else { return }

        let viewPoint = viewPoint(fromImagePoint: position)
        let availableWidth = max(180, bounds.maxX - viewPoint.x - 12)
        let container = NSScrollView(frame: CGRect(
            x: viewPoint.x,
            y: viewPoint.y - 3,
            width: min(420, availableWidth),
            height: 44
        ))
        container.hasVerticalScroller = false
        container.hasHorizontalScroller = false
        container.autohidesScrollers = true
        container.drawsBackground = true
        container.backgroundColor = .controlBackgroundColor
        container.borderType = .noBorder
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        let textView = InlineTextView(frame: container.contentView.bounds)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = false
        textView.autoresizingMask = [.height]
        textView.drawsBackground = false
        textView.textColor = currentColor
        textView.placeholder = "输入文字 · Return 完成"
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.onCommit = { [weak self] in self?.commitTextEntry() }
        textView.onCancel = { [weak self] in self?.cancelTextEntry() }

        container.documentView = textView
        addSubview(container)
        activeTextContainer = container
        activeTextView = textView
        activeTextPosition = position
        updateActiveTextEditorLayout()
        window?.makeFirstResponder(textView)
    }

    private func updateActiveTextEditorLayout() {
        guard let textView = activeTextView,
              let container = activeTextContainer,
              let position = activeTextPosition else { return }
        let editorFontSize = min(96, max(16, currentFontSize * displayScale))
        let fieldHeight = ceil(editorFontSize * 1.35 + 16)
        let viewPoint = viewPoint(fromImagePoint: position)
        var frame = container.frame
        frame.origin.y = min(viewPoint.y - 3, bounds.maxY - fieldHeight - 8)
        frame.size.height = fieldHeight
        container.frame = frame

        let font = NSFont.systemFont(ofSize: editorFontSize, weight: .semibold)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let verticalInset = max(6, floor((fieldHeight - lineHeight) / 2))
        textView.font = font
        textView.textContainerInset = CGSize(width: 10, height: verticalInset)
        textView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: max(container.contentSize.width, textView.intrinsicContentSize.width), height: fieldHeight)
        )
        textView.needsDisplay = true
    }

    private func commitTextEntry() {
        guard let textView = activeTextView,
              let container = activeTextContainer,
              let position = activeTextPosition else { return }
        activeTextView = nil
        activeTextContainer = nil
        activeTextPosition = nil
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        textView.onCommit = nil
        textView.onCancel = nil
        container.removeFromSuperview()

        guard !text.isEmpty else {
            window?.makeFirstResponder(self)
            return
        }

        let annotation = TextAnnotation(
            id: UUID(),
            text: text,
            position: position,
            color: currentColor,
            fontSize: currentFontSize
        )
        selectedID = annotation.id
        setAnnotations(annotations + [.text(annotation)], actionName: "添加文字")
        notifySelectionChanged()
        window?.makeFirstResponder(self)
    }

    private func cancelTextEntry() {
        guard let textView = activeTextView, let container = activeTextContainer else { return }
        activeTextView = nil
        activeTextContainer = nil
        activeTextPosition = nil
        textView.onCommit = nil
        textView.onCancel = nil
        container.removeFromSuperview()
        window?.makeFirstResponder(self)
    }

    private func setAnnotations(_ newAnnotations: [Annotation], actionName: String) {
        let oldAnnotations = annotations
        actionUndoManager.registerUndo(withTarget: self) { target in
            target.setAnnotations(oldAnnotations, actionName: actionName)
        }
        actionUndoManager.setActionName(actionName)
        annotations = newAnnotations
        if let selectedID, !annotations.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
            notifySelectionChanged()
        }
        needsDisplay = true
    }

    private func notifySelectionChanged() {
        let selection = selectedID.flatMap { id in annotations.first(where: { $0.id == id }) }
        delegate?.canvasSelectionDidChange(selection)
    }

    private var displayScale: CGFloat {
        guard let screenshot else { return 1 }
        return displayRect(for: screenshot.image.size).width / screenshot.image.size.width
    }

    private func displayRect(for imageSize: CGSize) -> CGRect {
        let available = bounds.insetBy(dx: 24, dy: 24)
        guard imageSize.width > 0, imageSize.height > 0,
              available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / imageSize.width, available.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func imagePoint(fromViewPoint point: CGPoint) -> CGPoint? {
        guard let screenshot else { return nil }
        let rect = displayRect(for: screenshot.image.size)
        guard rect.contains(point) else { return nil }
        let scale = rect.width / screenshot.image.size.width
        return CGPoint(x: (point.x - rect.minX) / scale, y: (point.y - rect.minY) / scale)
    }

    private func clampedImagePoint(fromViewPoint point: CGPoint) -> CGPoint? {
        guard let screenshot else { return nil }
        let rect = displayRect(for: screenshot.image.size)
        let clamped = CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
        let scale = rect.width / screenshot.image.size.width
        return CGPoint(x: (clamped.x - rect.minX) / scale, y: (clamped.y - rect.minY) / scale)
    }

    private func viewPoint(fromImagePoint point: CGPoint) -> CGPoint {
        guard let screenshot else { return point }
        let rect = displayRect(for: screenshot.image.size)
        let scale = rect.width / screenshot.image.size.width
        return CGPoint(x: rect.minX + point.x * scale, y: rect.minY + point.y * scale)
    }

    private func drawAnnotations(in targetRect: CGRect, showSelection: Bool) {
        for annotation in annotations {
            let selected = showSelection && annotation.id == selectedID
            switch annotation {
            case .text(let text):
                drawText(text, in: targetRect, selected: selected)
            case .arrow(let arrow):
                drawArrow(arrow, in: targetRect, selected: selected)
            }
        }
    }

    private func drawText(_ annotation: TextAnnotation, in targetRect: CGRect, selected: Bool) {
        guard let screenshot else { return }
        let scale = targetRect.width / screenshot.image.size.width
        let point = CGPoint(
            x: targetRect.minX + annotation.position.x * scale,
            y: targetRect.minY + annotation.position.y * scale
        )
        let font = NSFont.systemFont(ofSize: annotation.fontSize * scale, weight: .semibold)
        let whiteHalo: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.clear,
            .strokeColor: NSColor.white.withAlphaComponent(0.95),
            .strokeWidth: -18
        ]
        let darkOutline: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.clear,
            .strokeColor: NSColor.black.withAlphaComponent(0.92),
            .strokeWidth: -10
        ]
        let fill: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.color
        ]

        // 两层相反颜色的描边让文字在纯黑、纯白和复杂背景上都保持清晰。
        annotation.text.draw(at: point, withAttributes: whiteHalo)
        annotation.text.draw(at: point, withAttributes: darkOutline)
        annotation.text.draw(at: point, withAttributes: fill)

        if selected {
            let size = annotation.text.size(withAttributes: fill)
            drawSelectionBox(CGRect(origin: point, size: size).insetBy(dx: -6, dy: -5))
        }
    }

    private func drawArrow(_ annotation: ArrowAnnotation, in targetRect: CGRect, selected: Bool) {
        guard let screenshot else { return }
        let scale = targetRect.width / screenshot.image.size.width
        let start = CGPoint(
            x: targetRect.minX + annotation.start.x * scale,
            y: targetRect.minY + annotation.start.y * scale
        )
        let end = CGPoint(
            x: targetRect.minX + annotation.end.x * scale,
            y: targetRect.minY + annotation.end.y * scale
        )
        let baseWidth = max(1, annotation.lineWidth * scale)
        let outlineWidth = max(1.2, 2.4 * scale)

        // 白色外缘 + 黑色内缘 + 用户颜色，避免箭头消失在相近颜色的截图里。
        drawArrowLayer(
            from: start,
            to: end,
            lineWidth: baseWidth + outlineWidth * 2,
            headExpansion: outlineWidth * 1.4,
            color: NSColor.white.withAlphaComponent(0.95),
            scale: scale
        )
        drawArrowLayer(
            from: start,
            to: end,
            lineWidth: baseWidth + outlineWidth,
            headExpansion: outlineWidth * 0.7,
            color: NSColor.black.withAlphaComponent(0.92),
            scale: scale
        )
        drawArrowLayer(
            from: start,
            to: end,
            lineWidth: baseWidth,
            headExpansion: 0,
            color: annotation.color,
            scale: scale
        )

        if selected {
            drawHandle(at: start)
            drawHandle(at: end)
        }
    }

    private func drawArrowLayer(
        from start: CGPoint,
        to end: CGPoint,
        lineWidth: CGFloat,
        headExpansion: CGFloat,
        color: NSColor,
        scale: CGFloat
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(0.001, hypot(dx, dy))
        let ux = dx / length
        let uy = dy / length
        let coreHeadLength = max(12 * scale, 18 * scale)
        let headLength = coreHeadLength + headExpansion
        let headWidth = coreHeadLength * 0.72 + headExpansion * 1.4
        let base = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)
        let left = CGPoint(x: base.x - uy * headWidth / 2, y: base.y + ux * headWidth / 2)
        let right = CGPoint(x: base.x + uy * headWidth / 2, y: base.y - ux * headWidth / 2)

        color.setStroke()
        color.setFill()
        let shaft = NSBezierPath()
        shaft.move(to: start)
        shaft.line(to: base)
        shaft.lineWidth = lineWidth
        shaft.lineCapStyle = .round
        shaft.stroke()

        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: left)
        head.line(to: right)
        head.close()
        head.fill()
    }

    private func drawSelectionBox(_ rect: CGRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        path.lineWidth = 1
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }

    private func drawHandle(at point: CGPoint) {
        let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(ovalIn: rect)
        border.lineWidth = 1.5
        border.stroke()
    }

    private func hitTestAnnotation(at point: CGPoint) -> Annotation? {
        let scale = max(0.01, displayScale)
        for annotation in annotations.reversed() {
            switch annotation {
            case .text(let text):
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: text.fontSize, weight: .semibold)
                ]
                let size = text.text.size(withAttributes: attributes)
                let rect = CGRect(origin: text.position, size: size).insetBy(dx: -8 / scale, dy: -8 / scale)
                if rect.contains(point) { return annotation }
            case .arrow(let arrow):
                if distanceFromPoint(point, toSegmentFrom: arrow.start, to: arrow.end) <= 10 / scale {
                    return annotation
                }
            }
        }
        return nil
    }

    private func distanceFromPoint(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    private func drawEmptyState() {
        let title = "准备好截一张图"
        let subtitle = "点击工具栏中的“框选截图”，拖拽选择屏幕区域"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 23, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let titleSize = title.size(withAttributes: titleAttributes)
        let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
        title.draw(
            at: CGPoint(x: bounds.midX - titleSize.width / 2, y: bounds.midY + 4),
            withAttributes: titleAttributes
        )
        subtitle.draw(
            at: CGPoint(x: bounds.midX - subtitleSize.width / 2, y: bounds.midY - 30),
            withAttributes: subtitleAttributes
        )
    }
}

private final class InlineTextView: NSTextView {
    var placeholder = ""
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, !hasMarkedText() {
            onCommit?()
            return
        }
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let size = placeholder.size(withAttributes: attributes)
        placeholder.draw(
            at: CGPoint(
                x: textContainerInset.width,
                y: max(4, (bounds.height - size.height) / 2)
            ),
            withAttributes: attributes
        )
    }
}
