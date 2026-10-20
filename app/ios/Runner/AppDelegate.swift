import Flutter
import GameController
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var keyboardChannel: FlutterMethodChannel?
  private var keyboardObservers: [NSObjectProtocol] = []

  deinit {
    keyboardObservers.forEach(NotificationCenter.default.removeObserver)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

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
