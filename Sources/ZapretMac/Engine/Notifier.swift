import Foundation
import UserNotifications

/// Posts a notification. Asks for permission the first time it is needed.
enum Notifier {
    static func post(title: String, body: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: "zapretmac.stopped", content: content, trigger: nil))
        }
    }
}
