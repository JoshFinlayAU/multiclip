import Foundation
import AppKit

/// Loads the menu-bar icon from the bundled PNGs and prepares it for the status
/// bar (template rendering for the monochrome styles so it adapts to light/dark).
enum IconProvider {
    static func menuBarImage(style: String) -> NSImage? {
        let name: String
        let isTemplate: Bool
        switch style {
        case "black":
            name = "clipboard-black"; isTemplate = true
        case "color":
            name = "clipboard-color"; isTemplate = false
        default:
            name = "clipboard"; isTemplate = true
        }

        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            // Fallback: a system symbol so the app is still usable.
            let fallback = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "MultiClip")
            fallback?.isTemplate = true
            return fallback
        }
        let size = NSSize(width: 18, height: 18)
        let resized = NSImage(size: size)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver,
                   fraction: 1.0)
        resized.unlockFocus()
        resized.isTemplate = isTemplate
        return resized
    }
}
