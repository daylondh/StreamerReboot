import Cocoa
import FlutterMacOS
import AVFoundation

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let permissionChannel = FlutterMethodChannel(
      name: "church_streamer/media_permissions",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    permissionChannel.setMethodCallHandler { call, result in
      if call.method == "status" {
        result([
          "camera": Self.authorizationName(for: .video),
          "microphone": Self.authorizationName(for: .audio)
        ])
        return
      }
      guard call.method == "request" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let group = DispatchGroup()
      var cameraAllowed = false
      var microphoneAllowed = false

      group.enter()
      AVCaptureDevice.requestAccess(for: .video) { allowed in
        cameraAllowed = allowed
        group.leave()
      }
      group.enter()
      AVCaptureDevice.requestAccess(for: .audio) { allowed in
        microphoneAllowed = allowed
        group.leave()
      }
      group.notify(queue: .main) {
        result([
          "camera": cameraAllowed ? "granted" : "denied",
          "microphone": microphoneAllowed ? "granted" : "denied"
        ])
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    DispatchQueue.main.async { [weak self] in
      self?.toggleFullScreen(nil)
    }
  }

  private static func authorizationName(for mediaType: AVMediaType) -> String {
    switch AVCaptureDevice.authorizationStatus(for: mediaType) {
    case .authorized:
      return "granted"
    case .notDetermined:
      return "notDetermined"
    case .denied, .restricted:
      return "denied"
    @unknown default:
      return "denied"
    }
  }
}
