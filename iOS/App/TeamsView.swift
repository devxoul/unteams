import SwiftUI
import WebKit

struct TeamsView: UIViewRepresentable {
  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> WKWebView {
    let webView = WKWebView(frame: .zero, configuration: Teams.makeConfiguration(messageHandler: context.coordinator))
    context.coordinator.configure(webView)
    webView.load(URLRequest(url: Teams.url))
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {}

  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    func configure(_ webView: WKWebView) {
      webView.navigationDelegate = self
      webView.uiDelegate = self
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

private extension UIView {
  func findViewController() -> UIViewController? {
    sequence(first: next) { $0?.next }.lazy.compactMap { $0 as? UIViewController }.first
  }
}
