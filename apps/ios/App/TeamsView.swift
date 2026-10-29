import SwiftUI
import WebKit

struct TeamsView: UIViewRepresentable {
  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> WKWebView {
    let webView = WKWebView(frame: .zero, configuration: Teams.makeConfiguration(messageHandler: context.coordinator))
    context.coordinator.configure(webView)
    webView.configuration.userContentController.addUserScript(WKUserScript(source: desktopSpoof, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    webView.load(URLRequest(url: Teams.url))
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {}

  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    func configure(_ webView: WKWebView) {
      webView.navigationDelegate = self
      webView.uiDelegate = self
      // Desktop Safari's user agent; Teams turns away mobile browsers.
      webView.customUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.5.2 Safari/605.1.15"
      #if DEBUG
      webView.isInspectable = true
      #endif
    }

    // The bridge script still posts notifications and badges; the iPhone app doesn't surface them.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}

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
      if let url { UIApplication.shared.open(url) }
      decisionHandler(.cancel)
      if webView.url == nil { webView.findViewController()?.dismiss(animated: true) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    // window.open (sign-in, some Teams flows) gets a sheet sharing the session.
    func webView(
      _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
      for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      let url = navigationAction.request.url
      switch Teams.route(for: url, linkActivated: true) {
      case .app: break
      case .drop: return nil
      case .browser:
        if let url { UIApplication.shared.open(url) }
        return nil
      }
      let popup = WKWebView(frame: .zero, configuration: configuration)
      configure(popup)
      let controller = UIViewController()
      controller.view = popup
      webView.findViewController()?.present(controller, animated: true)
      return popup
    }

    func webViewDidClose(_ webView: WKWebView) { webView.findViewController()?.dismiss(animated: true) }

    func webView(
      _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo,
      type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
      decisionHandler(Teams.isInternal(URL(string: "https://\(origin.host)")) ? .grant : .prompt)
    }
  }
}

/// Microsoft sign-in (Conditional Access, error 53003) blocks a "Mac" that exposes touch and a phone-sized screen, so
/// on sign-in pages only, those signals report what the Mac app does. Teams itself keeps real touch support.
private let desktopSpoof = #"""
(() => {
  if (!/(^|\.)(microsoftonline\.com|live\.com|microsoftazuread-sso\.com)$/.test(location.hostname)) return;
  const get = (target, name, value) => Object.defineProperty(target, name, { get: () => value, configurable: true });
  get(Navigator.prototype, "maxTouchPoints", 0);
  get(Navigator.prototype, "hardwareConcurrency", 8);
  for (const target of [window, Window.prototype, Document.prototype, Element.prototype, HTMLElement.prototype])
    for (const name of ["ontouchstart", "ontouchmove", "ontouchend", "ontouchcancel"]) delete target[name];
  for (const name of ["TouchEvent", "Touch", "TouchList"]) delete window[name];
  get(Screen.prototype, "width", 1512); get(Screen.prototype, "height", 982);
  get(Screen.prototype, "availWidth", 1512); get(Screen.prototype, "availHeight", 856);
  get(window, "devicePixelRatio", 2);
  const desktop = { "pointer: fine": true, "pointer: coarse": false, "pointer: none": false, "hover: hover": true, "hover: none": false };
  const matchMedia = window.matchMedia.bind(window);
  window.matchMedia = (query) => {
    const key = String(query).replace(/[()\s]/g, "").replace("any-", "").replace(":", ": ");
    if (!(key in desktop)) return matchMedia(query);
    return { matches: desktop[key], media: query, onchange: null, addListener() {}, removeListener() {},
      addEventListener() {}, removeEventListener() {}, dispatchEvent() { return false; } };
  };
})();
"""#

private extension UIView {
  func findViewController() -> UIViewController? {
    sequence(first: next) { $0?.next }.lazy.compactMap { $0 as? UIViewController }.first
  }
}
