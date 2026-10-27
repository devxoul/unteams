import ProjectDescription

let teamID = "N2C267LBVY"
let bundleIDPrefix = "app.unteams"

// Each configuration gets its own bundle IDs so Debug, Development and Production builds install side by side.
let configurations: [Configuration] = [
  .debug(name: "Debug", settings: ["BUNDLE_ID_PREFIX": "\(bundleIDPrefix).debug", "APP_ICON": "AppIcon-Debug"]),
  .release(name: "Development", settings: ["BUNDLE_ID_PREFIX": "\(bundleIDPrefix).dev", "APP_ICON": "AppIcon-Dev"]),
  .release(name: "Production", settings: ["BUNDLE_ID_PREFIX": .string(bundleIDPrefix), "APP_ICON": "AppIcon"]),
]

// Each configuration picks its icon through APP_ICON, so Debug and Development builds are told apart at a glance.
let appIcons: [ResourceFileElement] = ["Shared/AppIcon.icon", "Shared/AppIcon-Debug.icon", "Shared/AppIcon-Dev.icon"]
let appIcon: SettingsDictionary = ["ASSETCATALOG_COMPILER_APPICON_NAME": "$(APP_ICON)"]

let baseSettings: SettingsDictionary = [
  "DEVELOPMENT_TEAM": .string(teamID),
  "CODE_SIGN_STYLE": "Automatic",
  "SWIFT_VERSION": "5.0",
]

let version: [String: Plist.Value] = [
  "CFBundleShortVersionString": "0.1.0",
  "CFBundleVersion": .string(Environment.buildNumber.getString(default: "1")),
]

let mediaUsage: [String: Plist.Value] = [
  "NSCameraUsageDescription": "Teams uses the camera for video calls.",
  "NSMicrophoneUsageDescription": "Teams uses the microphone for calls.",
]

let project = Project(
  name: "Unteams",
  settings: .settings(base: baseSettings, configurations: configurations, defaultSettings: .recommended),
  targets: [
    .target(
      name: "UnteamsiOS",
      destinations: [.iPhone, .iPad],
      product: .app,
      productName: "Unteams",
      bundleId: "$(BUNDLE_ID_PREFIX).ios",
      deploymentTargets: .iOS("18.0"),
      infoPlist: .extendingDefault(with: version.merging(mediaUsage) { $1 }.merging([
        "CFBundleDisplayName": "Unteams",
        "UILaunchScreen": [:],
        "ITSAppUsesNonExemptEncryption": false,
      ]) { $1 }),
      sources: ["iOS/App/**", "Shared/Sources/**"],
      resources: .resources(appIcons),
      settings: .settings(base: appIcon)
    ),
    .target(
      name: "UnteamsMac",
      destinations: [.mac],
      product: .app,
      productName: "Unteams",
      bundleId: "$(BUNDLE_ID_PREFIX).mac",
      deploymentTargets: .macOS("15.0"),
      infoPlist: .extendingDefault(with: version.merging(mediaUsage) { $1 }.merging([
        "CFBundleDisplayName": "Unteams",
        "LSApplicationCategoryType": "public.app-category.business",
      ]) { $1 }),
      sources: ["MacApp/Sources/**", "Shared/Sources/**"],
      resources: .resources(appIcons),
      entitlements: "MacApp/App.entitlements",
      settings: .settings(base: appIcon.merging([
        "ENABLE_HARDENED_RUNTIME": "YES",
        "CODE_SIGN_IDENTITY[sdk=macosx*]": "Apple Development",
      ]) { $1 })
    ),
  ]
)
