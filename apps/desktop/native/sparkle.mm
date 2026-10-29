// Hosts Sparkle in the Electron process, so it can show its update UI and quit the app to install.
#import <Sparkle/Sparkle.h>
#include <node_api.h>

static SPUStandardUpdaterController *controller;

static napi_value Start(napi_env env, napi_callback_info info) {
  if (!controller) {
    controller = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES updaterDelegate:nil userDriverDelegate:nil];
  }
  return nullptr;
}

static napi_value CheckForUpdates(napi_env env, napi_callback_info info) {
  [controller checkForUpdates:nil];
  return nullptr;
}

NAPI_MODULE_INIT() {
  napi_property_descriptor properties[] = {
    {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
    {"checkForUpdates", nullptr, CheckForUpdates, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, 2, properties);
  return exports;
}
