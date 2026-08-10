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
    private weak var captureMainMenuItem: NSMenuItem?
    private var shortcutMenus: [NSMenu] = []
    private var editorWasVisibleBeforeCapture = false
    private var isCapturing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        configureStatusItem()
        editor.onCaptureRequested = { [weak self] in self?.beginCapture(automaticallyCopies: false) }
        registerGlobalCaptureShortcut()
        editor.showEditor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotKey.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func beginStandardCapture() {
        beginCapture(automaticallyCopies: false)
    }

    @objc private func beginQuickCapture() {
        beginCapture(automaticallyCopies: true)
    }

    private func beginCapture(automaticallyCopies: Bool) {
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
                    if automaticallyCopies {
                        self.editor.copyResult()
                    }
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

        let shortcut = CaptureShortcut.current
        let menu = NSMenu()
        let captureItem = menuItem(
            "快速截图并复制（\(shortcut.displayName)）",
            action: #selector(beginQuickCapture),
            key: shortcut.keyEquivalent,
            modifiers: shortcut.cocoaModifiers
        )
        menu.addItem(captureItem)
        captureStatusMenuItem = captureItem
        menu.addItem(menuItem("打开编辑器", action: #selector(showEditor), key: "e", modifiers: [.command]))
        menu.addItem(shortcutSettingsMenuItem())
        menu.addItem(.separator())
        menu.addItem(menuItem("退出 CaptureMark", action: #selector(terminate), key: "q", modifiers: [.command]))
        item.menu = menu
        statusItem = item
    }

    private func registerGlobalCaptureShortcut() {
        let shortcut = CaptureShortcut.current
        let status = register(shortcut)
        updateShortcutMenu(shortcut, registered: status == noErr)
    }

    private func register(_ shortcut: CaptureShortcutPreset) -> OSStatus {
        globalHotKey.registerCaptureShortcut(shortcut) { [weak self] in
            self?.beginCapture(automaticallyCopies: true)
        }
    }

    @objc private func shortcutMenuItemSelected(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let shortcut = CaptureShortcutPreset(rawValue: rawValue) else { return }
        applyShortcut(shortcut)
    }

    private func applyShortcut(_ shortcut: CaptureShortcutPreset) {
        let previous = CaptureShortcut.current
        let status = register(shortcut)
        guard status == noErr else {
            _ = register(previous)
            updateShortcutMenu(previous, registered: true)
            showShortcutConflict(shortcut)
            return
        }

        CaptureShortcut.current = shortcut
        updateShortcutMenu(shortcut, registered: true)
    }

    private func showShortcutConflict(_ shortcut: CaptureShortcutPreset) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "快捷键 \(shortcut.displayName) 已被占用"
        alert.informativeText = "CaptureMark 已保留原来的快捷键 \(CaptureShortcut.current.displayName)，请选择另一个组合。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func updateShortcutMenu(_ shortcut: CaptureShortcutPreset, registered: Bool) {
        let suffix = registered ? "" : " · 已被占用"
        let title = "快速截图并复制（\(shortcut.displayName)\(suffix)）"
        for item in [captureStatusMenuItem, captureMainMenuItem] {
            item?.title = title
            item?.keyEquivalent = shortcut.keyEquivalent
            item?.keyEquivalentModifierMask = shortcut.cocoaModifiers
        }
        statusItem?.button?.toolTip = registered
            ? "CaptureMark · \(shortcut.displayName) 快速截图并复制"
            : "CaptureMark · 全局快捷键冲突"
        updateShortcutMenuChecks(shortcut)
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
        appMenu.addItem(shortcutSettingsMenuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("退出 CaptureMark", action: #selector(terminate), key: "q", modifiers: [.command]))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        let shortcut = CaptureShortcut.current
        let captureItem = menuItem(
            "快速截图并复制（\(shortcut.displayName)）",
            action: #selector(beginQuickCapture),
            key: shortcut.keyEquivalent,
            modifiers: shortcut.cocoaModifiers
        )
        fileMenu.addItem(captureItem)
        captureMainMenuItem = captureItem
        fileMenu.addItem(menuItem("框选截图并编辑", action: #selector(beginStandardCapture)))
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

    private func shortcutSettingsMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: "截图快捷键", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "截图快捷键")
        for preset in CaptureShortcutPreset.allCases {
            let item = NSMenuItem(
                title: preset.displayName + (preset == .defaultPreset ? "（默认）" : ""),
                action: #selector(shortcutMenuItemSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.rawValue
            item.state = preset == CaptureShortcut.current ? .on : .off
            menu.addItem(item)
        }
        root.submenu = menu
        shortcutMenus.append(menu)
        return root
    }

    private func updateShortcutMenuChecks(_ shortcut: CaptureShortcutPreset) {
        for menu in shortcutMenus {
            for item in menu.items {
                item.state = (item.representedObject as? String) == shortcut.rawValue ? .on : .off
            }
        }
    }
}
