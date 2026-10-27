import AppKit

enum MainMenu {
  static func make() -> NSMenu {
    let main = NSMenu()
    let name = ProcessInfo.processInfo.processName

    main.addSubmenu(name, [
      item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
      .separator(),
      item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
      item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
      item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
      .separator(),
      item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"),
    ])
    main.addSubmenu("Edit", [
      item("Undo", Selector(("undo:")), "z"),
      item("Redo", Selector(("redo:")), "z", [.command, .shift]),
      .separator(),
      item("Cut", #selector(NSText.cut(_:)), "x"),
      item("Copy", #selector(NSText.copy(_:)), "c"),
      item("Paste", #selector(NSText.paste(_:)), "v"),
      item("Select All", #selector(NSText.selectAll(_:)), "a"),
    ])
    main.addSubmenu("View", [
      item("Reload", #selector(AppDelegate.reloadTeams(_:)), "r"),
      .separator(),
      item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
    ])
    let window = main.addSubmenu("Window", [
      item("Close", #selector(NSWindow.performClose(_:)), "w"),
      item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
      item("Zoom", #selector(NSWindow.performZoom(_:))),
    ])
    NSApp.windowsMenu = window
    return main
  }

  private static func item(
    _ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    return item
  }
}

private extension NSMenu {
  @discardableResult
  func addSubmenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
    let menu = NSMenu(title: title)
    items.forEach(menu.addItem)
    let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    parent.submenu = menu
    addItem(parent)
    return menu
  }
}
