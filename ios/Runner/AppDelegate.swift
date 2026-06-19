import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    private let gemmaHandler = GemmaInferenceHandler()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            fatalError("rootViewController is not a FlutterViewController")
        }

        let channel = FlutterMethodChannel(
            name: "com.example.translate_ko_jp/gemma",
            binaryMessenger: controller.binaryMessenger
        )

        channel.setMethodCallHandler { [weak self] (call, result) in
            self?.gemmaHandler.handle(call, result: result)
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
