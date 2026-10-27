# Unteams

A personal Microsoft Teams wrapper for macOS and iOS. It loads [Teams on the web](https://teams.cloud.microsoft), which doesn't require the device registration that the official enterprise apps enforce, and adds what a browser tab lacks.

## Features

- **Mac**: a Dock app with native notifications (click to jump to the conversation), an unread badge on the Dock icon, and a window that hides on close so Teams keeps running.
- **iOS**: the Teams web app full screen, signed in once and kept that way.
- Both: links to other sites open in the default browser; sign-in popups, camera, and microphone work.

## How it works

WKWebView has no Web Notification or Badging API, so a user script replaces `Notification`, `ServiceWorkerRegistration.showNotification`, and `navigator.setAppBadge` with messages to the app. When the page doesn't use the Badging API, the badge comes from the unread count in the page title (`(3) Chat | Microsoft Teams`).

## Build

Requires Xcode 26 and [Tuist](https://tuist.dev) (`mise install`).

```sh
tuist generate  # creates Unteams.xcworkspace
```

Set your own `teamID` (and optionally `bundleIDPrefix`) in [`Project.swift`](Project.swift) first.

| Scheme | Product |
|---|---|
| `UnteamsMac` | Mac app |
| `UnteamsiOS` | iPhone and iPad app |
