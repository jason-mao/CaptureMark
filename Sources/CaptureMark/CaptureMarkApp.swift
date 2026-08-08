import AppKit

@main
enum CaptureMarkApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let editor = EditorWindowController()
    private let selectionCoordinator = SelectionCoordinator()
    private let globalHotKey = GlobalHotKey()
    private var statusItem: NSStatusItem?
    private weak var captureStatusMenuItem: NSMenuItem?
    private var editorWasVisibleBeforeCapture = false
    private var isCapturing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        configureStatusItem()
        editor.onCaptureRequested = { [weak self] in self?.beginCapture() }
        registerGlobalCaptureShortcut()
        editor.showEditor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotKey.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func beginCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        editorWasVisibleBeforeCapture = editor.window?.isVisible == true
        editor.window?.orderOut(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            self.selectionCoordinator.start { [weak self] screenshot in
                guard let self else { return }
                self.isCapturing = false
                if let screenshot {
                    self.editor.setScreenshot(screenshot)
                } else if self.editorWasVisibleBeforeCapture {
                    self.editor.showEditor()
                }
            }
        }
    }

    @objc private func showEditor() {
        editor.showEditor()
    }

    @objc private func undo() {
        editor.undo()
    }

    @objc private func redo() {
        editor.redo()
    }

    @objc private func copyResult() {
        editor.copyResult()
    }

    @objc private func exportPNG() {
        editor.exportPNG()
    }

    @objc private func deleteSelection() {
        editor.deleteSelection()
    }

    @objc private func terminate() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "CaptureMark")
        item.button?.toolTip = "CaptureMark"

        let menu = NSMenu()
        let captureItem = menuItem("框选截图（⌘⇧2）", action: #selector(beginCapture), key: "2", modifiers: [.command, .shift])
        menu.addItem(captureItem)
        captureStatusMenuItem = captureItem
        menu.addItem(menuItem("打开编辑器", action: #selector(showEditor), key: "e", modifiers: [.command]))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出 CaptureMark", action: #selector(terminate), key: "q", modifiers: [.command]))
        item.menu = menu
        statusItem = item
    }

    private func registerGlobalCaptureShortcut() {
        let status = globalHotKey.registerCaptureShortcut { [weak self] in
            self?.beginCapture()
        }
        if status == noErr {
            captureStatusMenuItem?.title = "框选截图（⌘⇧2）"
            statusItem?.button?.toolTip = "CaptureMark · ⌘⇧2 框选截图"
        } else {
            captureStatusMenuItem?.title = "框选截图（⌘⇧2 已被占用）"
            statusItem?.button?.toolTip = "CaptureMark · 全局快捷键冲突"
        }
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(
            title: "关于 CaptureMark",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApp
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("退出 CaptureMark", action: #selector(terminate), key: "q", modifiers: [.command]))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(menuItem("框选截图", action: #selector(beginCapture), key: "2", modifiers: [.command, .shift]))
        fileMenu.addItem(menuItem("导出 PNG…", action: #selector(exportPNG), key: "s", modifiers: [.command, .shift]))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(menuItem("撤销", action: #selector(undo), key: "z", modifiers: [.command]))
        editMenu.addItem(menuItem("重做", action: #selector(redo), key: "z", modifiers: [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(menuItem("复制", action: #selector(copyResult), key: "c", modifiers: [.command]))
        editMenu.addItem(menuItem("删除标注", action: #selector(deleteSelection), key: "\u{8}", modifiers: []))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func menuItem(
        _ title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
