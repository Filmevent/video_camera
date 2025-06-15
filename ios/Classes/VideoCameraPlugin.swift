import Flutter
import UIKit

@objc(VideoCameraPlugin)
public class VideoCameraPlugin: NSObject, FlutterPlugin {
    @objc public static func register(with registrar: FlutterPluginRegistrar) {
        let factory = FLNativeViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "platform-view-type")
    }
}