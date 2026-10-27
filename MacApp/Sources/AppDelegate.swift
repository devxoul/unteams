import AppKit
import UserNotifications

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var windowController: TeamsWindowController?
  private let notifier = Notifier()

  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = MainMenu.make()
    let controller = TeamsWindowController(notifier: notifier)
    windowController = controller
    notifier.onClick = { [weak controller] id in controller?.handleNotificationClick(id: id) }
    notifier.requestAuthorization()
    controller.showWindow(nil)
  }

  // Clicking the Dock icon brings back the window that closing only hid.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    windowController?.showWindow(nil)
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  @objc func reloadTeams(_ sender: Any?) { windowController?.reload() }
}
