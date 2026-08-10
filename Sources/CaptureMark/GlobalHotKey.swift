import AppKit
import Carbon.HIToolbox

enum CaptureShortcutPreset: String, CaseIterable {
    case commandShift6
    case commandShift7
    case commandShift8
    case commandShift9
    case commandOption6
    case controlOption6

    static let defaultPreset: Self = .commandShift6

    var displayName: String {
        switch self {
        case .commandShift6: "⌘⇧6"
        case .commandShift7: "⌘⇧7"
        case .commandShift8: "⌘⇧8"
        case .commandShift9: "⌘⇧9"
        case .commandOption6: "⌘⌥6"
        case .controlOption6: "⌃⌥6"
        }
    }

    var keyEquivalent: String {
        switch self {
        case .commandShift6, .commandOption6, .controlOption6: "6"
        case .commandShift7: "7"
        case .commandShift8: "8"
        case .commandShift9: "9"
        }
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        switch self {
        case .commandShift6, .commandShift7, .commandShift8, .commandShift9:
            [.command, .shift]
        case .commandOption6:
            [.command, .option]
        case .controlOption6:
            [.control, .option]
        }
    }

    fileprivate var carbonKeyCode: UInt32 {
        switch self {
        case .commandShift6, .commandOption6, .controlOption6: UInt32(kVK_ANSI_6)
        case .commandShift7: UInt32(kVK_ANSI_7)
        case .commandShift8: UInt32(kVK_ANSI_8)
        case .commandShift9: UInt32(kVK_ANSI_9)
        }
    }

    fileprivate var carbonModifiers: UInt32 {
        switch self {
        case .commandShift6, .commandShift7, .commandShift8, .commandShift9:
            UInt32(cmdKey | shiftKey)
        case .commandOption6:
            UInt32(cmdKey | optionKey)
        case .controlOption6:
            UInt32(controlKey | optionKey)
        }
    }
}

enum CaptureShortcut {
    private static let defaultsKey = "CaptureShortcutPreset"

    static var current: CaptureShortcutPreset {
        get {
            guard let value = UserDefaults.standard.string(forKey: defaultsKey),
                  let preset = CaptureShortcutPreset(rawValue: value) else {
                return .defaultPreset
            }
            return preset
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}

final class GlobalHotKey {
    private static let signature: OSType = 0x434D4152 // "CMAR"
    private static let identifier: UInt32 = 1

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var action: (() -> Void)?

    @discardableResult
    func registerCaptureShortcut(
        _ shortcut: CaptureShortcutPreset,
        action: @escaping () -> Void
    ) -> OSStatus {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr,
                      identifier.signature == GlobalHotKey.signature,
                      identifier.id == GlobalHotKey.identifier else {
                    return OSStatus(eventNotHandledErr)
                }

                let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    owner.action?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            self.action = nil
            return handlerStatus
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let registrationStatus = RegisterEventHotKey(
            shortcut.carbonKeyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &hotKey
        )
        if registrationStatus != noErr {
            unregister()
        }
        return registrationStatus
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        action = nil
    }

    deinit {
        unregister()
    }
}
