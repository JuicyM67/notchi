import Carbon.HIToolbox

/// Global snabbtangent med tryck/släpp (för tryck-och-håll-för-att-prata).
/// Standard: ⌃⌥ Mellanslag.
final class Hotkey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    init(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(controlKey | optionKey)) {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            let me = Unmanaged<Hotkey>.fromOpaque(userData).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) { me.onPress?() } else { me.onRelease?() }
            return noErr
        }, 2, &types, selfPtr, &handler)

        let id = EventHotKeyID(signature: OSType(0x4E544348), id: 1) // 'NTCH'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
