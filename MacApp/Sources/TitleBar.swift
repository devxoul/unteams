import AppKit
import WebKit

/// Keeps the mouse-down that started a drag in Teams' top bar, so the window can be dragged once the page reports
/// that the press landed on empty space rather than on a control.
final class TeamsWebView: WKWebView {
  private(set) var lastMouseDown: NSEvent?

  override func mouseDown(with event: NSEvent) {
    lastMouseDown = event
    super.mouseDown(with: event)
  }
}

enum TitleBar {
  /// Pads Teams' top bar so the window buttons don't cover its controls, and reports presses on the bar's empty
  /// space as window drags (double-click zooms). The bar is found by shape (full width, at the top, bar height)
  /// because Teams' class names are generated and change between releases.
  static let script = #"""
  (() => {
    if (window.opener) return;
    const inset = 76;
    const barHeight = 48;
    const post = (message) => window.webkit.messageHandlers.unteams.postMessage(message);
    let bar = null;

    const findBar = () => {
      for (let el = document.elementFromPoint(inset / 2, barHeight / 2); el && el !== document.body; el = el.parentElement) {
        const rect = el.getBoundingClientRect();
        if (rect.top <= 0 && rect.width >= window.innerWidth - 2 && rect.height >= 30 && rect.height <= 80) return el;
      }
      return null;
    };

    // Teams paints the bar color on an inner element, so the padding takes the first opaque color under the bar's
    // content. Re-read every tick so it follows theme switches.
    const barColor = () => {
      for (let el = document.elementFromPoint(inset + 8, barHeight / 2); el && el !== bar.parentElement; el = el.parentElement) {
        const color = getComputedStyle(el).backgroundColor;
        if (color && color !== "transparent" && !/rgba\(.*,\s*0\)$/.test(color)) return color;
      }
      return null;
    };

    const update = () => {
      if (!bar || !bar.isConnected) {
        bar = findBar();
        if (!bar) return;
        bar.style.setProperty("padding-left", inset + "px", "important");
        bar.style.setProperty("box-sizing", "border-box", "important");
      }
      const color = barColor();
      if (color) bar.style.setProperty("background-color", color, "important");
    };
    // A timer rather than a MutationObserver: Teams mutates the DOM constantly while it boots, and probing layout
    // on every mutation stalls it on the splash screen.
    setInterval(update, 1000);

    const interactive = "a, button, input, textarea, select, [role=button], [role=link], [role=menuitem], [role=tab], [role=combobox], [role=search], [contenteditable], [tabindex]";
    window.addEventListener("mousedown", (event) => {
      if (event.button !== 0 || event.clientY >= barHeight || event.target.closest(interactive)) return;
      post({ type: event.detail === 2 ? "zoom" : "drag" });
    }, true);
  })();
  """#
}
