import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut.
///
/// Uses Carbon's `RegisterEventHotKey` rather than an `NSEvent` global monitor
/// on purpose: the Carbon API needs no Accessibility or Input Monitoring
/// permission, so the palette works the moment the app launches instead of
/// after a trip through System Settings.
final class GlobalHotKey {

    struct Combination: Equatable {
        /// Virtual key code, e.g. `kVK_ANSI_K`.
        var keyCode: UInt32
        /// Carbon modifier mask, e.g. `UInt32(cmdKey | optionKey | controlKey)`.
        var modifiers: UInt32
        var display: [String]

        static let `default` = Combination(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(controlKey | optionKey | cmdKey),
            display: ["⌃", "⌥", "⌘", "K"]
        )
    }

    private static var handlerInstalled = false
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1

    private var ref: EventHotKeyRef?
    private let id: UInt32

    init?(_ combination: Combination, action: @escaping () -> Void) {
        Self.installHandlerIfNeeded()

        id = Self.nextID
        Self.nextID += 1
        Self.actions[id] = action

        var hotKeyID = EventHotKeyID(signature: OSType(0x4D50_4144) /* "MPAD" */, id: id)
        var created: EventHotKeyRef?
        let status = RegisterEventHotKey(combination.keyCode,
                                         combination.modifiers,
                                         hotKeyID,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &created)
        guard status == noErr, let created else {
            Self.actions[id] = nil
            return nil
        }
        ref = created
        _ = hotKeyID
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.actions[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &pressed)
            guard status == noErr else { return status }
            DispatchQueue.main.async { GlobalHotKey.actions[pressed.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
