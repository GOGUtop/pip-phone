import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization(completion: @escaping (Bool, String) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                completion(false, error.localizedDescription)
                return
            }
            completion(granted, granted ? "granted" : "denied")
        }
    }

    func currentAuthorization(completion: @escaping (String) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let value: String
            switch settings.authorizationStatus {
            case .authorized: value = "granted"
            case .provisional: value = "provisional"
            case .ephemeral: value = "ephemeral"
            case .denied: value = "denied"
            case .notDetermined: value = "default"
            @unknown default: value = "unknown"
            }
            completion(value)
        }
    }

    func notify(title: String, body: String, completion: ((Bool, String) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional ||
                    settings.authorizationStatus == .ephemeral else {
                completion?(false, "notification-permission-not-granted")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "st-reply-done-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request) { error in
                if let error {
                    completion?(false, error.localizedDescription)
                } else {
                    completion?(true, "sent")
                }
            }
        }
    }
}
