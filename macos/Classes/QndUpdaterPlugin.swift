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
    LOG=/tmp/qnd_updater_apply_\(pid).log
    exec >> "$LOG" 2>&1
    echo "=== $(date) apply_update pid=$$ ==="
    set -x

    PID=\(pid)
    STAGING="\(stagingDir)"
    BUNDLE="\(bundlePath)"

    echo "=== wait for PID $PID ==="
    for i in $(seq 1 200); do
      if ! kill -0 "$PID" 2>/dev/null; then break; fi
      sleep 0.3
    done
    sleep 1

    SRC_APP=""
    for candidate in "$STAGING"/*.app; do
      if [ -d "$candidate/Contents" ]; then
        SRC_APP="$candidate"
        break
      fi
    done

    if [ -z "$SRC_APP" ] || [ ! -d "$SRC_APP/Contents" ]; then
      echo "no .app in staging"
      ls -la "$STAGING"
      exit 1
    fi

    echo "=== verify staging app signature ==="
    /usr/bin/codesign --verify --verbose=2 "$SRC_APP" 2>&1 | sed "s/^/  sig: /"

    echo "=== copy new bundle ==="
    NEW_BUNDLE="$BUNDLE.new_$$"
    /bin/rm -rf "$NEW_BUNDLE"
    /usr/bin/ditto --rsrc --extattr "$SRC_APP" "$NEW_BUNDLE"

    echo "=== remove quarantine ==="
    /usr/bin/xattr -dr com.apple.quarantine "$NEW_BUNDLE" 2>/dev/null || true

    echo "=== verify new bundle signature ==="
    /usr/bin/codesign --verify --verbose=4 "$NEW_BUNDLE" 2>&1 | sed "s/^/  verify: /"

    echo "=== dump entitlements ==="
    /usr/bin/codesign -d --entitlements - "$NEW_BUNDLE" 2>&1 | sed "s/^/  ent: /"

    echo "=== swap ==="
    /bin/mv "$BUNDLE" "$BUNDLE.old_$$"
    /bin/mv "$NEW_BUNDLE" "$BUNDLE"
    /usr/bin/xattr -dr com.apple.quarantine "$BUNDLE" 2>/dev/null || true

    echo "=== relaunch ==="
    /usr/bin/open "$BUNDLE"
    sleep 2
    /bin/rm -rf "$BUNDLE.old_$$"
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