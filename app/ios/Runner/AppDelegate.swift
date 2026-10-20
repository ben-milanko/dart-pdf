import BackgroundTasks
import Flutter
import GameController
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var ocrChannel: FlutterMethodChannel?
  private var ocrBackgroundTime = UIBackgroundTaskIdentifier.invalid
  private var ocrTask: Any?
  private var ocrCount = 0
  private var ocrCompleted = 0
  private let ocrIdentifier = "dev.milanko.dartpdf.ocr"

  private func endOcr(success: Bool) {
    if #available(iOS 26.0, *) {
      (ocrTask as? BGContinuedProcessingTask)?.setTaskCompleted(success: success)
      ocrTask = nil
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: ocrIdentifier)
    }
    if ocrBackgroundTime != .invalid {
      UIApplication.shared.endBackgroundTask(ocrBackgroundTime)
      ocrBackgroundTime = .invalid
    }
  }

  private func beginOcr(_ args: [String: Any]) {
    endOcr(success: false)
    ocrCount = args["count"] as? Int ?? 0
    ocrCompleted = 0
    if #available(iOS 26.0, *), args["automatic"] as? Bool != true {
      // ContinuedProcessing requires a foreground user action. Automatic OCR
      // only uses finite UIKit time and durable restart/resume.
      let request = BGContinuedProcessingTaskRequest(
        identifier: ocrIdentifier, title: "OCR",
        subtitle: args["title"] as? String ?? "DartPDF")
      request.strategy = .fail
      do {
        try BGTaskScheduler.shared.submit(request)
        return
      } catch {
        // Resource pressure/disabled background refresh: finite time below.
      }
    }
    ocrBackgroundTime = UIApplication.shared.beginBackgroundTask(withName: "OCR") { [weak self] in
      self?.ocrChannel?.invokeMethod("expired", arguments: nil)
      self?.endOcr(success: false)
    }
  }

  private var keyboardChannel: FlutterMethodChannel?
  private var keyboardObservers: [NSObjectProtocol] = []

  deinit {
    keyboardObservers.forEach(NotificationCenter.default.removeObserver)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 26.0, *) {
      BGTaskScheduler.shared.register(forTaskWithIdentifier: ocrIdentifier, using: nil) { [weak self] task in
        guard let self = self, let continued = task as? BGContinuedProcessingTask else {
          task.setTaskCompleted(success: false)
          return
        }
        self.ocrTask = continued
        continued.progress.totalUnitCount = Int64(max(1, self.ocrCount))
        continued.progress.completedUnitCount = Int64(self.ocrCompleted)
        continued.expirationHandler = { [weak self] in
          // The system's Live Activity cancellation reaches this handler.
          // Honor it as cancellation; abrupt OS termination instead leaves
          // the running job available for checkpoint recovery.
          self?.ocrChannel?.invokeMethod("cancel", arguments: nil)
          self?.endOcr(success: false)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OcrBackground") {
      let channel = FlutterMethodChannel(name: "dev.milanko.dartpdf/ocr_background",
                                         binaryMessenger: registrar.messenger())
      ocrChannel = channel
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { result(nil); return }
        switch call.method {
        case "begin": self.beginOcr(call.arguments as? [String: Any] ?? [:]); result(nil)
        case "progress":
          let args = call.arguments as? [String: Any] ?? [:]
          self.ocrCompleted = args["completed"] as? Int ?? 0
          self.ocrCount = args["count"] as? Int ?? self.ocrCount
          if #available(iOS 26.0, *), let task = self.ocrTask as? BGContinuedProcessingTask {
            task.progress.totalUnitCount = Int64(max(1, self.ocrCount))
            task.progress.completedUnitCount = Int64(self.ocrCompleted)
          }
          result(nil)
        case "end": self.endOcr(success: call.arguments as? Bool ?? false); result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KeyboardAvailability") {
      let channel = FlutterMethodChannel(
        name: "dev.milanko.dartpdf/keyboard", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "isConnected" {
          result(GCKeyboard.coalesced != nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      keyboardChannel = channel
      keyboardObservers.forEach(NotificationCenter.default.removeObserver)
      keyboardObservers = [
        Notification.Name.GCKeyboardDidConnect,
        Notification.Name.GCKeyboardDidDisconnect,
      ].map { name in
        NotificationCenter.default.addObserver(
          forName: name, object: nil, queue: .main
        ) { [weak self] notification in
          // These notifications describe the first connection / last disconnection.
          self?.keyboardChannel?.invokeMethod(
            "changed", arguments: notification.name == .GCKeyboardDidConnect)
        }
      }
    }

  }
}
