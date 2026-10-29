// Unteams on Chromium: WebKit pins pages to ~30fps in Low Power Mode, which makes Teams sluggish on battery.
import {
  app,
  BrowserWindow,
  clipboard,
  type ContextMenuParams,
  ipcMain,
  Menu,
  type MenuItemConstructorOptions,
  screen,
  session,
  shell,
  type WebContents,
} from "electron";
import fs from "node:fs";
import path from "node:path";

import { badgeLabel, isInternal, route, TEAMS_URL, unreadCount, webLink } from "./teams";

let window: BrowserWindow | undefined;
let quitting = false;
let usesBadgingAPI = false;
let updater: { start(): void; checkForUpdates(): void } | undefined;
let launchLink: string | undefined;

// Running from source keeps its own profile, so it can run next to the packaged app without fighting over the lock.
if (!app.isPackaged) {
  app.setName("Unteams Debug");
  app.setPath("userData", path.join(app.getPath("appData"), "Unteams Debug"));
}
const isDebug = !app.isPackaged;
if (!app.requestSingleInstanceLock()) app.quit();
app.on("second-instance", showWindow);
// Meeting and chat links that browsers and calendars hand to the Teams app open here. Registered before launch
// finishes, so a link that launches the app is caught too.
app.on("open-url", (event, url) => {
  event.preventDefault();
  const link = webLink(url);
  if (!link) return;
  if (!window) {
    launchLink = link;
    return;
  }
  void window.loadURL(link);
  showWindow();
});
// Teams sends unrecognized browsers to its "unsupported browser" page; Electron's user agent names Electron and the app.
app.userAgentFallback = app.userAgentFallback.replace(/ (Electron|[Uu]nteams(Debug)?)\/\S+/g, "");

app.whenReady().then(() => {
  session.defaultSession.setPermissionRequestHandler((contents, permission, callback, details) => {
    if (permission === "notifications") return callback(true);
    callback(isInternal("requestingUrl" in details ? details.requestingUrl : contents.getURL()));
  });
  // Electron rejects getDisplayMedia() without a handler, so Teams couldn't share the screen. macOS 15 and later show
  // the system picker, where the user chooses what to share, instead of calling the handler. Earlier versions have no
  // picker to ask with, so capture is refused rather than handing over a display unasked.
  session.defaultSession.setDisplayMediaRequestHandler((_request, callback) => callback(null), {
    useSystemPicker: true,
  });
  // Sparkle updates the packaged app only; running from source has no release bundle to replace.
  if (!isDebug) {
    updater = require(path.join(process.resourcesPath, "sparkle.node"));
    updater?.start();
  }
  Menu.setApplicationMenu(makeMenu());
  createWindow();
});

// Clicking the Dock icon brings back the window that closing only hid.
app.on("activate", showWindow);
app.on("before-quit", () => {
  quitting = true;
});
app.on("window-all-closed", () => {});
// Electron shows no context menu of its own, so right-clicks in Teams and its popups would do nothing.
app.on("web-contents-created", (_event, contents) => {
  contents.on("context-menu", (_menuEvent, params) => {
    contextMenu(contents, params).popup({ window: BrowserWindow.fromWebContents(contents) ?? undefined });
  });
});

ipcMain.on("badge", (_event, count: number) => {
  usesBadgingAPI = true;
  app.dock?.setBadge(badgeLabel(count));
});
ipcMain.on("show", showWindow);
let dragOrigin: { pointerX: number; pointerY: number; windowX: number; windowY: number } | undefined;
ipcMain.on("drag-start", (_event, pointerX: number, pointerY: number) => {
  if (!window || window.isFullScreen()) return;
  const [windowX = 0, windowY = 0] = window.getPosition();
  dragOrigin = { pointerX, pointerY, windowX, windowY };
});
ipcMain.on("drag-move", (_event, pointerX: number, pointerY: number) => {
  if (!window || !dragOrigin) return;
  const x = dragOrigin.windowX + pointerX - dragOrigin.pointerX;
  const y = dragOrigin.windowY + pointerY - dragOrigin.pointerY;
  window.setPosition(Math.round(x), Math.round(y));
});
ipcMain.on("zoom", () => {
  if (!window) return;
  if (window.isMaximized()) window.unmaximize();
  else window.maximize();
});

