#include "qnd_updater_plugin.h"

#include <windows.h>
#include <winver.h>
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

namespace fs = std::filesystem;

namespace qnd_updater {

void QndUpdaterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "qnd_updater",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<QndUpdaterPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

QndUpdaterPlugin::QndUpdaterPlugin() {}
QndUpdaterPlugin::~QndUpdaterPlugin() {}

std::string QndUpdaterPlugin::GetAppVersionString() {
  wchar_t exe_path[MAX_PATH];
  if (!GetModuleFileNameW(nullptr, exe_path, MAX_PATH)) return "";

  DWORD dummy = 0;
  DWORD size = GetFileVersionInfoSizeW(exe_path, &dummy);
  if (size == 0) return "";

  std::vector<BYTE> data(size);
  if (!GetFileVersionInfoW(exe_path, 0, size, data.data())) return "";

  VS_FIXEDFILEINFO *info = nullptr;
  UINT len = 0;
  if (!VerQueryValueW(data.data(), L"\\",
                      reinterpret_cast<LPVOID *>(&info), &len) ||
      info == nullptr) {
    return "";
  }

  std::ostringstream v;
  v << HIWORD(info->dwFileVersionMS) << "."
    << LOWORD(info->dwFileVersionMS) << "."
    << HIWORD(info->dwFileVersionLS) << "."
    << LOWORD(info->dwFileVersionLS);
  return v.str();
}

static std::wstring WidenUtf8(const std::string &s) {
  if (s.empty()) return L"";
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(),
                              static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      out.data(), n);
  return out;
}

static std::wstring GetExePathW() {
  wchar_t buf[MAX_PATH];
  GetModuleFileNameW(nullptr, buf, MAX_PATH);
  return buf;
}

void QndUpdaterPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {

  const auto &name = method_call.method_name();

  if (name == "getAppVersion") {
    result->Success(flutter::EncodableValue(GetAppVersionString()));
    return;
  }

  if (name == "getPlatformVersion") {
    std::ostringstream s;
    s << "Windows ";
    if (IsWindows10OrGreater()) s << "10+";
    else if (IsWindows8OrGreater()) s << "8";
    else if (IsWindows7OrGreater()) s << "7";
    result->Success(flutter::EncodableValue(s.str()));
    return;
  }

  if (name == "applyUpdate") {
    const auto *args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("BAD_ARGS", "expected map");
      return;
    }
    auto it = args->find(flutter::EncodableValue("stagingDir"));
    if (it == args->end()) {
      result->Error("BAD_ARGS", "stagingDir missing");
      return;
    }
    const auto *sv = std::get_if<std::string>(&it->second);
    if (!sv) {
      result->Error("BAD_ARGS", "stagingDir is not string");
      return;
    }

    std::wstring staging = WidenUtf8(*sv);
    std::replace(staging.begin(), staging.end(), L'/', L'\\');

    const std::wstring exe = GetExePathW();
    const std::wstring install = fs::path(exe).parent_path().wstring();
    const std::wstring exeName = fs::path(exe).filename().wstring();

    wchar_t tmp[MAX_PATH];
    GetTempPathW(MAX_PATH, tmp);
    std::wstring bat = std::wstring(tmp) + L"qnd_updater_apply.bat";

    {
      std::wofstream f(bat, std::ios::binary);
      if (!f.is_open()) {
        result->Error("IO", "cannot write helper .bat");
        return;
      }
      f << L"@echo off\r\n";
      f << L"chcp 65001 >nul\r\n";
      f << L"setlocal\r\n";
      f << L"set TARGET=" << exeName << L"\r\n";
      f << L":wait\r\n";
      f << L"tasklist /FI \"IMAGENAME eq %TARGET%\" 2>NUL | find /I \"%TARGET%\" >NUL\r\n";
      f << L"if not errorlevel 1 (timeout /t 1 /nobreak >nul & goto wait)\r\n";
      f << L"xcopy /E /I /Y /Q \"" << staging << L"\\*\" \"" << install << L"\\\"\r\n";
      f << L"start \"\" \"" << exe << L"\"\r\n";
      f << L"del \"%~f0\"\r\n";
    }

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    std::wstring cmd = L"cmd.exe /c \"" + bat + L"\"";
    BOOL ok = CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE,
                             CREATE_NO_WINDOW | DETACHED_PROCESS, nullptr,
                             nullptr, &si, &pi);
    if (!ok) {
      result->Error("SPAWN", "CreateProcess failed");
      return;
    }
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    result->Success(flutter::EncodableValue(true));
    return;
  }

  result->NotImplemented();
}

}  // namespace qnd_updater