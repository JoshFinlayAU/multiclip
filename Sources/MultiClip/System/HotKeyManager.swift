import Foundation
import Carbon.HIToolbox
import AppKit

/// Carbon modifier flags, kept in our own type so Preferences doesn't depend on
/// Carbon. Maps to the Carbon `cmdKey`/`optionKey`/etc. masks.
struct HotKeyModifiers: OptionSet {
    let rawValue: UInt32
    static let command = HotKeyModifiers(rawValue: UInt32(cmdKey))
    static let option  = HotKeyModifiers(rawValue: UInt32(optionKey))
    static let control = HotKeyModifiers(rawValue: UInt32(controlKey))
    static let shift   = HotKeyModifiers(rawValue: UInt32(shiftKey))
}

/// Registers a single global hot key using the Carbon Event Manager, which works
/// for menu-bar (accessory) apps without Accessibility permission.
final class HotKeyManager {
    var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x4D4C4350 // 'MLCP'

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        guard keyCode != 0 else { return }

        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            NSLog("MultiClip: failed to register hot key (status \(status))")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyCallback,
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
    }

    fileprivate func handlePress() {
        DispatchQueue.main.async { [weak self] in self?.onPressed?() }
    }

    deinit {
        unregister()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }
}

/// C callback bridged back to the owning HotKeyManager instance.
private func hotKeyCallback(_ nextHandler: EventHandlerCallRef?,
                            _ event: EventRef?,
                            _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData = userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handlePress()
    return noErr
}
