<p align="center">
  <img src="Shared/AppIcon.icon/Assets/unteams.png" width="128" alt="Unteams icon">
</p>

<h1 align="center">Unteams</h1>

A personal Microsoft Teams wrapper for macOS and iOS. It loads [Teams on the web](https://teams.cloud.microsoft), which doesn't require the device registration that the official enterprise apps enforce, and adds what a browser tab lacks.

## Why

Many organizations only let the official Teams apps in through device management (Intune or Company Portal). Teams on the web works without that, but it's a tab: it gets lost among others, it can't put a badge on the Dock, and its notifications depend on the browser. Unteams turns the web app into a standalone app and changes nothing else.

## Features

### Mac

- A Dock app with its own window and menu bar.
- Native notifications through Notification Center. Clicking one opens the conversation.
- An unread badge on the Dock icon.
- Closing the window only hides it, so Teams keeps running and notifications keep arriving. Click the Dock icon to bring it back.

### iOS and iPadOS

- The Teams web app in full screen, shown as desktop Safari so Teams doesn't turn it away as an unsupported mobile browser.
- You sign in once and stay signed in.
- No notifications: iOS suspends WKWebView in the background, so the page can't receive them.

### Both

- Teams and Microsoft sign-in pages, including your company's own SSO host, stay in the app.
- Links to other sites, `mailto:`, and `tel:` open in the default browser or app.
- `msteams:` links, which would hand off to the desktop client, are dropped.
- Sign-in popups, camera, and microphone work, so calls work too.

## How it works

Everything Teams-specific is in [`Shared/Sources/Teams.swift`](Shared/Sources/Teams.swift).

- **Notifications and badge.** WKWebView has no Web Notification or Badging API, so a user script injected at document start replaces `Notification`, `ServiceWorkerRegistration.showNotification`, and `navigator.setAppBadge` with messages to the app. When the page doesn't use the Badging API, the badge comes from the unread count in the page title (`(3) Chat | Microsoft Teams`).
- **Staying signed in.** Teams renews tokens in a hidden `login.microsoftonline.com` iframe. With WebKit's tracking prevention on, that iframe can't see the sign-in cookie, so every renewal fails and Teams asks you to sign in again. Unteams turns tracking prevention off through a private WebKit switch. That's fine for a personal build but rules out the App Store.
- **Browser check.** Teams only supports browsers it recognizes, so the user agent includes a Safari version token.
- **Routing.** A list of Microsoft domains decides which URLs stay in the app. Everything else the user clicks opens outside it.

## Requirements

- macOS 15 or later (Mac app), iOS 18 or later (iPhone and iPad app)
- Xcode 26
- [Tuist](https://tuist.dev)
- An Apple Developer team for code signing

## Build

1. Set your own `teamID` (and optionally `bundleIDPrefix`) in [`Project.swift`](Project.swift).
2. Generate the workspace:

   ```sh
   tuist generate  # creates Unteams.xcworkspace
   ```

3. Open `Unteams.xcworkspace`, pick a scheme, and run.

| Scheme | Product |
|---|---|
| `UnteamsMac` | Mac app |
| `UnteamsiOS` | iPhone and iPad app |

### Configurations

Each configuration has its own bundle ID and icon, so all three can be installed side by side and told apart.

| Configuration | Bundle ID prefix | Icon |
|---|---|---|
| Debug | `<prefix>.debug` | `AppIcon-Debug` |
| Development | `<prefix>.dev` | `AppIcon-Dev` |
| Production | `<prefix>` | `AppIcon` |

Debug builds make the web view inspectable, so Safari's Web Inspector (Develop menu) can attach to it.

## Project layout

```
Project.swift          Tuist project: targets, bundle IDs, signing, configurations
Shared/Sources/        Code compiled into both apps (Teams URL, domains, bridge script)
Shared/AppIcon*.icon   App icons for each configuration
MacApp/Sources/        Mac app: window, menu, title bar, notifications
iOS/App/               iOS app: SwiftUI entry point and web view
```

## Limitations

- It's the Teams web app, so it has the web app's features and nothing more.
- No notifications on iOS (see above).
- Uses private WebKit API, so it isn't meant for the App Store.
- Not affiliated with Microsoft.
