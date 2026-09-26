//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <qnd_updater/qnd_updater_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) qnd_updater_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "QndUpdaterPlugin");
  qnd_updater_plugin_register_with_registrar(qnd_updater_registrar);
}
