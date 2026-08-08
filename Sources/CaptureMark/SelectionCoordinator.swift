import AppKit
import CoreGraphics
import ScreenCaptureKit

final class SelectionCoordinator {
    private var windows: [SelectionWindow] = []
    private var completion: ((CapturedScreenshot?) -> Void)?

    func start(completion: @escaping (CapturedScreenshot?) -> Void) {
        guard ensureScreenCapturePermission() else {
            completion(nil)
            return
        }

        self.completion = completion
        NSApp.activate(ignoringOtherApps: true)

        windows = NSScreen.screens.map { screen in
            let window = SelectionWindow(screen: screen)
            window.selectionView.onSelection = { [weak self] rect in
                self?.finish(screen: screen, localRect: rect)
            }
            window.selectionView.onCancel = { [weak self] in
                self?.cancel()
            }
            window.orderFrontRegardless()
            return window
        }

        windows.first?.makeKey()
        windows.first?.makeFirstResponder(windows.first?.selectionView)
    }

    private func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        if CGRequestScreenCaptureAccess() {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "请在“系统设置 → 隐私与安全性 → 屏幕录制”中允许 CaptureMark，然后重新打开应用。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    private func finish(screen: NSScreen, localRect: CGRect) {
        let normalizedRect = localRect.standardized.integral
        guard normalizedRect.width >= 4, normalizedRect.height >= 4,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            cancel()
            return
        }

        closeWindows()

        let displayID = CGDirectDisplayID(number.uint32Value)
        let captureRect = CGRect(
            x: normalizedRect.minX,
            y: screen.frame.height - normalizedRect.maxY,
            width: normalizedRect.width,
            height: normalizedRect.height
        )

        if #available(macOS 14.0, *) {
            captureWithScreenCaptureKit(
                displayID: displayID,
                captureRect: captureRect,
                pointSize: normalizedRect.size,
                scale: screen.backingScaleFactor
            )
        } else {
            captureWithCoreGraphics(
                displayID: displayID,
                captureRect: captureRect,
                pointSize: normalizedRect.size
            )
        }
    }

    @available(macOS 14.0, *)
    private func captureWithScreenCaptureKit(
        displayID: CGDirectDisplayID,
        captureRect: CGRect,
        pointSize: CGSize,
        scale: CGFloat
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw CaptureError.displayNotFound
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.sourceRect = captureRect
                configuration.width = max(1, Int(pointSize.width * scale))
                configuration.height = max(1, Int(pointSize.height * scale))
                configuration.showsCursor = false

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                self.complete(with: image, pointSize: pointSize)
            } catch {
                self.captureWithCoreGraphics(
                    displayID: displayID,
                    captureRect: captureRect,
                    pointSize: pointSize
                )
            }
        }
    }

    private func captureWithCoreGraphics(
        displayID: CGDirectDisplayID,
        captureRect: CGRect,
        pointSize: CGSize
    ) {
        guard let image = CGDisplayCreateImage(displayID, rect: captureRect) else {
            showCaptureFailure()
            completion?(nil)
            completion = nil
            return
        }
        complete(with: image, pointSize: pointSize)
    }

    private func complete(with image: CGImage, pointSize: CGSize) {
        let result = CapturedScreenshot(cgImage: image, pointSize: pointSize)
        completion?(result)
        completion = nil
    }

    private func cancel() {
        closeWindows()
        completion?(nil)
        completion = nil
    }

    private func closeWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func showCaptureFailure() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "截图失败"
        alert.informativeText = "无法读取所选屏幕区域。请检查屏幕录制权限后重试。"
        alert.runModal()
    }
}

private enum CaptureError: Error {
    case displayNotFound
}

final class SelectionWindow: NSWindow {
    let selectionView = SelectionView()

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = selectionView
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
}

final class SelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let selectionRect, selectionRect.width >= 4, selectionRect.height >= 4 else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }
        onSelection?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()

        guard let selectionRect else {
            drawHint()
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        selectionRect.fill()
        NSGraphicsContext.restoreGraphicsState()

        let border = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        NSColor.white.setStroke()
        border.stroke()

        let sizeText = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = sizeText.size(withAttributes: attributes)
        let badgeRect = CGRect(
            x: selectionRect.minX,
            y: max(6, selectionRect.minY - textSize.height - 10),
            width: textSize.width + 14,
            height: textSize.height + 6
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5).fill()
        sizeText.draw(at: CGPoint(x: badgeRect.minX + 7, y: badgeRect.minY + 3), withAttributes: attributes)
    }

    private func drawHint() {
        let text = "拖拽框选截图区域  ·  Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: bounds.midX - size.width / 2 - 14,
            y: bounds.midY - size.height / 2 - 8,
            width: size.width + 28,
            height: size.height + 16
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        text.draw(at: CGPoint(x: rect.minX + 14, y: rect.minY + 8), withAttributes: attributes)
    }
}
