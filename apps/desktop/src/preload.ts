import { contextBridge, ipcRenderer, webFrame } from "electron";

contextBridge.exposeInMainWorld("unteams", {
  badge: (count: number) => ipcRenderer.send("badge", count),
  show: () => ipcRenderer.send("show"),
  zoom: () => ipcRenderer.send("zoom"),
  dragStart: (x: number, y: number) => ipcRenderer.send("drag-start", x, y),
  dragMove: (x: number, y: number) => ipcRenderer.send("drag-move", x, y),
});

// Runs in the page's own world, where Teams can see it. Chromium already shows web notifications natively; this
// only makes a click bring back the hidden window, and routes the Badging API to the Dock.
function pageScript(): void {
  type Bridge = {
    badge(count: number): void;
    show(): void;
    zoom(): void;
    dragStart(x: number, y: number): void;
    dragMove(x: number, y: number): void;
  };
  const maybeBridge = (window as unknown as { unteams?: Bridge }).unteams;
  if (!maybeBridge) return;
  const bridge: Bridge = maybeBridge;

  const Native = window.Notification;
  if (Native) {
    window.Notification = class extends Native {
      constructor(title: string, options?: NotificationOptions) {
        super(title, options);
        this.addEventListener("click", () => bridge.show());
      }
    };
  }
  // setAppBadge() without a count means "something is unread"; the app shows a dot for -1.
  navigator.setAppBadge = (count?: number) => {
    bridge.badge(count === undefined ? -1 : Number(count));
    return Promise.resolve();
  };
  navigator.clearAppBadge = () => {
    bridge.badge(0);
    return Promise.resolve();
  };

  // Pads Teams' top bar so the window buttons don't cover it, and makes presses on the bar's empty space drag the
  // window (double-click zooms). The bar is found by shape because Teams' class names are generated. The drag is
  // driven from pointer events instead of -webkit-app-region, which swallows clicks on Teams' div-based controls.
  if (window.opener || window.top !== window || !location.hostname.endsWith("cloud.microsoft")) return;
  const inset = 76;
  const barHeight = 48;
  const interactive =
    "a, button, input, textarea, select, [role=button], [role=link], [role=menuitem], [role=tab], [role=combobox], [role=search], [role=searchbox], [contenteditable], [tabindex]";
  const style = document.createElement("style");
  style.textContent = `[data-unteams-bar]{padding-left:${inset}px!important;box-sizing:border-box!important}`;
  let bar: HTMLElement | null = null;
  let appliedColor: string | null = null;
  let ticks = 0;

  const findBar = (): HTMLElement | null => {
    for (
      let el = document.elementFromPoint(inset / 2, barHeight / 2);
      el && el !== document.body;
      el = el.parentElement
    ) {
      const rect = el.getBoundingClientRect();
      if (rect.top <= 0 && rect.width >= innerWidth - 2 && rect.height >= 30 && rect.height <= 80)
        return el as HTMLElement;
    }
    return null;
  };

  // Teams paints the bar color on an inner element, so the padding takes the first opaque color under the bar's
  // content, starting above any control under the probe point so a hovered button's highlight isn't copied.
  const barColor = (): string | null => {
    let start = document.elementFromPoint(inset + 8, barHeight / 2);
    const control = start?.closest(interactive);
    if (control) start = control.parentElement;
    for (let el = start; el && el !== bar; el = el.parentElement) {
      const color = getComputedStyle(el).backgroundColor;
      if (color && color !== "transparent" && !/rgba\(.*,\s*0\)$/.test(color)) return color;
    }
    return null;
  };

  // Probing layout restyles an otherwise idle page, so the color is re-read only every few seconds or when something
  // that can change it happens, and written only when it changed.
  const update = (force = false): void => {
    if (document.hidden) return;
    if (!bar?.isConnected) {
      bar = findBar();
      if (!bar) return;
      if (!style.isConnected) document.head.append(style);
      bar.setAttribute("data-unteams-bar", "");
      appliedColor = null;
      force = true;
    }
    if (!force && ++ticks % 5 !== 0) return;
    const color = barColor();
    if (!color || color === appliedColor) return;
    bar.style.setProperty("background-color", color, "important");
    appliedColor = color;
  };
  setInterval(update, 1000);
  const refresh = (): void => update(true);
  document.addEventListener("visibilitychange", refresh);
  window.addEventListener("focus", refresh);
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", refresh);

  const onEmptyBar = (event: MouseEvent): boolean => {
    const target = event.target as Element | null;
    // Teams' search box is a styled div with no interactive role; its pointer or text cursor still marks it.
    if (!target || target.closest(interactive) || getComputedStyle(target).cursor !== "auto") return false;
    return event.button === 0 && event.clientY < barHeight;
  };
  window.addEventListener(
    "pointerdown",
    (event) => {
      if (!onEmptyBar(event)) return;
      if (event.detail === 2) return bridge.zoom();
      const target = event.target as HTMLElement;
      target.setPointerCapture(event.pointerId);
      bridge.dragStart(event.screenX, event.screenY);
      const move = (e: PointerEvent): void => bridge.dragMove(e.screenX, e.screenY);
      const end = (): void => {
        target.removeEventListener("pointermove", move);
        target.removeEventListener("pointerup", end);
        target.removeEventListener("pointercancel", end);
      };
      target.addEventListener("pointermove", move);
      target.addEventListener("pointerup", end);
      target.addEventListener("pointercancel", end);
    },
    true,
  );
}

void webFrame.executeJavaScript(`(${pageScript.toString()})()`);
