import AppKit
import UserNotifications

/// Shows the page's web notifications as system notifications and routes clicks back to the page.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
  var onClick: ((String) -> Void)?
  private let center = UNUserNotificationCenter.current()

  override init() {
    super.init()
    center.delegate = self
  }

  func requestAuthorization() {
    center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
      if let error { NSLog("Unteams: notification authorization failed: %@", error.localizedDescription) }
    }
  }

  func show(id: String, title: String, body: String, tag: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    content.userInfo = ["id": id]
    if !tag.isEmpty { content.threadIdentifier = tag }
    // A tag replaces the earlier notification with the same tag, like browsers do.
    let identifier = tag.isEmpty ? "unteams.\(id)" : "unteams.tag.\(tag)"
    center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
      if let error { NSLog("Unteams: failed to show notification: %@", error.localizedDescription) }
    }
  }

  func close(id: String) {
    center.getDeliveredNotifications { [center] delivered in
      let ids = delivered.filter { $0.request.content.userInfo["id"] as? String == id }.map(\.request.identifier)
      center.removeDeliveredNotifications(withIdentifiers: ids)
    }
  }

  func setBadge(_ count: Int) {
    NSApp.dockTile.badgeLabel = switch count {
    case 0: nil
    case ..<0: "\u{2022}"
    default: String(count)
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .list])
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let id = response.notification.request.content.userInfo["id"] as? String
    DispatchQueue.main.async { [onClick] in
      if let id { onClick?(id) }
      completionHandler()
    }
  }
}
