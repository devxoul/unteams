import Foundation
import WebKit

enum Teams {
  static let url = URL(string: "https://teams.cloud.microsoft/")!

  /// Name of the script message handler the bridge script posts to.
  static let messageHandler = "unteams"

  // Hosts Teams and Microsoft sign-in navigate through. Anything else opens in the default browser.
  private static let internalDomains = [
    "cloud.microsoft", "microsoft.com", "microsoftonline.com", "microsoftonline-p.com", "live.com", "office.com",
    "office.net", "office365.com", "sharepoint.com", "skype.com", "msauth.net", "msftauth.net", "msauthimages.net",
    "msftauthimages.net", "windows.net", "microsoftazuread-sso.com", "azure.com", "aka.ms",
  ]

  static func isInternal(_ url: URL?) -> Bool {
    guard let url else { return true }
    let scheme = url.scheme ?? ""
    guard scheme == "https" || scheme == "http" else {
      return scheme == "about" || scheme == "blob" || scheme == "data"
    }
    guard let host = url.host()?.lowercased() else { return false }
    return internalDomains.contains { host == $0 || host.hasSuffix(".\($0)") }
  }

  @MainActor
  static func makeConfiguration(messageHandler handler: WKScriptMessageHandler) -> WKWebViewConfiguration {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    // Teams only supports browsers it recognizes; the Safari token makes WKWebView pass as Safari.
    configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
    configuration.mediaTypesRequiringUserActionForPlayback = []
    #if os(iOS)
    configuration.allowsInlineMediaPlayback = true
    #endif
    let controller = WKUserContentController()
    controller.addUserScript(WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    controller.add(handler, name: messageHandler)
    configuration.userContentController = controller
    return configuration
  }

  /// Reads the unread count Teams puts in the page title, e.g. "(3) Chat | Microsoft Teams".
  static func unreadCount(fromTitle title: String?) -> Int {
    guard let title, let match = title.firstMatch(of: /^\((\d+)\)/) else { return 0 }
    return Int(match.1) ?? 0
  }

  /// Replaces the Web Notification and Badging APIs, which WKWebView doesn't provide, with messages to the app.
  static let bridgeScript = #"""
  (() => {
    const post = (message) => window.webkit.messageHandlers.unteams.postMessage(message);
    const live = new Map();
    let seq = 0;

    class UnteamsNotification extends EventTarget {
      constructor(title, options = {}) {
        super();
        this.title = String(title);
        this.body = String(options.body || "");
        this.tag = String(options.tag || "");
        this.icon = options.icon || "";
        this.data = options.data;
        this.onclick = this.onclose = this.onshow = this.onerror = null;
        this._id = String(++seq);
        live.set(this._id, this);
        post({ type: "notify", id: this._id, title: this.title, body: this.body, tag: this.tag });
        setTimeout(() => this._fire("show"));
      }
      _fire(name) {
        const event = new Event(name, { cancelable: true });
        this.dispatchEvent(event);
        const handler = this["on" + name];
        if (typeof handler === "function") handler.call(this, event);
      }
      close() {
        if (!live.delete(this._id)) return;
        post({ type: "close", id: this._id });
        this._fire("close");
      }
      static get permission() { return "granted"; }
      static requestPermission(callback) {
        if (typeof callback === "function") callback("granted");
        return Promise.resolve("granted");
      }
      static get maxActions() { return 0; }
    }

    window.__unteamsClick = (id) => {
      const notification = live.get(id);
      window.focus();
      if (notification) notification._fire("click");
    };

    Object.defineProperty(window, "Notification", { value: UnteamsNotification, writable: true, configurable: true });

    if (window.ServiceWorkerRegistration) {
      ServiceWorkerRegistration.prototype.showNotification = function (title, options) {
        new UnteamsNotification(title, options);
        return Promise.resolve();
      };
      ServiceWorkerRegistration.prototype.getNotifications = () => Promise.resolve([]);
    }

    if (navigator.permissions && navigator.permissions.query) {
      const query = navigator.permissions.query.bind(navigator.permissions);
      navigator.permissions.query = (descriptor) =>
        descriptor && descriptor.name === "notifications"
          ? Promise.resolve({ name: "notifications", state: "granted", onchange: null,
              addEventListener() {}, removeEventListener() {} })
          : query(descriptor);
    }

    // setAppBadge() without a count means "something is unread"; the app shows a dot for -1.
    navigator.setAppBadge = (count) => { post({ type: "badge", count: count === undefined ? -1 : Number(count) }); return Promise.resolve(); };
    navigator.clearAppBadge = () => { post({ type: "badge", count: 0 }); return Promise.resolve(); };
  })();
  """#
}
