import Foundation
import UserNotifications

/// Thin wrapper over UNUserNotificationCenter for the "file transfer complete"
/// notices. Plain clipboard syncs intentionally stay silent.
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                NSLog("MultiClip: notification auth error: \(error)")
            } else {
                NSLog("MultiClip: notifications granted=\(granted)")
            }
        }
    }

    static func fileTransferComplete(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("MultiClip: failed to post notification: \(error)")
            }
        }
    }
}
