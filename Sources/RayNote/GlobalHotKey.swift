import Carbon

/// Owns the Carbon registration and handler together. Replacements are acquired
/// before the working key is released, so a conflict cannot disable the shortcut.
@MainActor final class GlobalHotKey {
    private static var nextID: UInt32 = 0
    let identifier: EventHotKeyID
    private var registration: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private var isPressed = false
    private(set) var current: GlobalShortcut?

    init(action: @escaping () -> Void) {
        Self.nextID &+= 1
        identifier = EventHotKeyID(signature: 0x524E4F54, id: Self.nextID)
        self.action = action
    }

    deinit {
        if let registration { UnregisterEventHotKey(registration) }
        if let handler { RemoveEventHandler(handler) }
    }

    func replace(with shortcut: GlobalShortcut) -> OSStatus {
        if current == shortcut { return noErr }
        if handler == nil {
            var types = [kEventHotKeyPressed, kEventHotKeyReleased].map {
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32($0))
            }
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                return MainActor.assumeIsolated { owner.handle(event) }
            }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return status }
        }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier,
                                        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &replacement)
        guard status == noErr else { return status }
        if let registration { UnregisterEventHotKey(registration) }
        registration = replacement
        current = shortcut
        isPressed = false
        return noErr
    }

    func handle(_ event: EventRef) -> OSStatus {
        let kind = GetEventKind(event)
        guard current != nil, GetEventClass(event) == OSType(kEventClassKeyboard),
              kind == UInt32(kEventHotKeyPressed) || kind == UInt32(kEventHotKeyReleased) else { return OSStatus(eventNotHandledErr) }
        var received = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &received)
        guard status == noErr, received.signature == identifier.signature, received.id == identifier.id else {
            return OSStatus(eventNotHandledErr)
        }
        if kind == UInt32(kEventHotKeyReleased) { isPressed = false; return noErr }
        // Holding the shortcut must not alternate between showing and hiding.
        if !isPressed { isPressed = true; action() }
        return noErr
    }
}
