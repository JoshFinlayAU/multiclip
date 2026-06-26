import Foundation
import AppKit
import CoreGraphics

/// Synthesizes a Command-V keystroke into the frontmost application.
/// Requires Accessibility permission (System Settings ▸ Privacy ▸ Accessibility).
enum Paster {
    private static let vKeyCode: CGKeyCode = 9 // ANSI 'v'

    /// Whether the process is currently trusted for Accessibility.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility access (shows the system dialog
    /// once and reveals the app in System Settings).
    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Post Cmd+V. Best-effort; silently no-ops if event creation fails.
    static func pasteIntoFrontmostApp() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
