import SwiftUI

/// Backing model for the settings window. Loads current values on init and
/// writes them back (Preferences + Keychain) when `save()` is called.
final class SettingsModel: ObservableObject {
    @Published var deviceName: String
    @Published var sharedKey: String
    @Published var historyLimit: Int
    @Published var fileSizeLimitMB: Int

    @Published var hotKeyEnabled: Bool
    @Published var hotKeyLetter: String
    @Published var modCommand: Bool
    @Published var modOption: Bool
    @Published var modControl: Bool
    @Published var modShift: Bool

    @Published var iconStyle: String

    /// Invoked after a successful save so the app can re-apply settings.
    var onSaved: (() -> Void)?

    init() {
        let p = Preferences.shared
        deviceName = p.deviceName
        sharedKey = KeychainStore.sharedKey() ?? ""
        historyLimit = p.historyLimit
        fileSizeLimitMB = p.fileSizeLimitMB
        hotKeyEnabled = p.hotKeyEnabled
        hotKeyLetter = KeyCodeMap.character(for: p.hotKeyCode).map { String($0).uppercased() } ?? "V"
        let mods = HotKeyModifiers(rawValue: p.hotKeyModifiers)
        modCommand = mods.contains(.command)
        modOption = mods.contains(.option)
        modControl = mods.contains(.control)
        modShift = mods.contains(.shift)
        iconStyle = p.iconStyle
    }

    func save() {
        let p = Preferences.shared
        p.deviceName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        p.historyLimit = historyLimit
        p.fileSizeLimitMB = fileSizeLimitMB
        p.hotKeyEnabled = hotKeyEnabled
        if let ch = hotKeyLetter.lowercased().first, let code = KeyCodeMap.keyCode(for: ch) {
            p.hotKeyCode = code
        }
        var mods: HotKeyModifiers = []
        if modCommand { mods.insert(.command) }
        if modOption { mods.insert(.option) }
        if modControl { mods.insert(.control) }
        if modShift { mods.insert(.shift) }
        p.hotKeyModifiers = mods.rawValue
        p.iconStyle = iconStyle

        KeychainStore.setSharedKey(sharedKey.trimmingCharacters(in: .whitespacesAndNewlines))

        onSaved?()
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Identity & Security") {
                        labeledField("Device name") {
                            TextField("This Mac", text: $model.deviceName)
                                .textFieldStyle(.roundedBorder)
                        }
                        labeledField("Shared key") {
                            SecureField("Required to join other devices", text: $model.sharedKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Text("Devices that share the exact same key can see each other's copies. A wrong or empty key means a device cannot join.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    section("History & Transfer") {
                        labeledField("History length") {
                            Stepper(value: $model.historyLimit, in: 1...50) {
                                Text("\(model.historyLimit) items")
                            }
                        }
                        labeledField("Max item size") {
                            Stepper(value: $model.fileSizeLimitMB, in: 1...1000, step: 5) {
                                Text("\(model.fileSizeLimitMB) MB")
                            }
                        }
                    }

                    section("Paste Hot Key") {
                        Toggle("Enable global hot key", isOn: $model.hotKeyEnabled)
                        HStack(spacing: 12) {
                            Toggle("⌘", isOn: $model.modCommand)
                            Toggle("⌥", isOn: $model.modOption)
                            Toggle("⌃", isOn: $model.modControl)
                            Toggle("⇧", isOn: $model.modShift)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("Key")
                                TextField("V", text: Binding(
                                    get: { model.hotKeyLetter },
                                    set: { model.hotKeyLetter = String($0.uppercased().prefix(1)) }
                                ))
                                .frame(width: 40)
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                        .disabled(!model.hotKeyEnabled)
                        Text("Pastes the most recent item from another device into the frontmost app (needs Accessibility permission).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    section("Menu Bar Icon") {
                        Picker("Style", selection: $model.iconStyle) {
                            Text("Outline").tag("outline")
                            Text("Filled").tag("black")
                            Text("Color").tag("color")
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Spacer()
                Button("Close", action: onClose)
                Button("Save") {
                    model.save()
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 420, height: 540)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).frame(width: 110, alignment: .leading)
            content()
        }
    }
}