function createWindow(): void {
  const created = new BrowserWindow({
    ...loadFrame(),
    minWidth: 480,
    minHeight: 400,
    title: "Unteams",
    titleBarStyle: "hiddenInset",
    show: false,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      // Keeps timers at full speed while the window is hidden, so notifications arrive promptly.
      backgroundThrottling: false,
    },
  });
  window = created;

  created.on("moved", () => saveFrame(created));
  created.on("resized", () => saveFrame(created));

  // Closing hides the window so Teams keeps running and notifying in the background.
  created.on("close", (event) => {
    if (quitting) return;
    event.preventDefault();
    if (!created.isFullScreen()) return created.hide();
    created.once("leave-full-screen", () => created.hide());
    created.setFullScreen(false);
  });

  // Once the page uses the Badging API, it owns the badge and the title is ignored.
  created.on("page-title-updated", (_event, title) => {
    if (!usesBadgingAPI) app.dock?.setBadge(badgeLabel(unreadCount(title)));
  });

  const contents = created.webContents;
  contents.on("will-navigate", (event, url) => {
    const target = route(url);
    if (target === "app") return;
    event.preventDefault();
    if (target === "browser") void shell.openExternal(url);
  });
  // Sign-in and some Teams flows open sized popups; those get a real window sharing the session. Links that would open
  // a tab, like the ones clicked in chats, go to the browser even when they point at Microsoft hosts.
  contents.setWindowOpenHandler(({ url, disposition }) => {
    let target = url === "about:blank" ? "app" : route(url);
    if (target === "app" && disposition !== "new-window" && /^https?:/i.test(url)) target = "browser";
    if (target === "browser") void shell.openExternal(url);
    if (target !== "app") return { action: "deny" };
    return { action: "allow", overrideBrowserWindowOptions: { width: 520, height: 680 } };
  });
  contents.on("did-create-window", (popup) => {
    popup.webContents.on("will-navigate", (event, url) => {
      if (route(url) !== "browser") return;
      event.preventDefault();
      void shell.openExternal(url);
      popup.close();
    });
  });
  // A crashed page reloads, but not twice within a minute, so a page that crashes while loading can't loop forever.
  let lastCrash = 0;
  contents.on("render-process-gone", (_event, details) => {
    if (details.reason === "clean-exit" || Date.now() - lastCrash < 60_000) return;
    lastCrash = Date.now();
    contents.reload();
  });

  created.once("ready-to-show", () => created.show());
  void created.loadURL(launchLink ?? TEAMS_URL);
}

function showWindow(): void {
  window?.show();
  window?.focus();
}

function makeMenu(): Menu {
  return Menu.buildFromTemplate([
    {
      role: "appMenu",
      submenu: [
        { role: "about" },
        ...(updater ? [{ label: "Check for Updates…", click: () => updater?.checkForUpdates() }] : []),
        { type: "separator" },
        { role: "services" },
        { type: "separator" },
        { role: "hide" },
        { role: "hideOthers" },
        { role: "unhide" },
        { type: "separator" },
        { role: "quit" },
      ],
    },
    { role: "editMenu" },
    {
      label: "View",
      submenu: [
        { label: "Reload", accelerator: "CmdOrCtrl+R", click: () => window?.webContents.reload() },
        ...(isDebug ? [{ role: "toggleDevTools" } as const] : []),
        { type: "separator" },
        { role: "resetZoom" },
        { role: "zoomIn" },
        // zoomIn's Cmd+Plus needs Shift on most layouts; browsers also zoom in on Cmd+=.
        { role: "zoomIn", accelerator: "CmdOrCtrl+=", visible: false },
        { role: "zoomOut" },
        { type: "separator" },
        { role: "togglefullscreen" },
      ],
    },
    { role: "windowMenu" },
  ]);
}

function contextMenu(contents: WebContents, params: ContextMenuParams): Menu {
  const { editFlags, isEditable, linkURL, misspelledWord } = params;
  const groups: MenuItemConstructorOptions[][] = [
    [
      ...params.dictionarySuggestions.map((word) => ({ label: word, click: () => contents.replaceMisspelling(word) })),
      ...(misspelledWord
        ? [
            {
              label: "Learn Spelling",
              click: () => contents.session.addWordToSpellCheckerDictionary(misspelledWord),
            },
          ]
        : []),
    ],
    linkURL && route(linkURL) !== "drop"
      ? [
          { label: "Open Link in Browser", click: () => void shell.openExternal(linkURL) },
          { label: "Copy Link", click: () => clipboard.writeText(linkURL) },
        ]
      : [],
    params.mediaType === "image"
      ? [{ label: "Copy Image", click: () => contents.copyImageAt(params.x, params.y) }]
      : [],
    isEditable
      ? [
          { role: "cut", enabled: editFlags.canCut },
          { role: "copy", enabled: editFlags.canCopy },
          { role: "paste", enabled: editFlags.canPaste },
          { role: "selectAll", enabled: editFlags.canSelectAll },
        ]
      : editFlags.canCopy
        ? [{ role: "copy" }]
        : [],
  ];
  const items = groups
    .filter((group) => group.length > 0)
    .flatMap((group, index) => (index > 0 ? [{ type: "separator" } as const, ...group] : group));
  return Menu.buildFromTemplate(items);
}

type Frame = { x?: number; y?: number; width: number; height: number };

const frameFile = (): string => path.join(app.getPath("userData"), "window.json");

function loadFrame(): Frame {
  try {
    const frame = JSON.parse(fs.readFileSync(frameFile(), "utf8")) as Required<Frame>;
    const onScreen = screen.getAllDisplays().some(({ workArea: area }) => {
      return (
        frame.x < area.x + area.width &&
        frame.x + frame.width > area.x &&
        frame.y < area.y + area.height &&
        frame.y + frame.height > area.y
      );
    });
    return onScreen ? frame : { width: frame.width, height: frame.height };
  } catch {
    return { width: 1200, height: 800 };
  }
}

function saveFrame(target: BrowserWindow): void {
  if (target.isMinimized() || target.isFullScreen()) return;
  fs.writeFileSync(frameFile(), JSON.stringify(target.getBounds()));
}
