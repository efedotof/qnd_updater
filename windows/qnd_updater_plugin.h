#ifndef FLUTTER_PLUGIN_QND_UPDATER_PLUGIN_H_
#define FLUTTER_PLUGIN_QND_UPDATER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <string>

namespace qnd_updater {

class QndUpdaterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  QndUpdaterPlugin();
  virtual ~QndUpdaterPlugin();

  QndUpdaterPlugin(const QndUpdaterPlugin&) = delete;
  QndUpdaterPlugin& operator=(const QndUpdaterPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  static std::string GetAppVersionString();
};

}  

#endif  // FLUTTER_PLUGIN_QND_UPDATER_PLUGIN_H_