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

  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    private var downloads: [ObjectIdentifier: URL] = [:]
    // Finished files wait here until nothing else is being presented or dismissed, then get one share sheet each.
    private var finishedFiles: [URL] = []
    private var isDismissingPopup = false
    private var isSharing = false

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
      case .app: return decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
      case .drop: return decisionHandler(.cancel)
      case .browser: break
      }
      if let url { UIApplication.shared.open(url) }
      decisionHandler(.cancel)
      if webView.url == nil { webView.findViewController()?.dismiss(animated: true) }
    }

    // Files Teams serves as attachments, or that WebKit can't show, are downloaded and offered in a share sheet.
    func webView(
      _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
      decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
      let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
      let isAttachment = disposition?.lowercased().hasPrefix("attachment") ?? false
      decisionHandler(isAttachment || !navigationResponse.canShowMIMEType ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
      startDownload(download, in: webView)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
      startDownload(download, in: webView)
    }

    private func startDownload(_ download: WKDownload, in webView: WKWebView) {
      download.delegate = self
      // A popup opened with window.open only to start a download is left blank, whether it never loaded anything or
      // still shows its initial about:blank document. webView.url already names the download here, so the committed
      // page is read from the back-forward list.
      let shownURL = webView.backForwardList.currentItem?.url
      guard let popup = webView.findViewController(), popup.presentingViewController != nil,
        shownURL == nil || shownURL?.absoluteString == "about:blank"
      else { return }
      isDismissingPopup = true
      popup.dismiss(animated: true) { [weak self] in
        self?.isDismissingPopup = false
        self?.shareNextFile()
      }
    }

    func download(
      _ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
      completionHandler: @escaping (URL?) -> Void
    ) {
      // Each download gets its own folder, so the file keeps its suggested name.
      let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
      do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      } catch {
        return completionHandler(nil)
      }
      let destination = folder.appending(path: suggestedFilename)
      downloads[ObjectIdentifier(download)] = destination
      completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
      guard let file = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
      finishedFiles.append(file)
      shareNextFile()
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
      guard let file = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
      try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    private func shareNextFile() {
      guard !isDismissingPopup, !isSharing, !finishedFiles.isEmpty,
        let presenter = UIApplication.shared.topViewController
      else { return }
      // A controller mid-transition (a Teams popup sliding in, say) can't present yet; try again once it settles.
      if let transition = presenter.transitionCoordinator {
        transition.animate(alongsideTransition: nil) { [weak self] _ in self?.shareNextFile() }
        return
      }
      let file = finishedFiles.removeFirst()
      let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
      sheet.popoverPresentationController?.sourceView = presenter.view
      sheet.popoverPresentationController?.sourceRect = CGRect(
        x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
      // Called once the sheet is done, whether the file was shared or not; the file is only needed until then.
      sheet.completionWithItemsHandler = { [weak self] _, _, _, _ in
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        self?.isSharing = false
        self?.shareNextFile()
      }
      isSharing = true
      presenter.present(sheet, animated: true)
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

private extension UIApplication {
  var topViewController: UIViewController? {
    let window = connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    return sequence(first: window?.rootViewController) { $0?.presentedViewController }.compactMap { $0 }.last
  }
}

private extension UIView {
  func findViewController() -> UIViewController? {
    sequence(first: next) { $0?.next }.lazy.compactMap { $0 as? UIViewController }.first
  }
}
