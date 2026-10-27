import AppKit
import WebKit

final class TeamsWindowController: NSWindowController, NSWindowDelegate {
  private let notifier: Notifier
  private var webView: WKWebView!
  private var popups: [NSWindow] = []
  private var titleObservation: NSKeyValueObservation?
  /// Once the page uses the Badging API, it owns the badge and the title is ignored.
  private var usesBadgingAPI = false

  init(notifier: Notifier) {
    self.notifier = notifier
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false
    )
    window.title = "Unteams"
    window.titlebarAppearsTransparent = true
    window.minSize = NSSize(width: 480, height: 400)
    window.center()
    window.setFrameAutosaveName("Main")
    super.init(window: window)
    window.delegate = self

    let webView = WKWebView(frame: .zero, configuration: Teams.makeConfiguration(messageHandler: self))
    configure(webView)
    window.contentView = webView
    self.webView = webView
    titleObservation = webView.observe(\.title) { [weak self] webView, _ in
      guard let self, !self.usesBadgingAPI else { return }
      self.notifier.setBadge(Teams.unreadCount(fromTitle: webView.title))
    }
    webView.load(URLRequest(url: Teams.url))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func reload() { webView.reload() }

  func handleNotificationClick(id: String) {
    showWindow(nil)
    NSApp.activate()
    webView.evaluateJavaScript("window.__unteamsClick(\(jsString(id)))")
  }

  // Closing hides the window so Teams keeps running and notifying in the background.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard sender === window else { return true }
    sender.orderOut(nil)
    return false
  }

  func windowWillClose(_ notification: Notification) {
    popups.removeAll { $0 === notification.object as? NSWindow }
  }

  private func configure(_ webView: WKWebView) {
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.allowsBackForwardNavigationGestures = false
    #if DEBUG
    webView.isInspectable = true
    #endif
  }

  private func jsString(_ value: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [value])
    return String(data: data, encoding: .utf8)!.dropFirst().dropLast().description
  }
}

extension TeamsWindowController: WKScriptMessageHandler {
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
    switch type {
    case "notify":
      notifier.show(
        id: body["id"] as? String ?? "", title: body["title"] as? String ?? "",
        body: body["body"] as? String ?? "", tag: body["tag"] as? String ?? ""
      )
    case "close":
      notifier.close(id: body["id"] as? String ?? "")
    case "badge":
      usesBadgingAPI = true
      notifier.setBadge((body["count"] as? NSNumber)?.intValue ?? 0)
    default:
      break
    }
  }
}

extension TeamsWindowController: WKNavigationDelegate {
  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    let url = navigationAction.request.url
    switch Teams.route(for: url, linkActivated: navigationAction.navigationType == .linkActivated) {
    case .app: return decisionHandler(.allow)
    case .drop: return decisionHandler(.cancel)
    case .browser: break
    }
    // Links to other sites open in the default browser; a popup that only existed for one closes again.
    if let url { NSWorkspace.shared.open(url) }
    decisionHandler(.cancel)
    if webView !== self.webView, webView.url == nil || webView.url?.absoluteString == "about:blank" {
      webView.window?.close()
    }
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
}

extension TeamsWindowController: WKUIDelegate {
  // Sign-in and some Teams flows use window.open; those get a real window sharing the session.
  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    let url = navigationAction.request.url
    switch Teams.route(for: url, linkActivated: true) {
    case .app: break
    case .drop: return nil
    case .browser:
      if let url { NSWorkspace.shared.open(url) }
      return nil
    }
    let popupView = WKWebView(frame: .zero, configuration: configuration)
    configure(popupView)
    let size = NSSize(width: windowFeatures.width?.doubleValue ?? 520, height: windowFeatures.height?.doubleValue ?? 680)
    let popup = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable],
      backing: .buffered, defer: false
    )
    popup.isReleasedWhenClosed = false
    popup.contentView = popupView
    popup.delegate = self
    popup.center()
    popup.makeKeyAndOrderFront(nil)
    popups.append(popup)
    return popupView
  }

  func webViewDidClose(_ webView: WKWebView) { webView.window?.close() }

  func webView(
    _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo,
    type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void
  ) {
    decisionHandler(Teams.isInternal(URL(string: "https://\(origin.host)")) ? .grant : .prompt)
  }

  func webView(
    _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping ([URL]?) -> Void
  ) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection
    panel.canChooseDirectories = parameters.allowsDirectories
    panel.begin { completionHandler($0 == .OK ? panel.urls : nil) }
  }

  func webView(
    _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping () -> Void
  ) {
    let alert = NSAlert()
    alert.messageText = message
    alert.runModal()
    completionHandler()
  }

  func webView(
    _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping (Bool) -> Void
  ) {
    let alert = NSAlert()
    alert.messageText = message
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    completionHandler(alert.runModal() == .alertFirstButtonReturn)
  }
}
