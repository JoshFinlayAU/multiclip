import AppKit

if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
}

if CommandLine.arguments.contains("--integration") {
    IntegrationHarness().run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
