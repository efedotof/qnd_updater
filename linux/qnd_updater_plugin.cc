#include "include/qnd_updater/qnd_updater_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>
#include <string>

#include "qnd_updater_plugin_private.h"

#define QND_UPDATER_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), qnd_updater_plugin_get_type(), \
                              QndUpdaterPlugin))

struct _QndUpdaterPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(QndUpdaterPlugin, qnd_updater_plugin, g_object_get_type())


static std::string read_exe_path() {
  char buf[4096];
  ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
  if (n <= 0) return "";
  buf[n] = '\0';
  return std::string(buf);
}

static std::string exe_dir() {
  const std::string exe = read_exe_path();
  if (exe.empty()) return "";
  const auto pos = exe.find_last_of('/');
  if (pos == std::string::npos) return "";
  return exe.substr(0, pos);
}

static std::string read_version_file() {
  const std::string dir = exe_dir();
  if (dir.empty()) return "";
  const std::string path = dir + "/version";
  FILE* f = fopen(path.c_str(), "r");
  if (!f) return "";
  char buf[256] = {0};
  if (!fgets(buf, sizeof(buf), f)) {
    fclose(f);
    return "";
  }
  fclose(f);
  std::string v(buf);
  while (!v.empty() &&
         (v.back() == '\n' || v.back() == '\r' || v.back() == ' ')) {
    v.pop_back();
  }
  return v;
}

static std::string shell_quote(const std::string& s) {
  std::string out = "'";
  for (char c : s) {
    if (c == '\'') {
      out += "'\\''";
    } else {
      out += c;
    }
  }
  out += "'";
  return out;
}


FlMethodResponse* get_platform_version() {
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar* version = g_strdup_printf("Linux %s", uname_data.release);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

FlMethodResponse* get_app_version() {
  const std::string v = read_version_file();
  g_autoptr(FlValue) result = fl_value_new_string(v.c_str());
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* apply_update(const gchar* staging_dir) {
  const std::string exe = read_exe_path();
  if (exe.empty()) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "IO", "cannot resolve /proc/self/exe", nullptr));
  }
  const std::string install_dir = exe_dir();
  if (install_dir.empty()) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "IO", "cannot determine install directory", nullptr));
  }

  const pid_t pid = getpid();
  const std::string script_path =
      "/tmp/qnd_updater_apply_" + std::to_string(pid) + ".sh";

  const std::string body =
      "#!/bin/bash\n"
      "set -e\n"
      "PID=" + std::to_string(pid) + "\n"
      "STAGING=" + shell_quote(staging_dir) + "\n"
      "INSTALL=" + shell_quote(install_dir) + "\n"
      "EXE=" + shell_quote(exe) + "\n"
      "while kill -0 \"$PID\" 2>/dev/null; do sleep 0.3; done\n"
      "cp -r \"$STAGING\"/. \"$INSTALL\"/\n"
      "chmod +x \"$EXE\" 2>/dev/null || true\n"
      "nohup \"$EXE\" >/dev/null 2>&1 &\n"
      "rm -- \"$0\"\n";

  {
    FILE* f = fopen(script_path.c_str(), "w");
    if (!f) {
      return FL_METHOD_RESPONSE(fl_method_error_response_new(
          "IO", "cannot write helper script", nullptr));
    }
    fwrite(body.c_str(), 1, body.size(), f);
    fclose(f);
  }
  chmod(script_path.c_str(), 0755);

  const pid_t child = fork();
  if (child < 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "SPAWN", "fork failed", nullptr));
  }
  if (child == 0) {
    setsid();
    execl("/bin/bash", "bash", script_path.c_str(), (char*)nullptr);
    _exit(127);
  }

  g_autoptr(FlValue) ok = fl_value_new_bool(TRUE);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(ok));
}



static void qnd_updater_plugin_handle_method_call(
    QndUpdaterPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "getPlatformVersion") == 0) {
    response = get_platform_version();
  } else if (strcmp(method, "getAppVersion") == 0) {
    response = get_app_version();
  } else if (strcmp(method, "applyUpdate") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "BAD_ARGS", "expected map", nullptr));
    } else {
      FlValue* staging = fl_value_lookup_string(args, "stagingDir");
      if (staging == nullptr ||
          fl_value_get_type(staging) != FL_VALUE_TYPE_STRING) {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "BAD_ARGS", "stagingDir missing", nullptr));
      } else {
        response = apply_update(fl_value_get_string(staging));
      }
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}



static void qnd_updater_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(qnd_updater_plugin_parent_class)->dispose(object);
}

static void qnd_updater_plugin_class_init(QndUpdaterPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = qnd_updater_plugin_dispose;
}

static void qnd_updater_plugin_init(QndUpdaterPlugin* self) {}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  QndUpdaterPlugin* plugin = QND_UPDATER_PLUGIN(user_data);
  qnd_updater_plugin_handle_method_call(plugin, method_call);
}

void qnd_updater_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  QndUpdaterPlugin* plugin = QND_UPDATER_PLUGIN(
      g_object_new(qnd_updater_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "qnd_updater",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}