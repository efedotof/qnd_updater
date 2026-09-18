#include "include/qnd_updater/qnd_updater_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "qnd_updater_plugin.h"

void QndUpdaterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  qnd_updater::QndUpdaterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
