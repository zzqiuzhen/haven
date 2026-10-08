import Flutter
import UIKit

/// 备用 App 图标切换（MethodChannel: haven/appicon）
enum AppIconPlugin {
  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "AppIconPlugin") else { return }
    let channel = FlutterMethodChannel(name: "haven/appicon", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getIcon":
        result(UIApplication.shared.alternateIconName ?? "")
      case "setIcon":
        let name = call.arguments as? String
        let target: String? = (name?.isEmpty ?? true) ? nil : name
        guard UIApplication.shared.supportsAlternateIcons else {
          result(FlutterError(code: "unsupported", message: "当前设备不支持更换图标", details: nil))
          return
        }
        if UIApplication.shared.alternateIconName == target {
          result(true)
          return
        }
        DispatchQueue.main.async {
          UIApplication.shared.setAlternateIconName(target) { error in
            if let error = error {
              result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
            } else {
              result(true)
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
