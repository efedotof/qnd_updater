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
    << HIWORD(info->dwFileVersionLS);
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
    std::wstring log = std::wstring(tmp) + L"qnd_updater_apply.log";

    DeleteFileW(log.c_str());

    {
      std::wofstream f(bat, std::ios::binary | std::ios::trunc);
      if (!f.is_open()) {
        result->Error("IO", "cannot write helper .bat");
        return;
      }

      f << L"@echo off\r\n";
      f << L"chcp 65001 >nul\r\n";
      f << L"setlocal EnableDelayedExpansion\r\n";
      f << L"set LOG=\"" << log << L"\"\r\n";
      f << L"set TARGET=" << exeName << L"\r\n";
      f << L"set STAGING=" << staging << L"\r\n";
      f << L"set INSTALL=" << install << L"\r\n";
      f << L"set EXE=" << exe << L"\r\n";

      f << L"echo [%DATE% %TIME%] === START === > %LOG%\r\n";
      f << L"echo TARGET=%TARGET% >> %LOG%\r\n";
      f << L"echo STAGING=%STAGING% >> %LOG%\r\n";
      f << L"echo INSTALL=%INSTALL% >> %LOG%\r\n";

      f << L"echo [%TIME%] --- Version BEFORE copy --- >> %LOG%\r\n";
      f << L"powershell -NoProfile -Command \"(Get-Item '%EXE%').VersionInfo.FileVersion\" >> %LOG% 2>&1\r\n";

      f << L":wait\r\n";
      f << L"tasklist /FI \"IMAGENAME eq %TARGET%\" 2>NUL | findstr /I /C:\"%TARGET%\" >NUL\r\n";
      f << L"if not errorlevel 1 (\r\n";
      f << L"  timeout /t 1 /nobreak >nul\r\n";
      f << L"  goto wait\r\n";
      f << L")\r\n";
      f << L"echo [%TIME%] Process stopped >> %LOG%\r\n";

      f << L"timeout /t 2 /nobreak >nul\r\n";

      f << L"echo [%TIME%] Starting xcopy... >> %LOG%\r\n";
      f << L"xcopy /E /I /Y /Q \"%STAGING%\\*\" \"%INSTALL%\\\" >> %LOG% 2>&1\r\n";
      f << L"echo [%TIME%] xcopy errorlevel=!errorlevel! >> %LOG%\r\n";

      f << L"echo [%TIME%] --- Version AFTER copy --- >> %LOG%\r\n";
      f << L"powershell -NoProfile -Command \"(Get-Item '%EXE%').VersionInfo.FileVersion\" >> %LOG% 2>&1\r\n";

      f << L"echo [%TIME%] Starting app... >> %LOG%\r\n";
      f << L"cd /d \"%INSTALL%\"\r\n";
      f << L"start \"\" \"%EXE%\"\r\n";
      f << L"echo [%TIME%] start returned !errorlevel! >> %LOG%\r\n";

      f << L"timeout /t 3 /nobreak >nul\r\n";
      f << L"tasklist /FI \"IMAGENAME eq %TARGET%\" 2>NUL | findstr /I /C:\"%TARGET%\" >NUL\r\n";
      f << L"if errorlevel 1 (\r\n";
      f << L"  echo [%TIME%] !!! ERROR: app NOT running after start !!! >> %LOG%\r\n";
      f << L"  echo Возможные причины: >> %LOG%\r\n";
      f << L"  echo   - antivirus/SmartScreen блокирует новый exe >> %LOG%\r\n";
      f << L"  echo   - missing DLL (нужны VC++ Redistributable) >> %LOG%\r\n";
      f << L"  echo   - exe повреждён или несовместим >> %LOG%\r\n";
      f << L") else (\r\n";
      f << L"  echo [%TIME%] OK: app is running >> %LOG%\r\n";
      f << L")\r\n";

      f << L"echo [%TIME%] === END === >> %LOG%\r\n";
      f << L"del \"%~f0\"\r\n";
      f << L"exit /b\r\n";
    }

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;

    PROCESS_INFORMATION pi{};
    std::wstring cmd = L"cmd.exe /c \"" + bat + L"\"";

    BOOL ok = CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE,
                             CREATE_NO_WINDOW, nullptr,
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