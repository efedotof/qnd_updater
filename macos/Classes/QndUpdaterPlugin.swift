import Cocoa
import FlutterMacOS

public class QndUpdaterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "qnd_updater",
                                       binaryMessenger: registrar.messenger)
    let instance = QndUpdaterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getAppVersion":
      result(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")

    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)

    case "applyUpdate":
      guard let args = call.arguments as? [String: Any],
            let staging = args["stagingDir"] as? String else {
        result(FlutterError(code: "BAD_ARGS",
                            message: "stagingDir missing",
                            details: nil))
        return
      }
      applyUpdate(stagingDir: staging, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func applyUpdate(stagingDir: String, result: @escaping FlutterResult) {
    let bundlePath = Bundle.main.bundlePath
    let bundleName = (bundlePath as NSString).lastPathComponent
    let pid = ProcessInfo.processInfo.processIdentifier


    let script = """
    #!/bin/bash
    set -e
    PID=\(pid)
    STAGING="\(stagingDir)"
    BUNDLE="\(bundlePath)"
    APP_NAME="\(bundleName)"

    # ждём выхода процесса
    while kill -0 "$PID" 2>/dev/null; do sleep 0.4; done

    SRC_APP="$STAGING/$APP_NAME"

    if [ -d "$SRC_APP/Contents" ]; then
      # ZIP содержит <app_name>.app/Contents — копируем содержимое бандла
      /usr/bin/ditto "$SRC_APP/Contents" "$BUNDLE/Contents"
    elif [ -d "$STAGING/Contents" ]; then
      # ZIP содержит Contents прямо в корне
      /usr/bin/ditto "$STAGING/Contents" "$BUNDLE/Contents"
    else
      echo "update archive layout not recognized" >&2
      exit 1
    fi

    # снимаем quarantine
    /usr/bin/xattr -dr com.apple.quarantine "$BUNDLE" 2>/dev/null || true

    # перезапуск
    /usr/bin/open "$BUNDLE"
    /bin/rm -- "$0"
    """

    let scriptPath = NSTemporaryDirectory() + "qnd_updater_apply_\(UUID().uuidString).sh"
    do {
      try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: scriptPath)
    } catch {
      result(FlutterError(code: "IO",
                          message: error.localizedDescription,
                          details: nil))
      return
    }

    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = [scriptPath]
    try? task.run()

    result(true)
  }
}