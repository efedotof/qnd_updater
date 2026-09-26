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
    let pid = ProcessInfo.processInfo.processIdentifier

    let script = """
    #!/bin/bash
    set -e
    PID=\(pid)
    STAGING="\(stagingDir)"
    BUNDLE="\(bundlePath)"

    # ждём выхода процесса
    while kill -0 "$PID" 2>/dev/null; do sleep 0.4; done

    # поверх бандла
    /usr/bin/ditto "$STAGING" "$BUNDLE"

    # снимаем quarantine на всякий
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