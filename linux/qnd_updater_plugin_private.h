#ifndef FLUTTER_PLUGIN_QND_UPDATER_PLUGIN_PRIVATE_H_
#define FLUTTER_PLUGIN_QND_UPDATER_PLUGIN_PRIVATE_H_

#include <flutter_linux/flutter_linux.h>

#include "include/qnd_updater/qnd_updater_plugin.h"

// Exposed for unit tests only.
FlMethodResponse* get_platform_version();
FlMethodResponse* get_app_version();

#endif  // FLUTTER_PLUGIN_QND_UPDATER_PLUGIN_PRIVATE_H_