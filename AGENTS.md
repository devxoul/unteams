# unteams

Personal Microsoft Teams web wrapper for macOS and iOS, built with Tuist. Layout follows devxoul/nothering.

## Build

```bash
tuist generate --no-open   # creates Unteams.xcworkspace
```

Schemes: `UnteamsMac`, `UnteamsiOS`. `Shared/Sources` is compiled into both apps.

## Notes

- The web app URL and the list of in-app (Microsoft) domains live in `Shared/Sources/Teams.swift`, along with the bridge script that shims the Notification and Badging APIs.
- iOS intentionally has no notifications: WKWebView is suspended in the background.
- Debug builds set `isInspectable`, so Safari's Web Inspector can attach.
